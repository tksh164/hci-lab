[CmdletBinding()]
param ()

$ErrorActionPreference = [Management.Automation.ActionPreference]::Stop
$WarningPreference = [Management.Automation.ActionPreference]::Continue
$VerbosePreference = [Management.Automation.ActionPreference]::Continue
$ProgressPreference = [Management.Automation.ActionPreference]::SilentlyContinue

function Invoke-VSCodeInstallation
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateScript({ Test-Path -PathType Container -LiteralPath $_ })]
        [string] $DownloadFolderPath
    )

    'Download the Visual Studio Code system installer.' | Write-ScriptLog
    $params = @{
        SourceUri      = 'https://code.visualstudio.com/sha/download?build=stable&os=win32-x64'
        DownloadFolder = $DownloadFolderPath
        FileNameToSave = 'VSCodeSetup-x64.exe'
    }
    $installerFile = Invoke-FileDownload @params
    'Download the Visual Studio Code system installer completed.' | Write-ScriptLog

    'Install Visual Studio Code.' | Write-ScriptLog
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
    $result = Start-Process @params
    $result | Format-List -Property @(
        @{ Label = 'FileName'; Expression = { $_.StartInfo.FileName } },
        @{ Label = 'Arguments'; Expression = { $_.StartInfo.Arguments } },
        @{ Label = 'WorkingDirectory'; Expression = { $_.StartInfo.WorkingDirectory } },
        'Id',
        'HasExited',
        'ExitCode',
        'StartTime',
        'ExitTime',
        'TotalProcessorTime',
        'PrivilegedProcessorTime',
        'UserProcessorTime'
    ) | Out-String | Write-ScriptLog
    'Install Visual Studio Code completed.' | Write-ScriptLog
}

