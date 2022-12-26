[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)]
    [char] $DriveLetter,

    [Parameter(Mandatory = $false)]
    [string] $VolumeLabel = 'HCI Lab Data',

    [Parameter(Mandatory = $false)]
    [string] $StoragePoolName = 'hcisandboxpool'
)

$ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop
$ProgressPreference = [System.Management.Automation.ActionPreference]::SilentlyContinue

$logFolderPath = 'C:\Temp'
New-Item -ItemType Directory -Path $logFolderPath -Force
Start-Transcript -OutputDirectory $logFolderPath

# Create a storage pool.

New-StoragePool -FriendlyName $StoragePoolName -StorageSubSystemFriendlyName '*storage*' -PhysicalDisks (Get-PhysicalDisk -CanPool $true)

if ((Get-StoragePool -FriendlyName $StoragePoolName -ErrorAction SilentlyContinue).OperationalStatus -ne 'OK') {
    throw 'Storage pool creation failed.'
}

# Create a volume.

New-Volume -StoragePoolFriendlyName $StoragePoolName -FileSystem NTFS -AllocationUnitSize 64KB -ResiliencySettingName Simple -UseMaximumSize -DriveLetter $DriveLetter -FriendlyName $VolumeLabel

if ((Get-Volume -DriveLetter $DriveLetter -ErrorAction SilentlyContinue).OperationalStatus -ne 'OK') {
    throw 'Volume creation failed.'
}

$volumeRootPath = $DriveLetter + ':\'

# Set Defender exclusions.

Add-MpPreference -ExclusionPath $volumeRootPath

if ((Get-MpPreference).ExclusionPath -notcontains $volumeRootPath) {
    throw 'Defender exclusion setting failed.'
}

# Create the folder structure on the volume.

New-Item -ItemType Directory -Path ([IO.Path]::Combine($volumeRootPath, 'temp')) -Force
New-Item -ItemType Directory -Path ([IO.Path]::Combine($volumeRootPath, 'iso')) -Force
New-Item -ItemType Directory -Path ([IO.Path]::Combine($volumeRootPath, 'vhd')) -Force
New-Item -ItemType Directory -Path ([IO.Path]::Combine($volumeRootPath, 'vm')) -Force

Stop-Transcript
