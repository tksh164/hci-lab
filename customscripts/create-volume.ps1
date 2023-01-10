[CmdletBinding()]
param ()

$ErrorActionPreference = [Management.Automation.ActionPreference]::Stop
$WarningPreference = [Management.Automation.ActionPreference]::Continue
$VerbosePreference = [Management.Automation.ActionPreference]::Continue
$ProgressPreference = [Management.Automation.ActionPreference]::SilentlyContinue

Import-Module -Name '.\shared.psm1' -Force

$configParams = GetConfigParameters
Start-Transcript -OutputDirectory $configParams.labHost.folderPath.transcript
$configParams | ConvertTo-Json -Depth 16

WriteLog -Context $env:ComputerName -Message 'Creating a storage pool...'
$params = @{
    FriendlyName                 = $configParams.labHost.storage.poolName
    StorageSubSystemFriendlyName = '*storage*'
    PhysicalDisks                = Get-PhysicalDisk -CanPool $true
}
New-StoragePool @params
if ((Get-StoragePool -FriendlyName $params.FriendlyName -ErrorAction SilentlyContinue).OperationalStatus -ne 'OK') {
    throw 'Storage pool creation failed.'
}

WriteLog -Context $env:ComputerName -Message 'Creating a volume...'
$params = @{
    StoragePoolFriendlyName = $configParams.labHost.storage.poolName
    FileSystem              = 'NTFS'
    AllocationUnitSize      = 64KB
    ResiliencySettingName   = 'Simple'
    UseMaximumSize          = $true
    DriveLetter             = $configParams.labHost.storage.driveLetter
    FriendlyName            = $configParams.labHost.storage.volumeLabel
}
New-Volume @params
if ((Get-Volume -DriveLetter $params.DriveLetter -ErrorAction SilentlyContinue).OperationalStatus -ne 'OK') {
    throw 'Volume creation failed.'
}

WriteLog -Context $env:ComputerName -Message 'Setting Defender exclusions...'
$exclusionPath = $configParams.labHost.storage.driveLetter + ':\'
Add-MpPreference -ExclusionPath $exclusionPath
if ((Get-MpPreference).ExclusionPath -notcontains $exclusionPath) {
    throw 'Defender exclusion setting failed.'
}

WriteLog -Context $env:ComputerName -Message 'Creating the folder structure on the volume...'
New-Item -ItemType Directory -Path $configParams.labHost.folderPath.temp -Force
New-Item -ItemType Directory -Path $configParams.labHost.folderPath.updates -Force
New-Item -ItemType Directory -Path $configParams.labHost.folderPath.vhd -Force
New-Item -ItemType Directory -Path $configParams.labHost.folderPath.vm -Force

WriteLog -Context $env:ComputerName -Message 'The volume creation has been completed.'

Stop-Transcript
