[CmdletBinding()]
param ()

$ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop
$ProgressPreference = [System.Management.Automation.ActionPreference]::SilentlyContinue

Import-Module -Name '.\common.psm1'

$configParams = GetConfigParameters
Start-Transcript -OutputDirectory $configParams.folderPath.transcript
$configParams

# Create a storage pool.

New-StoragePool -FriendlyName $configParams.labHostStorage.storagePoolName -StorageSubSystemFriendlyName '*storage*' -PhysicalDisks (Get-PhysicalDisk -CanPool $true)
if ((Get-StoragePool -FriendlyName $configParams.labHostStorage.storagePoolName -ErrorAction SilentlyContinue).OperationalStatus -ne 'OK') {
    throw 'Storage pool creation failed.'
}

# Create a volume.

New-Volume -StoragePoolFriendlyName $configParams.labHostStorage.storagePoolName -FileSystem NTFS -AllocationUnitSize 64KB -ResiliencySettingName Simple -UseMaximumSize -DriveLetter $configParams.labHostStorage.driveLetter -FriendlyName $configParams.labHostStorage.volumeLabel
if ((Get-Volume -DriveLetter $configParams.labHostStorage.driveLetter -ErrorAction SilentlyContinue).OperationalStatus -ne 'OK') {
    throw 'Volume creation failed.'
}

# Set Defender exclusions.

$exclusionPath = $configParams.labHostStorage.driveLetter + ':\'
Add-MpPreference -ExclusionPath $exclusionPath
if ((Get-MpPreference).ExclusionPath -notcontains $exclusionPath) {
    throw 'Defender exclusion setting failed.'
}

# Create the folder structure on the volume.

New-Item -ItemType Directory -Path $configParams.folderPath.temp -Force
New-Item -ItemType Directory -Path $configParams.folderPath.vhd -Force
New-Item -ItemType Directory -Path $configParams.folderPath.vm -Force

Stop-Transcript
