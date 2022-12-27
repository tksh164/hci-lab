[CmdletBinding()]
param ()

$ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop
$ProgressPreference = [System.Management.Automation.ActionPreference]::SilentlyContinue

Import-Module -Name '.\common.psm1'

# Retrieve the configuration parameters.
$configParams = GetConfigParameters
$configParams

Start-Transcript -OutputDirectory ([IO.Path]::Combine($configParams.transcriptFolder, $MyInvocation.MyCommand.Name + '.log'))

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
