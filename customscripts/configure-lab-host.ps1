[CmdletBinding()]
param ()

$ErrorActionPreference = [Management.Automation.ActionPreference]::Stop
$WarningPreference = [Management.Automation.ActionPreference]::Continue
$VerbosePreference = [Management.Automation.ActionPreference]::Continue
$ProgressPreference = [Management.Automation.ActionPreference]::SilentlyContinue

Import-Module -Name '.\shared.psm1' -Force

$labConfig = GetLabConfig
Start-ScriptTranscript -OutputDirectory $labConfig.labHost.folderPath.log -ScriptName $MyInvocation.MyCommand.Name
$labConfig | ConvertTo-Json -Depth 16

# Volume

'Creating a storage pool...' | WriteLog -Context $env:ComputerName
$params = @{
    FriendlyName                 = $labConfig.labHost.storage.poolName
    StorageSubSystemFriendlyName = '*storage*'
    PhysicalDisks                = Get-PhysicalDisk -CanPool $true
}
New-StoragePool @params
if ((Get-StoragePool -FriendlyName $params.FriendlyName -ErrorAction SilentlyContinue).OperationalStatus -ne 'OK') {
    throw 'Storage pool creation failed.'
}

'Creating a volume...' | WriteLog -Context $env:ComputerName
$params = @{
    StoragePoolFriendlyName = $labConfig.labHost.storage.poolName
    FileSystem              = 'ReFS'
    AllocationUnitSize      = 4KB
    ResiliencySettingName   = 'Simple'
    UseMaximumSize          = $true
    DriveLetter             = $labConfig.labHost.storage.driveLetter
    FriendlyName            = $labConfig.labHost.storage.volumeLabel
}
New-Volume @params
if ((Get-Volume -DriveLetter $params.DriveLetter -ErrorAction SilentlyContinue).OperationalStatus -ne 'OK') {
    throw 'Volume creation failed.'
}

'Setting Defender exclusions...' | WriteLog -Context $env:ComputerName
$exclusionPath = $labConfig.labHost.storage.driveLetter + ':\'
Add-MpPreference -ExclusionPath $exclusionPath
if ((Get-MpPreference).ExclusionPath -notcontains $exclusionPath) {
    throw 'Defender exclusion setting failed.'
}

'Creating the folder structure on the volume...' | WriteLog -Context $env:ComputerName
New-Item -ItemType Directory -Path $labConfig.labHost.folderPath.temp -Force
New-Item -ItemType Directory -Path $labConfig.labHost.folderPath.updates -Force
New-Item -ItemType Directory -Path $labConfig.labHost.folderPath.vhd -Force
New-Item -ItemType Directory -Path $labConfig.labHost.folderPath.vm -Force

'The volume creation has been completed.' | WriteLog -Context $env:ComputerName

# Hyper-V

'Configuring Hyper-V host settings...' | WriteLog -Context $env:ComputerName
$params = @{
    VirtualMachinePath        = $labConfig.labHost.folderPath.vm
    VirtualHardDiskPath       = $labConfig.labHost.folderPath.vhd
    EnableEnhancedSessionMode = $true
}
Set-VMHost @params

'Creating a NAT vSwitch...' | WriteLog -Context $env:ComputerName
$params = @{
    Name        = $labConfig.labHost.vSwitch.nat.name
    SwitchType  = 'Internal'
}
New-VMSwitch @params

'Creating a network NAT...' | WriteLog -Context $env:ComputerName
$params = @{
    Name                             = $labConfig.labHost.vSwitch.nat.name
    InternalIPInterfaceAddressPrefix = $labConfig.labHost.vSwitch.nat.subnet
}
New-NetNat @params

'Assigning an IP address to the NAT vSwitch network interface...' | WriteLog -Context $env:ComputerName
$params= @{
    InterfaceIndex = (Get-NetAdapter | Where-Object { $_.Name -match $labConfig.labHost.vSwitch.nat.name }).ifIndex
    AddressFamily  = 'IPv4'
    IPAddress      = $labConfig.labHost.vSwitch.nat.hostIPAddress
    PrefixLength   = $labConfig.labHost.vSwitch.nat.hostPrefixLength
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

'Creating shortcut for Hyper-V Manager on the desktop....' | WriteLog -Context $env:ComputerName
$wshShell = New-Object -ComObject 'WScript.Shell'
$shortcut = $wshShell.CreateShortcut('C:\Users\Public\Desktop\Hyper-V Manager.lnk')
$shortcut.TargetPath = '%windir%\System32\mmc.exe'
$shortcut.Arguments = '"%windir%\System32\virtmgmt.msc"'
$shortcut.Description = 'Hyper-V Manager provides management access to your virtualization platform.'
$shortcut.IconLocation = '%ProgramFiles%\Hyper-V\SnapInAbout.dll,0'
$shortcut.Save()

'Creating shortcut for Windows Admin Center VM on the desktop....' | WriteLog -Context $env:ComputerName
$wshShell = New-Object -ComObject 'WScript.Shell'
$shortcut = $wshShell.CreateShortcut('C:\Users\Public\Desktop\Windows Admin Center VM.lnk')
$shortcut.TargetPath = '%windir%\System32\mstsc.exe'
$shortcut.Arguments = '/v:{0}' -f $labConfig.wac.vmName  # The VM name is also the computer name.
$shortcut.Description = 'Windows Admin Center VM provides management access to your lab environment.'
$shortcut.Save()

'Creating shortcut for Windows Admin Center on the desktop....' | WriteLog -Context $env:ComputerName
$wshShell = New-Object -ComObject 'WScript.Shell'
$shortcut = $wshShell.CreateShortcut('C:\Users\Public\Desktop\Windows Admin Center.lnk')
$shortcut.TargetPath = 'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe'
$shortcut.Arguments = 'https://{0}' -f $labConfig.wac.vmName  # The VM name is also the computer name.
$shortcut.Description = 'Windows Admin Center for the lab environment.'
$shortcut.IconLocation = 'imageres.dll,1'
$shortcut.Save()

'Some tweaks have been completed.' | WriteLog -Context $env:ComputerName

Stop-ScriptTranscript