try {
    Import-Module -Name ([IO.Path]::Combine($PSScriptRoot, 'common.psm1')) -Force

    $labConfig = Get-LabDeploymentConfig
    Start-ScriptLogging -OutputDirectory $labConfig.labHost.folderPath.log

    'Lab deployment config:' | Write-ScriptLog
    $labConfig | ConvertTo-Json -Depth 16 | Write-Host

    # Volume

    'Create a new storage pool.' | Write-ScriptLog
    $params = @{
        FriendlyName                 = $labConfig.labHost.storage.poolName
        StorageSubSystemFriendlyName = '*storage*'
        PhysicalDisks                = Get-PhysicalDisk -CanPool $true
    }
    $storagePool = New-StoragePool @params
    $storagePool | Format-List -Property '*'
    'Create a new storage pool completed.' | Write-ScriptLog

    'Create a new virtual disk.' | Write-ScriptLog
    $params = @{
        StoragePoolFriendlyName = $labConfig.labHost.storage.poolName
        FriendlyName            = $labConfig.labHost.storage.volumeLabel
        UseMaximumSize          = $true
        AllocationUnitSize      = 1GB
        ResiliencySettingName   = 'Simple'
        NumberOfColumns         = ($storagePool | Get-PhysicalDisk).Length
        Interleave              = 64KB
    }
    $virtualDisk = New-VirtualDisk @params
    $virtualDisk | Format-List -Property '*'
    'Create a new virtual disk completed.' | Write-ScriptLog

    'Initialize the virtual disk.' | Write-ScriptLog
    $params = @{
        UniqueId       = $virtualDisk.UniqueId
        PartitionStyle = 'GPT'
        Passthru       = $true
    }
    $disk = Initialize-Disk @params
    $disk | Format-List -Property '*'
    'Initialize the virtual disk completed.' | Write-ScriptLog

    'Create a new partition.' | Write-ScriptLog
    $params = @{
        DriveLetter    = $labConfig.labHost.storage.driveLetter
        UseMaximumSize = $true
    }
    $partition = $disk | New-Partition @params
    $partition | Format-List -Property '*'
    'Create a new partition completed.' | Write-ScriptLog

    'Format the partition.' | Write-ScriptLog
    $params = @{
        FileSystem         = 'ReFS'
        AllocationUnitSize = 4KB
        NewFileSystemLabel = $labConfig.labHost.storage.volumeLabel
    }
    $volume = $partition | Format-Volume @params
    $volume | Format-List -Property '*'
    'Format the partition completed.' | Write-ScriptLog

    # Folder structure

    'Create the folder structure on the volume.' | Write-ScriptLog
    New-Item -ItemType Directory -Path $labConfig.labHost.folderPath.temp -Force
    New-Item -ItemType Directory -Path $labConfig.labHost.folderPath.updates -Force
    New-Item -ItemType Directory -Path $labConfig.labHost.folderPath.vhd -Force
    New-Item -ItemType Directory -Path $labConfig.labHost.folderPath.vm -Force
    'Create the folder structure on the volume completed.' | Write-ScriptLog

    # Disable WinSxS clean up

    'Disable WinSxS clean up.' | Write-ScriptLog
    Disable-ScheduledTask -TaskName 'StartComponentCleanup' -TaskPath '\Microsoft\Windows\Servicing'
    'Disable WinSxS clean up completed.' | Write-ScriptLog

    # Stop and disable SysMain service

    Stop-Service -Name 'SysMain' -NoWait
    Set-Service -Name 'SysMain' -StartupType Disabled

    # Defender configuration

    'Set Defender exclusions.' | Write-ScriptLog
    $exclusionPaths = @(
        ($volume.DriveLetter + ':\'),
        '%SystemDrive%\Temp\hcilab-logs',
        '%ProgramData%\Microsoft\Windows\Hyper-V',
        '%ProgramData%\Microsoft\Windows\Hyper-V\Snapshots',
        '%Public%\Documents\Hyper-V\Virtual Hard Disks'
    )
    $exclusionExtensions = @(
        '.vhd',
        '.vhdx',
        '.avhd',
        '.avhdx',
        '.vhds',
        '.vhdpmem',
        '.iso',
        '.rct',
        '.mrt',
        '.vsv',
        '.bin',
        '.xml',
        '.vmcx',
        '.vmrs',
        '.vmgs'
    )
    $exclusionProcess = @(
        '%SystemRoot%\System32\vmms.exe',
        '%SystemRoot%\System32\vmwp.exe',
        '%SystemRoot%\System32\vmsp.exe',
        '%SystemRoot%\System32\vmcompute.exe'
    )
    Add-MpPreference -ExclusionPath $exclusionPaths -ExclusionExtension $exclusionExtensions -ExclusionProcess $exclusionProcess
    'Set Defender exclusions completed.' | Write-ScriptLog

    # Hyper-V

    'Configure Hyper-V host settings.' | Write-ScriptLog
    $params = @{
        VirtualMachinePath        = $labConfig.labHost.folderPath.vm
        VirtualHardDiskPath       = $labConfig.labHost.folderPath.vhd
        EnableEnhancedSessionMode = $true
    }
    Set-VMHost @params
    'Configure Hyper-V host settings completed.' | Write-ScriptLog

    # NAT

    'Create a new NAT vSwitch.' | Write-ScriptLog
    $params = @{
        Name       = $labConfig.labHost.vSwitch.nat.name
        SwitchType = 'Internal'
    }
    New-VMSwitch @params
    'Create a new NAT vSwitch completed.' | Write-ScriptLog

    'Enable forwarding on the lab host''s NAT network interface.' | Write-ScriptLog
    $params = @{
        InterfaceAlias = '*{0}*' -f $labConfig.labHost.vSwitch.nat.name
    }
    Get-NetIPInterface @params | Set-NetIPInterface -Forwarding 'Enabled'
    'Enable forwarding on the lab host''s NAT network interface completed.' | Write-ScriptLog

    foreach ($netNat in $labConfig.labHost.netNat) {
        'Create a new network NAT "{0}".' -f $netNat.name | Write-ScriptLog
        $params = @{
            Name                             = $netNat.name
            InternalIPInterfaceAddressPrefix = $netNat.InternalAddressPrefix
        }
        New-NetNat @params
        'Create a new network NAT "{0}" completed.' -f $netNat.name | Write-ScriptLog

        'Assign an internal IP configuration to the host''s NAT network interface.' | Write-ScriptLog
        $params= @{
            InterfaceIndex = (Get-NetAdapter -Name ('*{0}*' -f $labConfig.labHost.vSwitch.nat.name)).ifIndex
            AddressFamily  = 'IPv4'
            IPAddress      = $netNat.hostInternalIPAddress
            PrefixLength   = $netNat.hostInternalPrefixLength
        }
        New-NetIPAddress @params
        'Assign an internal IP configuration to the host''s NAT network interface completed.' | Write-ScriptLog
    }

    # Tweaks for Windows

    'Disable diagnostics data send screen.' | Write-ScriptLog
    New-RegistryKey -ParentPath 'HKLM:\SOFTWARE\Policies\Microsoft\Windows' -KeyName 'OOBE'
    Set-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\OOBE' -Name 'DisablePrivacyExperience' -Value 1
    'Disable diagnostics data send screen completed.' | Write-ScriptLog

    'Hide the Network Location wizard. All networks will be Public.' | Write-ScriptLog
    New-RegistryKey -ParentPath 'HKLM:\SYSTEM\CurrentControlSet\Control\Network' -KeyName 'NewNetworkWindowOff'
    'Hide the Network Location wizard completed.' | Write-ScriptLog

    # Tweaks for Server Manager

    'Disable ServerManager scheduled task.' | Write-ScriptLog
    Disable-ScheduledTask -TaskName 'ServerManager' -TaskPath '\Microsoft\Windows\Server Manager'
    'Disable ServerManager scheduled task completed.' | Write-ScriptLog

    'Stop Server Manager launch at logon.' | Write-ScriptLog
    Set-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\ServerManager' -Name 'DoNotOpenServerManagerAtLogon' -Value 1
    'Stop Server Manager launch at logon completed.' | Write-ScriptLog

    'Stop Windows Admin Center popup at Server Manager launch.' | Write-ScriptLog
    Set-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\ServerManager' -Name 'DoNotPopWACConsoleAtSMLaunch' -Value 1
    'Stop Windows Admin Center popup at Server Manager launch completed.' | Write-ScriptLog

    # Tweaks for Microsoft Edge

    'Hide the first run experience of Microsoft Edge.' | Write-ScriptLog
    New-RegistryKey -ParentPath 'HKLM:\SOFTWARE\Policies\Microsoft' -KeyName 'Edge'
    Set-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' -Name 'HideFirstRunExperience' -Value 1
    'Hide the first run experience of Microsoft Edge completed.' | Write-ScriptLog

    # Install tools

    $toolsToInstall = $labConfig.labHost.toolsToInstall -split ';'
    if ($toolsToInstall -contains 'vscode') {
        'Install Visual Studio Code.' | Write-ScriptLog
        Invoke-VSCodeInstallation -DownloadFolderPath $labConfig.labHost.folderPath.temp
        'Install Visual Studio Code completed.' | Write-ScriptLog
    }

    # Shortcuts on the desktop

    $firstHciNodeName = Format-HciNodeName -Format $labConfig.hciNode.vmName -Offset $labConfig.hciNode.vmNameOffset -Index 0
    $shortcutParams = @(
        # @{
        #     ShortcutFilePath = 'C:\Users\Public\Desktop\Windows Admin Center.lnk'
        #     TargetPath       = 'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe'
        #     Arguments        = 'https://{0}' -f $labConfig.wac.vmName  # The VM name is also the computer name.
        #     Description      = 'Open Windows Admin Center for your lab environment.'
        #     IconLocation     = 'imageres.dll,-1028'
        # },
        @{
            ShortcutFilePath = 'C:\Users\Public\Desktop\{0}.lnk' -f $labConfig.wac.vmName
            TargetPath       = '%windir%\System32\mstsc.exe'
            Arguments        = '/v:{0}' -f $labConfig.wac.vmName  # The VM name is also the computer name.
            Description      = 'Make a remote desktop connection to the Windows Admin Center VM in your lab environment.'
        },
        @{
            ShortcutFilePath = 'C:\Users\Public\Desktop\{0}.lnk' -f $firstHciNodeName
            TargetPath       = '%windir%\System32\mstsc.exe'
            Arguments        = '/v:{0}' -f $firstHciNodeName  # The VM name is also the computer name.
            Description      = 'Make a remote desktop connection to the member node "{0}" VM of the HCI cluster in your lab environment.' -f $firstHciNodeName
        },
        @{
            ShortcutFilePath = 'C:\Users\Public\Desktop\Hyper-V Manager.lnk'
            TargetPath       = '%windir%\System32\mmc.exe'
            Arguments        = '"%windir%\System32\virtmgmt.msc"'
            Description      = 'Hyper-V Manager provides management access to virtual machines in your lab environment.'
            IconLocation     = '%ProgramFiles%\Hyper-V\SnapInAbout.dll,0'
        }
    )
    foreach ($params in $shortcutParams) {
        'Create a new shortcut on the desktop: "{0}".' -f $params.ShortcutFilePath | Write-ScriptLog
        New-ShortcutFile @params
        'Create a new shortcut on the desktop: "{0}" completed.' -f $params.ShortcutFilePath | Write-ScriptLog
    }

    'The lab host configuration has been successfully completed.' | Write-ScriptLog
}
catch {
    $exceptionMessage = New-ExceptionMessage -ErrorRecord $_
    $exceptionMessage | Write-ScriptLog -Level Error
    throw $exceptionMessage
}
finally {
    'The lab host configuration has been finished.' | Write-ScriptLog
    Stop-ScriptLogging
}
