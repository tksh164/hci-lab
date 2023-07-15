[CmdletBinding()]
param ()

$ErrorActionPreference = [Management.Automation.ActionPreference]::Stop
$WarningPreference = [Management.Automation.ActionPreference]::Continue
$VerbosePreference = [Management.Automation.ActionPreference]::Continue
$ProgressPreference = [Management.Automation.ActionPreference]::SilentlyContinue

Import-Module -Name ([IO.Path]::Combine($PSScriptRoot, 'shared.psm1')) -Force

$labConfig = Get-LabDeploymentConfig
Start-ScriptLogging -OutputDirectory $labConfig.labHost.folderPath.log
$labConfig | ConvertTo-Json -Depth 16 | Write-Host

# Volume

'Creating a storage pool...' | Write-ScriptLog -Context $env:ComputerName
$params = @{
    FriendlyName                 = $labConfig.labHost.storage.poolName
    StorageSubSystemFriendlyName = '*storage*'
    PhysicalDisks                = Get-PhysicalDisk -CanPool $true
}
New-StoragePool @params
if ((Get-StoragePool -FriendlyName $params.FriendlyName -ErrorAction SilentlyContinue).OperationalStatus -ne 'OK') {
    throw 'Storage pool creation failed.'
}

'Creating a volume...' | Write-ScriptLog -Context $env:ComputerName
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

'Setting Defender exclusions...' | Write-ScriptLog -Context $env:ComputerName
$exclusionPath = $labConfig.labHost.storage.driveLetter + ':\'
Add-MpPreference -ExclusionPath $exclusionPath
if ((Get-MpPreference).ExclusionPath -notcontains $exclusionPath) {
    throw 'Defender exclusion setting failed.'
}

'Creating the folder structure on the volume...' | Write-ScriptLog -Context $env:ComputerName
New-Item -ItemType Directory -Path $labConfig.labHost.folderPath.temp -Force
New-Item -ItemType Directory -Path $labConfig.labHost.folderPath.updates -Force
New-Item -ItemType Directory -Path $labConfig.labHost.folderPath.vhd -Force
New-Item -ItemType Directory -Path $labConfig.labHost.folderPath.vm -Force

'The volume creation has been completed.' | Write-ScriptLog -Context $env:ComputerName

# Hyper-V

'Configuring Hyper-V host settings...' | Write-ScriptLog -Context $env:ComputerName
$params = @{
    VirtualMachinePath        = $labConfig.labHost.folderPath.vm
    VirtualHardDiskPath       = $labConfig.labHost.folderPath.vhd
    EnableEnhancedSessionMode = $true
}
Set-VMHost @params

'Creating a NAT vSwitch...' | Write-ScriptLog -Context $env:ComputerName
$params = @{
    Name       = $labConfig.labHost.vSwitch.nat.name
    SwitchType = 'Internal'
}
New-VMSwitch @params

'Enabling forwarding on the host''s NAT network interfaces...' | Write-ScriptLog -Context $env:ComputerName
$paramsForGet = @{
    InterfaceAlias = '*{0}*' -f $labConfig.labHost.vSwitch.nat.name
}
$paramsForSet = @{
    Forwarding = 'Enabled'
}
Get-NetIPInterface @paramsForGet | Set-NetIPInterface @paramsForSet

foreach ($netNat in $labConfig.labHost.netNat) {
    'Creating a network NAT "{0}"...' -f $netNat.name | Write-ScriptLog -Context $env:ComputerName
    $params = @{
        Name                             = $netNat.name
        InternalIPInterfaceAddressPrefix = $netNat.InternalAddressPrefix
    }
    New-NetNat @params

    'Assigning an internal IP configuration to the host''s NAT network interface...' | Write-ScriptLog -Context $env:ComputerName
    $params= @{
        InterfaceIndex = (Get-NetAdapter -Name ('*{0}*' -f $labConfig.labHost.vSwitch.nat.name)).ifIndex
        AddressFamily  = 'IPv4'
        IPAddress      = $netNat.hostInternalIPAddress
        PrefixLength   = $netNat.hostInternalPrefixLength
    }
    New-NetIPAddress @params
}

'The Hyper-V configuration has been completed.' | Write-ScriptLog -Context $env:ComputerName

# Tweaks

'Setting to stop Server Manager launch at logon.' | Write-ScriptLog -Context $env:ComputerName
Set-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\ServerManager' -Name 'DoNotOpenServerManagerAtLogon' -Value 1

'Setting to stop Windows Admin Center popup at Server Manager launch.' | Write-ScriptLog -Context $env:ComputerName
Set-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\ServerManager' -Name 'DoNotPopWACConsoleAtSMLaunch' -Value 1

'Setting to hide the Network Location wizard. All networks will be Public.' | Write-ScriptLog -Context $env:ComputerName
New-RegistryKey -ParentPath 'HKLM:\SYSTEM\CurrentControlSet\Control\Network' -KeyName 'NewNetworkWindowOff'

