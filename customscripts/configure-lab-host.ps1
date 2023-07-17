[CmdletBinding()]
param ()

$ErrorActionPreference = [Management.Automation.ActionPreference]::Stop
$WarningPreference = [Management.Automation.ActionPreference]::Continue
$VerbosePreference = [Management.Automation.ActionPreference]::Continue
$ProgressPreference = [Management.Automation.ActionPreference]::SilentlyContinue

function Invoke-WindowsTerminalInstallation
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateScript({ Test-Path -PathType Container -LiteralPath $_ })]
        [string] $DownloadFolderPath
    )

    'Downloading the Windows 10 pre-install kit zip file...' | Write-ScriptLog -Context $env:ComputerName
    $params = @{
        SourceUri      = 'https://github.com/microsoft/terminal/releases/download/v1.17.11461.0/Microsoft.WindowsTerminal_1.17.11461.0_8wekyb3d8bbwe.msixbundle_Windows10_PreinstallKit.zip'
        DownloadFolder = $DownloadFolderPath
        FileNameToSave = 'Microsoft.WindowsTerminal_Windows10_PreinstallKit.zip'
    }
    $zipFile = Invoke-FileDownload @params

    'Expaneding the Windows 10 pre-install kit zip file...' | Write-ScriptLog -Context $env:ComputerName
    $fileSourceFolder = [IO.Path]::Combine([IO.Path]::GetDirectoryName($zipFile.FullName), [IO.Path]::GetFileNameWithoutExtension($zipFile.FullName))
    Expand-Archive -LiteralPath $zipFile.FullName -DestinationPath $fileSourceFolder -Force

    # Retrieve the Windows Termainl intallation files.
    $vcLibsAppxFile = Get-ChildItem -LiteralPath $fileSourceFolder -Filter 'Microsoft.VCLibs.*.UWPDesktop_*_x64__*.appx' | Select-Object -First 1
    $uiXamlAppxFile = Get-ChildItem -LiteralPath $fileSourceFolder -Filter 'Microsoft.UI.Xaml.*_x64__*.appx' | Select-Object -First 1
    $msixBundleFile = Get-ChildItem -LiteralPath $fileSourceFolder -Filter '*.msixbundle' | Select-Object -First 1
    $licenseXmlFile = Get-ChildItem -LiteralPath $fileSourceFolder -Filter '*_License1.xml' | Select-Object -First 1

    'Microsoft.VCLibs: "{0}"' -f $vcLibsAppxFile.FullName | Write-ScriptLog -Context $env:ComputerName
    'Microsoft.UI.Xaml: "{0}"' -f $uiXamlAppxFile.FullName | Write-ScriptLog -Context $env:ComputerName
    'Microsoft.WindowsTerminal: "{0}"' -f $msixBundleFile.FullName | Write-ScriptLog -Context $env:ComputerName
    'LicenseXml: "{0}"' -f $licenseXmlFile.FullName | Write-ScriptLog -Context $env:ComputerName

    'Installing the dependency packages for Windows Terminal...' | Write-ScriptLog -Context $env:ComputerName
    Add-AppxProvisionedPackage -Online -SkipLicense -PackagePath $vcLibsAppxFile.FullName
    Add-AppxProvisionedPackage -Online -SkipLicense -PackagePath $uiXamlAppxFile.FullName

    'Creating a script file for the Windows Terminal installation scheduled task...' | Write-ScriptLog -Context $env:ComputerName
    $scheduledTaskName = 'WindowsTermailInstallation'
    $scheduledTaskScriptFileContent = @"
(Get-Host).UI.RawUI.WindowTitle = 'Windows Terminal installation'
Write-Host 'Finishing up the Windows Terminal installation...' -ForegroundColor Yellow
Add-AppxProvisionedPackage -Online -PackagePath '{0}' -LicensePath '{1}'
Disable-ScheduledTask -TaskName '{2}' -TaskPath '\'
"@ -f $msixBundleFile.FullName, $licenseXmlFile.FullName, $scheduledTaskName
    $scheduledTaskScriptFilePath = [IO.Path]::Combine($DownloadFolderPath, $scheduledTaskName + 'Task.ps1')
    Set-Content -LiteralPath $scheduledTaskScriptFilePath -Value $scheduledTaskScriptFileContent -Force

    'Creating a scheduled task for Windows Terminal installation...' | Write-ScriptLog -Context $env:ComputerName
    $adminUsername = Get-InstanceMetadata -FilterPath '/compute/osProfile/adminUsername' -LeafNode
    $params = @{
        TaskName = $scheduledTaskName
        TaskPath = '\'
        User     = $adminUsername
        RunLevel = 'Highest'
        Trigger  = New-ScheduledTaskTrigger -AtLogOn -User $adminUsername
        Action   = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument ('-NoLogo -NonInteractive -WindowStyle Minimized -File "{0}"' -f $scheduledTaskScriptFilePath)
        Force    = $true
    }
    Register-ScheduledTask @params
}

function Invoke-VSCodeInstallation
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateScript({ Test-Path -PathType Container -LiteralPath $_ })]
        [string] $DownloadFolderPath
    )

    'Downloading the Visual Studio Code system installer...' | Write-ScriptLog -Context $env:ComputerName
    $params = @{
        SourceUri      = 'https://code.visualstudio.com/sha/download?build=stable&os=win32-x64'
        DownloadFolder = $DownloadFolderPath
        FileNameToSave = 'VSCodeSetup-x64.exe'
    }
    $installerFile = Invoke-FileDownload @params

    'Installing the Visual Studio Code...' | Write-ScriptLog -Context $env:ComputerName
    $mergeTasks = @(
        'desktopicon',
        '!quicklaunchicon',
        'addcontextmenufiles',
        'addcontextmenufolders',
        'associatewithfiles',
        'addtopath',
        '!runcode'
    )
    $params = @{
        FilePath     = $installerFile.FullName
        ArgumentList = '/verysilent /suppressmsgboxes /mergetasks="{0}"' -f ($mergeTasks -join ',')
        Wait         = $true
        PassThru     = $true
    }
    Start-Process @params
}

Import-Module -Name ([IO.Path]::Combine($PSScriptRoot, 'common.psm1')) -Force

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
