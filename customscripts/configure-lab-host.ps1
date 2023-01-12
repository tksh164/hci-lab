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

# Volume

'Creating a storage pool...' | WriteLog -Context $env:ComputerName
$params = @{
    FriendlyName                 = $configParams.labHost.storage.poolName
    StorageSubSystemFriendlyName = '*storage*'
    PhysicalDisks                = Get-PhysicalDisk -CanPool $true
}
New-StoragePool @params
if ((Get-StoragePool -FriendlyName $params.FriendlyName -ErrorAction SilentlyContinue).OperationalStatus -ne 'OK') {
    throw 'Storage pool creation failed.'
}

'Creating a volume...' | WriteLog -Context $env:ComputerName
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

'Setting Defender exclusions...' | WriteLog -Context $env:ComputerName
$exclusionPath = $configParams.labHost.storage.driveLetter + ':\'
Add-MpPreference -ExclusionPath $exclusionPath
if ((Get-MpPreference).ExclusionPath -notcontains $exclusionPath) {
    throw 'Defender exclusion setting failed.'
}

'Creating the folder structure on the volume...' | WriteLog -Context $env:ComputerName
New-Item -ItemType Directory -Path $configParams.labHost.folderPath.temp -Force
New-Item -ItemType Directory -Path $configParams.labHost.folderPath.updates -Force
New-Item -ItemType Directory -Path $configParams.labHost.folderPath.vhd -Force
New-Item -ItemType Directory -Path $configParams.labHost.folderPath.vm -Force

'The volume creation has been completed.' | WriteLog -Context $env:ComputerName

# Hyper-V

'Configuring Hyper-V host settings...' | WriteLog -Context $env:ComputerName
$params = @{
    VirtualMachinePath        = $configParams.labHost.folderPath.vm
    VirtualHardDiskPath       = $configParams.labHost.folderPath.vhd
    EnableEnhancedSessionMode = $true
}
Set-VMHost @params

'Creating a NAT vSwitch...' | WriteLog -Context $env:ComputerName
$params = @{
    Name        = $configParams.labHost.vSwitch.nat.name
    SwitchType  = 'Internal'
}
New-VMSwitch @params

'Creating a network NAT...' | WriteLog -Context $env:ComputerName
$params = @{
    Name                             = $configParams.labHost.vSwitch.nat.name
    InternalIPInterfaceAddressPrefix = $configParams.labHost.vSwitch.nat.subnet
}
New-NetNat @params

'Assigning an IP address to the NAT vSwitch network interface...' | WriteLog -Context $env:ComputerName
$params= @{
    InterfaceIndex = (Get-NetAdapter | Where-Object { $_.Name -match $configParams.labHost.vSwitch.nat.name }).ifIndex
    AddressFamily  = 'IPv4'
    IPAddress      = $configParams.labHost.vSwitch.nat.hostIPAddress
    PrefixLength   = $configParams.labHost.vSwitch.nat.hostPrefixLength
}
New-NetIPAddress @params

'The Hyper-V configuration has been completed.' | WriteLog -Context $env:ComputerName

# Tweaks

'Setting to stop Server Manager launch at logon.' | WriteLog -Context $env:ComputerName
Set-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\ServerManager' -Name 'DoNotOpenServerManagerAtLogon' -Value 1

'Setting to stop Windows Admin Center popup at Server Manager launch.' | WriteLog -Context $env:ComputerName
Set-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\ServerManager' -Name 'DoNotPopWACConsoleAtSMLaunch' -Value 1

'Setting to hide the Network Location wizard. All networks will be Public.' | WriteLog -Context $env:ComputerName
New-Item -ItemType Directory -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Network' -Name 'NewNetworkWindowOff'

'Some tweaks have been completed.' | WriteLog -Context $env:ComputerName

Stop-Transcript
