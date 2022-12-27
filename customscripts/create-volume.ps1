[CmdletBinding()]
param (
    [Parameter(Mandatory = $false)]
    [string] $ConfigParametersFile = '.\config-parameters.json'
)

$ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop
$ProgressPreference = [System.Management.Automation.ActionPreference]::SilentlyContinue

$logFolderPath = 'C:\Temp'
New-Item -ItemType Directory -Path $logFolderPath -Force
Start-Transcript -OutputDirectory $logFolderPath

Import-Module -Name '.\common.psm1'

$configParams = GetConfigParametersFromJsonFile -FilePath $ConfigParametersFile

# Create a storage pool.

New-StoragePool -FriendlyName $configParams.storagePoolName -StorageSubSystemFriendlyName '*storage*' -PhysicalDisks (Get-PhysicalDisk -CanPool $true)

if ((Get-StoragePool -FriendlyName $configParams.storagePoolName -ErrorAction SilentlyContinue).OperationalStatus -ne 'OK') {
    throw 'Storage pool creation failed.'
}

# Create a volume.

New-Volume -StoragePoolFriendlyName $configParams.storagePoolName -FileSystem NTFS -AllocationUnitSize 64KB -ResiliencySettingName Simple -UseMaximumSize -DriveLetter $configParams.driveLetter -FriendlyName $configParams.volumeLabel

if ((Get-Volume -DriveLetter $configParams.driveLetter -ErrorAction SilentlyContinue).OperationalStatus -ne 'OK') {
    throw 'Volume creation failed.'
}

# Set Defender exclusions.

$exclusionPath = $configParams.driveLetter + ':\'
Add-MpPreference -ExclusionPath $exclusionPath

if ((Get-MpPreference).ExclusionPath -notcontains $exclusionPath) {
    throw 'Defender exclusion setting failed.'
}

# Create the folder structure on the volume.

New-Item -ItemType Directory -Path $configParams.tempFolder -Force
New-Item -ItemType Directory -Path $configParams.vhdFolder -Force
New-Item -ItemType Directory -Path $configParams.vmFolder -Force

Stop-Transcript