'Setting to hide the first run experience of Microsoft Edge.' | Write-ScriptLog -Context $env:ComputerName
New-RegistryKey -ParentPath 'HKLM:\SOFTWARE\Policies\Microsoft' -KeyName 'Edge'
Set-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' -Name 'HideFirstRunExperience' -Value 1

# Shortcuts: Windows Admin Center

'Creating a shortcut for open Windows Admin Center on the desktop....' | Write-ScriptLog -Context $env:ComputerName
$params = @{
    ShortcutFilePath = 'C:\Users\Public\Desktop\Windows Admin Center.lnk'
    TargetPath       = 'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe'
    Arguments        = 'https://{0}' -f $labConfig.wac.vmName  # The VM name is also the computer name.
    Description      = 'Open Windows Admin Center for your lab environment.'
    IconLocation     = 'imageres.dll,1'
}
New-ShortcutFile @params

# Shortcuts: Remote Desktop connection

'Creating a shortcut for Remote Desktop connection to the Windows Admin Center VM on the desktop....' | Write-ScriptLog -Context $env:ComputerName
$params = @{
    ShortcutFilePath = 'C:\Users\Public\Desktop\RDC - WAC.lnk'
    TargetPath       = '%windir%\System32\mstsc.exe'
    Arguments        = '/v:{0}' -f $labConfig.wac.vmName  # The VM name is also the computer name.
    Description      = 'Make a remote desktop connection to the Windows Admin Center VM in your lab environment.'
}
New-ShortcutFile @params

$firstHciNodeName = Format-HciNodeName -Format $labConfig.hciNode.vmName -Offset $labConfig.hciNode.vmNameOffset -Index 0
'Creating a shortcut for Remote Desktop connection to the {0} VM on the desktop...' -f $firstHciNodeName | Write-ScriptLog -Context $env:ComputerName
$params = @{
    ShortcutFilePath = 'C:\Users\Public\Desktop\RDC - {0}.lnk' -f $firstHciNodeName
    TargetPath       = '%windir%\System32\mstsc.exe'
    Arguments        = '/v:{0}' -f $firstHciNodeName  # The VM name is also the computer name.
    Description      = 'Make a remote desktop connection to the member node "{0}" VM of the HCI cluster in your lab environment.' -f $firstHciNodeName
}
New-ShortcutFile @params

# Shortcuts: VMConnect

'Creating a shortcut for VMConnect to the AD DS DC VM on the desktop....' | Write-ScriptLog -Context $env:ComputerName
$params = @{
    ShortcutFilePath = 'C:\Users\Public\Desktop\VM - AD DS DC.lnk'
    TargetPath       = '%windir%\System32\vmconnect.exe'
    Arguments        = 'localhost {0}' -f $labConfig.addsDC.vmName  # The VM name is also the computer name.
    Description      = 'Open VMConnect for the AD DS DC VM in your lab environment.'
}
New-ShortcutFile @params

'Creating a shortcut for VMConnect to the Windows Admin Center VM on the desktop....' | Write-ScriptLog -Context $env:ComputerName
$params = @{
    ShortcutFilePath = 'C:\Users\Public\Desktop\VM - WAC.lnk'
    TargetPath       = '%windir%\System32\vmconnect.exe'
    Arguments        = 'localhost {0}' -f $labConfig.wac.vmName  # The VM name is also the computer name.
    Description      = 'Open VMConnect for the Windows Admin Center VM in your lab environment.'
}
New-ShortcutFile @params

'Creating a shortcut for VMConnect to the {0} VM on the desktop...' -f $firstHciNodeName | Write-ScriptLog -Context $env:ComputerName
$params = @{
    ShortcutFilePath = 'C:\Users\Public\Desktop\VM - {0}.lnk' -f $firstHciNodeName
    TargetPath       = '%windir%\System32\vmconnect.exe'
    Arguments        = 'localhost {0}' -f $firstHciNodeName  # The VM name is also the computer name.
    Description      = 'Open VMConnect for the HCI node VM "{0}" in your lab environment.' -f $firstHciNodeName
}
New-ShortcutFile @params

# Shortcuts: Hyper-V Manager

'Creating a shortcut for Hyper-V Manager on the desktop....' | Write-ScriptLog -Context $env:ComputerName
$params = @{
    ShortcutFilePath = 'C:\Users\Public\Desktop\Hyper-V Manager.lnk'
    TargetPath       = '%windir%\System32\mmc.exe'
    Arguments        = '"%windir%\System32\virtmgmt.msc"'
    Description      = 'Hyper-V Manager provides management access to virtual machines in your lab environment.'
    IconLocation     = '%ProgramFiles%\Hyper-V\SnapInAbout.dll,0'
}
New-ShortcutFile @params

'Some tweaks have been completed.' | Write-ScriptLog -Context $env:ComputerName

Stop-ScriptLogging
