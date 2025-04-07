[CmdletBinding()]
param (
    [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
    [string[]] $PSModuleNameToImport,

    [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
    [string] $LogFileName
)

$ErrorActionPreference = [Management.Automation.ActionPreference]::Stop
$WarningPreference = [Management.Automation.ActionPreference]::Continue
$VerbosePreference = [Management.Automation.ActionPreference]::Continue
$ProgressPreference = [Management.Automation.ActionPreference]::SilentlyContinue

function Invoke-WindowsAdminCenterInstallerDownload
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateScript({ Test-Path -PathType Container -LiteralPath $_ })]
        [string] $DownloadFolderPath
    )

    $params = @{
        SourceUri      = 'https://aka.ms/WACDownload'
        DownloadFolder = $DownloadFolderPath
        FileNameToSave = 'WindowsAdminCenter.msi'
    }
    $wacInstallerFile = Invoke-FileDownload @params
    return $wacInstallerFile
}

function New-CertificateForWindowsAdminCenter
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string] $VMName
    )

    $params = @{
        CertStoreLocation = 'Cert:\LocalMachine\My'
        Subject           = 'CN=Windows Admin Center for HCI lab'
        FriendlyName      = 'Windows Admin Center for HCI lab'
        Type              = 'SSLServerAuthentication'
        HashAlgorithm     = 'sha512'
        KeyExportPolicy   = 'ExportableEncrypted'
        NotBefore         = (Get-Date)::Now
        NotAfter          = (Get-Date).AddDays(180)  # The same days with Windows Server evaluation period.
        KeyUsage          = 'DigitalSignature', 'KeyEncipherment', 'DataEncipherment'
        TextExtension     = @(
            '2.5.29.37={text}1.3.6.1.5.5.7.3.1',  # Server Authentication
            ('2.5.29.17={{text}}DNS={0}' -f $VMName)
        )
    }
    $wacCret = New-SelfSignedCertificate @params | Move-Item -Destination 'Cert:\LocalMachine\Root' -PassThru
    return $wacCret
}

try {
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    Import-Module -Name $PSModuleNameToImport -Force
    
    $labConfig = Get-LabDeploymentConfig
    Start-ScriptLogging -OutputDirectory $labConfig.labHost.folderPath.log -FileName $LogFileName
    Set-ScriptLogDefaultContext -LogContext $labConfig.wac.vmName
    
    'Lab deployment config:' | Write-ScriptLog
    $labConfig | ConvertTo-Json -Depth 16 | Out-String | Write-ScriptLog
    
    #
    # Hyper-V VM creation
    #

    'Create the OS disk for the VM.' | Write-ScriptLog
    $params = @{
        OperatingSystem = [HciLab.OSSku]::WindowsServer2025
        ImageIndex      = [HciLab.OSImageIndex]::WSDatacenterDesktopExperience  # Datacenter with Desktop Experience
        Culture         = $labConfig.guestOS.culture
    }
    $parentVhdFileName = Format-BaseVhdFileName @params
    $params = @{
        Path                    = [IO.Path]::Combine($labConfig.labHost.folderPath.vm, $labConfig.wac.vmName, 'osdisk.vhdx')
        Differencing            = $true
        ParentPath              = [IO.Path]::Combine($labConfig.labHost.folderPath.vhd, $parentVhdFileName)
        BlockSizeBytes          = 32MB
        PhysicalSectorSizeBytes = 4KB
    }
    $vmOSDiskVhd = New-VHD  @params
    'Create the OS disk for the VM completed.' | Write-ScriptLog

    'Create the VM.' | Write-ScriptLog
    $params = @{
        Name       = $labConfig.wac.vmName
        Path       = $labConfig.labHost.folderPath.vm
        VHDPath    = $vmOSDiskVhd.Path
        Generation = 2
    }
    New-VM @params | Out-String | Write-ScriptLog
    'Create the VM completed.' | Write-ScriptLog

    'Change the VM''s automatic stop action.' | Write-ScriptLog
    Set-VM -Name $labConfig.wac.vmName -AutomaticStopAction ShutDown
    'Change the VM''s automatic stop action completed' | Write-ScriptLog

    'Configure the VM''s processor.' | Write-ScriptLog
    $vmProcessorCount = 6
    if ((Get-VMHost).LogicalProcessorCount -lt $vmProcessorCount) { $vmProcessorCount = (Get-VMHost).LogicalProcessorCount }
    Set-VMProcessor -VMName $labConfig.wac.vmName -Count $vmProcessorCount
    'Configure the VM''s processor completed.' | Write-ScriptLog

    'Configure the VM''s memory.' | Write-ScriptLog
    $params = @{
        VMName               = $labConfig.wac.vmName
        StartupBytes         = 1GB
        DynamicMemoryEnabled = $true
        MinimumBytes         = 512MB
        MaximumBytes         = $labConfig.wac.maximumRamBytes
    }
    Set-VMMemory @params
    'Configure the VM''s memory completed.' | Write-ScriptLog

    'Enable the VM''s vTPM.' | Write-ScriptLog
    $params = @{
        VMName               = $labConfig.wac.vmName
        NewLocalKeyProtector = $true
        Passthru             = $true
        ErrorAction          = [Management.Automation.ActionPreference]::Stop
    }
    try {
        Set-VMKeyProtector @params | Enable-VMTPM
    }
    catch {
        '{0} (ExceptionMessage: {1} | Exception: {2} | FullyQualifiedErrorId: {3} | CategoryInfo: {4} | ErrorDetailsMessage: {5})' -f @(
            'Caught exception on enable vTPM, will retry to enable vTPM.',
            $_.Exception.Message,
            $_.Exception.GetType().FullName,
            $_.FullyQualifiedErrorId,
            $_.CategoryInfo.ToString(),
            $_.ErrorDetails.Message
        ) | Write-ScriptLog -Level Warning

        # Rescue only once by retry.
        Set-VMKeyProtector @params | Enable-VMTPM
    }
    'Enable the VM''s vTPM completed.' | Write-ScriptLog

    'Configure the VM''s network adapters.' | Write-ScriptLog
    Get-VMNetworkAdapter -VMName $labConfig.wac.vmName | Remove-VMNetworkAdapter

    # Management
    'Configure the {0} network adapter.' -f $labConfig.wac.netAdapters.management.name | Write-ScriptLog
    $paramsForAdd = @{
        VMName       = $labConfig.wac.vmName
        Name         = $labConfig.wac.netAdapters.management.name
        SwitchName   = $labConfig.labHost.vSwitch.nat.name
        DeviceNaming = [Microsoft.HyperV.PowerShell.OnOffState]::On
        Passthru     = $true
    }
    $paramsForSet = @{
        MacAddressSpoofing = [Microsoft.HyperV.PowerShell.OnOffState]::On
        AllowTeaming       = [Microsoft.HyperV.PowerShell.OnOffState]::On
        Passthru           = $true
    }
    Add-VMNetworkAdapter @paramsForAdd |
    Set-VMNetworkAdapter @paramsForSet |
    Set-VMNetworkAdapterVlan -Trunk -NativeVlanId 0 -AllowedVlanIdList '1-4094'
    'Configure the {0} network adapter completed.' -f $labConfig.wac.netAdapters.management.name | Write-ScriptLog

    'Generate the unattend answer XML.' | Write-ScriptLog
    $adminPassword = Get-Secret -KeyVaultName $labConfig.keyVault.name -SecretName $labConfig.keyVault.secretName.adminPassword
    $params = @{
        ComputerName = $labConfig.wac.vmName
        Password     = $adminPassword
        Culture      = $labConfig.guestOS.culture
        TimeZone     = $labConfig.guestOS.timeZone
    }
    $unattendAnswerFileContent = New-UnattendAnswerFileContent @params
    'Generate the unattend answer XML completed.' | Write-ScriptLog

    'Inject the unattend answer file to the "{0}".' -f $vmOSDiskVhd.Path | Write-ScriptLog
    $params = @{
        VhdPath                   = $vmOSDiskVhd.Path
        UnattendAnswerFileContent = $unattendAnswerFileContent
        LogFolder                 = $labConfig.labHost.folderPath.log
    }
    Set-UnattendAnswerFileToVhd @params
    'Inject the unattend answer file to the "{0}" completed.' -f $vmOSDiskVhd.Path | Write-ScriptLog

    'Install the roles and features to the "{0}".' -f $vmOSDiskVhd.Path | Write-ScriptLog
    $params = @{
        VhdPath     = $vmOSDiskVhd.Path
        FeatureName = @(
            'RSAT-ADDS-Tools',
            'RSAT-AD-AdminCenter',
            'RSAT-AD-PowerShell',
            'GPMC',
            'RSAT-DNS-Server',
            'RSAT-Clustering-Mgmt',
            'RSAT-Clustering-PowerShell',
            'Hyper-V-Tools',
            'Hyper-V-PowerShell',
            'RSAT-DataCenterBridging-LLDP-Tools'
        )
        LogFolder   = $labConfig.labHost.folderPath.log
    }
    Install-WindowsFeatureToVhd @params
    'Install the roles and features to the "{0}" completed.' -f $vmOSDiskVhd.Path | Write-ScriptLog

    Start-VMSurely -VMName $labConfig.wac.vmName

    'Wait for the VM to be ready.' | Write-ScriptLog
    $localAdminCredential = New-LogonCredential -DomainFqdn '.' -Password $adminPassword
    Wait-PowerShellDirectReady -VMName $labConfig.wac.vmName -Credential $localAdminCredential
    'The VM is ready.' | Write-ScriptLog

    #
    # Guest OS configuration
    #

    'Copy the module files into the VM.' | Write-ScriptLog
    $params = @{
        VMName              = $labConfig.wac.vmName
        Credential          = $localAdminCredential
        SourceFilePath      = (Get-Module -Name 'common').Path
        DestinationPathInVM = 'C:\Windows\Temp'
    }
    $moduleFilePathsWithinVM = Copy-FileIntoVM @params
    'Copy the module files into the VM completed.' | Write-ScriptLog

    # The common parameters for Invoke-CommandWithinVM.
    $invokeWithinVMParams = @{
        VMName           = $labConfig.wac.vmName
        Credential       = $localAdminCredential
        ImportModuleInVM = $moduleFilePathsWithinVM
    }
    
    'Configure registry values within the VM.' | Write-ScriptLog
    Invoke-CommandWithinVM @invokeWithinVMParams -ScriptBlock {
        'Disable diagnostics data send screen.' | Write-ScriptLog
        New-RegistryKey -ParentPath 'HKLM:\SOFTWARE\Policies\Microsoft\Windows' -KeyName 'OOBE'
        Set-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\OOBE' -Name 'DisablePrivacyExperience' -Value 1
        'Disable diagnostics data send screen completed.' | Write-ScriptLog

        'Stop Server Manager launch at logon.' | Write-ScriptLog
        Set-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\ServerManager' -Name 'DoNotOpenServerManagerAtLogon' -Value 1
        'Stop Server Manager launch at logon completed.' | Write-ScriptLog

        'Stop Windows Admin Center popup at Server Manager launch.' | Write-ScriptLog
        Set-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\ServerManager' -Name 'DoNotPopWACConsoleAtSMLaunch' -Value 1
        'Stop Windows Admin Center popup at Server Manager launch completed.' | Write-ScriptLog

        'Hide the Network Location wizard. All networks will be Public.' | Write-ScriptLog
        New-RegistryKey -ParentPath 'HKLM:\SYSTEM\CurrentControlSet\Control\Network' -KeyName 'NewNetworkWindowOff'
        'Hide the Network Location wizard completed.' | Write-ScriptLog

        'Hide the first run experience of Microsoft Edge.' | Write-ScriptLog
        New-RegistryKey -ParentPath 'HKLM:\SOFTWARE\Policies\Microsoft' -KeyName 'Edge'
        Set-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' -Name 'HideFirstRunExperience' -Value 1
        'Hide the first run experience of Microsoft Edge completed.' | Write-ScriptLog
    } | Out-String | Write-ScriptLog
    'Configure registry values within the VM completed.' | Write-ScriptLog

    'Configure network settings within the VM.' | Write-ScriptLog
    Invoke-CommandWithinVM @invokeWithinVMParams -ScriptBlockParamList $labConfig.wac -ScriptBlock {
        param (
            [Parameter(Mandatory = $true)]
            [PSCustomObject] $VMConfig
        )

        'Rename the network adapters.' | Write-ScriptLog
        Get-NetAdapterAdvancedProperty -RegistryKeyword 'HyperVNetworkAdapterName' | ForEach-Object -Process {
            Rename-NetAdapter -Name $_.Name -NewName $_.DisplayValue
        }
        'Rename the network adapters completed.' | Write-ScriptLog

        # Management
        'Configure the IP & DNS on the "{0}" network adapter.' -f $VMConfig.netAdapters.management.name | Write-ScriptLog
        $paramsForSetNetIPInterface = @{
            AddressFamily = 'IPv4'
            Dhcp          = 'Disabled'
            PassThru      = $true
        }
        $paramsForNewIPAddress = @{
            AddressFamily  = 'IPv4'
            IPAddress      = $VMConfig.netAdapters.management.ipAddress
            PrefixLength   = $VMConfig.netAdapters.management.prefixLength
            DefaultGateway = $VMConfig.netAdapters.management.defaultGateway
        }
        $paramsForSetDnsClientServerAddress = @{
            ServerAddresses = $VMConfig.netAdapters.management.dnsServerAddresses
        }
        Get-NetAdapter -Name $VMConfig.netAdapters.management.name |
        Set-NetIPInterface @paramsForSetNetIPInterface |
        New-NetIPAddress @paramsForNewIPAddress |
        Set-DnsClientServerAddress @paramsForSetDnsClientServerAddress |
        Out-Null
        'Configure the IP & DNS on the "{0}" network adapter completed.' -f $VMConfig.NetAdapters.Management.Name | Write-ScriptLog

        'Network adapter IP configurations:' | Write-ScriptLog
        Get-NetIPAddress | Format-Table -Property @(
            'InterfaceIndex',
            'InterfaceAlias',
            'AddressFamily',
            'IPAddress',
            'PrefixLength',
            'PrefixOrigin',
            'SuffixOrigin',
            'AddressState',
            'Store'
        ) | Out-String -Width 200 | Write-ScriptLog

        'Network adapter DNS configurations:' | Write-ScriptLog
        Get-DnsClientServerAddress | Format-Table -Property @(
            'InterfaceIndex',
            'InterfaceAlias',
            @{ Label = 'AddressFamily'; Expression = { Switch ($_.AddressFamily) { 2 { 'IPv4' } 23 { 'IPv6' } default { $_.AddressFamily } } } }
            @{ Label = 'DNSServers'; Expression = { $_.ServerAddresses } }
        ) | Out-String -Width 200 | Write-ScriptLog
    } | Out-String | Write-ScriptLog
    'Configure network settings within the VM completed.' | Write-ScriptLog

    # Temporary comment out the WAC related code because of the WAC installation issue.
    <#
    'Donwload the Windows Admin Center installer.' | Write-ScriptLog
    $wacInstallerFile = Invoke-WindowsAdminCenterInstallerDownload -DownloadFolderPath $labConfig.labHost.folderPath.temp
    $wacInstallerFile | Out-String | Write-ScriptLog
    'Donwload the Windows Admin Center installer completed.' | Write-ScriptLog

    'Create a new SSL server authentication certificate for Windows Admin Center.' | Write-ScriptLog
    $wacCret = New-CertificateForWindowsAdminCenter -VMName $labConfig.wac.vmName
    'Create a new SSL server authentication certificate for Windows Admin Center completed.' | Write-ScriptLog

    'Export the Windows Admin Center certificate.' | Write-ScriptLog
    $wacPfxFilePathOnLabHost = [IO.Path]::Combine($labConfig.labHost.folderPath.temp, 'wac.pfx')
    $wacCret | Export-PfxCertificate -FilePath $wacPfxFilePathOnLabHost -Password $adminPassword | Out-String | Write-ScriptLog
    'Export the Windows Admin Center certificate completed.' | Write-ScriptLog

    'Copy the Windows Admin Center installer into the VM.' | Write-ScriptLog
    $wacInstallerFilePathInVM = [IO.Path]::Combine('C:\Windows\Temp', [IO.Path]::GetFileName($wacInstallerFile.FullName))
    Copy-Item -ToSession $localAdminCredPSSession -Path $wacInstallerFile.FullName -Destination $wacInstallerFilePathInVM
    'Copy the Windows Admin Center installer into the VM completed.' | Write-ScriptLog

    'Copy the Windows Admin Center certificate into the VM.' | Write-ScriptLog
    $wacPfxFilePathInVM = [IO.Path]::Combine('C:\Windows\Temp', [IO.Path]::GetFileName($wacPfxFilePathOnLabHost))
    Copy-Item -ToSession $localAdminCredPSSession -Path $wacPfxFilePathOnLabHost -Destination $wacPfxFilePathInVM
    'Copy the Windows Admin Center certificate into the VM completed.' | Write-ScriptLog

    'Install Windows Admin Center within the VM.' | Write-ScriptLog
    $params = @{
        InputObject = [PSCustomObject] @{
            WacInstallerFilePathInVM = $wacInstallerFilePathInVM
            WacPfxFilePathInVM       = $wacPfxFilePathInVM
            WacPfxPassword           = $adminPassword
        }
    }
    Invoke-Command @params -Session $localAdminCredPSSession -ScriptBlock {
        param (
            [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
            [string] $WacInstallerFilePathInVM,

            [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
            [string] $WacPfxFilePathInVM,

            [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
            [SecureString] $WacPfxPassword
        )

        # NOTE: Import the certificate to Root and My both stores required.
        'Import the Windows Admin Center certificate to the Root store.' | Write-ScriptLog
        $wacCertRootStore = Import-PfxCertificate -CertStoreLocation 'Cert:\LocalMachine\Root' -FilePath $WacPfxFilePathInVM -Password $WacPfxPassword -Exportable
        $wacCertRootStore | Format-Table -Property 'Thumbprint', 'Subject' | Out-String | Write-ScriptLog
        'Import the Windows Admin Center certificate to the Root store completed.' | Write-ScriptLog

        'Import the Windows Admin Center certificate to the My store.' | Write-ScriptLog
        $wacCertMyStore = Import-PfxCertificate -CertStoreLocation 'Cert:\LocalMachine\My' -FilePath $WacPfxFilePathInVM -Password $WacPfxPassword -Exportable
        $wacCertMyStore | Format-Table -Property 'Thumbprint', 'Subject' | Out-String | Write-ScriptLog
        'Import the Windows Admin Center certificate to the My store completed.' | Write-ScriptLog

        'Delete the Windows Admin Center certificate.' | Write-ScriptLog
        Remove-Item -LiteralPath $WacPfxFilePathInVM -Force
        'Delete the Windows Admin Center certificate completed.' | Write-ScriptLog

        'Install Windows Admin Center.' | Write-ScriptLog
        $msiArgs = @(
            '/i',
            ('"{0}"' -f $WacInstallerFilePathInVM),
            '/qn',
            '/L*v',
            '"C:\Windows\Temp\wac-install-log.log"',
            'SME_PORT=443',
            ('SME_THUMBPRINT={0}' -f $wacCertMyStore.Thumbprint),
            'SSL_CERTIFICATE_OPTION=installed'
            #'SSL_CERTIFICATE_OPTION=generate'
        )
        $result = Start-Process -FilePath 'msiexec.exe' -ArgumentList $msiArgs -Wait -PassThru
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
        if ($result.ExitCode -ne 0) {
            throw 'Windows Admin Center installation failed with exit code {0}.' -f $result.ExitCode
        }
        'Install Windows Admin Center completed.' | Write-ScriptLog

        'Delete the Windows Admin Center installer.' | Write-ScriptLog
        Remove-Item -LiteralPath $WacInstallerFilePathInVM -Force
        'Delete the Windows Admin Center installer completed.' | Write-ScriptLog

        'Wait for the ServerManagementGateway service to be ready.' | Write-ScriptLog
        &{
            $wacConnectionTestTimeout = (New-TimeSpan -Minutes 5)
            $wacConnectionTestIntervalSeconds = 5
            $startTime = Get-Date
            while ((Get-Date) -lt ($startTime + $wacConnectionTestTimeout)) {
                'Test connection to the ServerManagementGateway service.' | Write-ScriptLog
                if ((Test-NetConnection -ComputerName 'localhost' -Port 443).TcpTestSucceeded) {
                    'Connection test to the ServerManagementGateway service succeeded.' | Write-ScriptLog
                    return
                }
                Start-Sleep -Seconds $wacConnectionTestIntervalSeconds
            }
            'Connection test to the ServerManagementGateway service failed.' | Write-ScriptLog -Level Warning
        }
        'The ServerManagementGateway service is ready.' | Write-ScriptLog

        'Import the ExtensionTools module.' | Write-ScriptLog
        $wacExtensionToolsPSModulePath = [IO.Path]::Combine($env:ProgramFiles, 'Windows Admin Center\PowerShell\Modules\ExtensionTools\ExtensionTools.psm1')
        Import-Module -Name $wacExtensionToolsPSModulePath -Force
        'Import the ExtensionTools module completed.' | Write-ScriptLog

        'Update the Windows Admin Center extensions.' | Write-ScriptLog
        &{
            $retryLimit = 50
            $retryInterval = 15
            for ($retryCount = 0; $retryCount -lt $retryLimit; $retryCount++) {
                try {
                    [Uri] $gatewayEndpointUri = 'https://{0}' -f $env:ComputerName

                    # NOTE: Windows Admin Center extension updating will fail sometimes due to unable to connect remote server.
                    Get-Extension -GatewayEndpoint $gatewayEndpointUri -ErrorAction Stop |
                        Where-Object -Property 'isLatestVersion' -EQ $false |
                        ForEach-Object -Process {
                            $wacExtension = $_
                            Update-Extension -GatewayEndpoint $gatewayEndpointUri -ExtensionId $wacExtension.id -Verbose -ErrorAction Stop | Out-Null
                        }
                    'Windows Admin Center extension update succeeded.' | Write-ScriptLog

                    'Windows Admin Center extension status:' | Write-ScriptLog
                    Get-Extension -GatewayEndpoint $gatewayEndpointUri |
                        Sort-Object -Property id |
                        Format-table -Property id, status, version, isLatestVersion, title |
                        Out-String | Write-ScriptLog
                    return
                }
                catch {
                    'Retry updating the Windows Admin Center extensions.' | Write-ScriptLog -Level Warning
                    Start-Sleep -Seconds $retryInterval
                }
            }
            'Windows Admin Center extension update failed. Need manual update later.' | Write-ScriptLog -Level Warning
        }
        'Update the Windows Admin Center extensions completed.' | Write-ScriptLog

        'Set the Windows Integrated Authentication registry for Windows Admin Center.' | Write-ScriptLog
        New-RegistryKey -ParentPath 'HKLM:\SOFTWARE\Policies\Microsoft' -KeyName 'Edge'
        Set-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' -Name 'AuthServerAllowlist' -Value $env:ComputerName
        'Set the Windows Integrated Authentication registry for Windows Admin Center completed.' | Write-ScriptLog

        'Create the shortcut for Windows Admin Center on the desktop.' | Write-ScriptLog
        $params = @{
            ShortcutFilePath = 'C:\Users\Public\Desktop\Windows Admin Center.lnk'
            TargetPath       = 'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe'
            Arguments        = 'https://{0}' -f $env:ComputerName
            Description      = 'Windows Admin Center for the lab environment.'
            IconLocation     = 'imageres.dll,-1028'
        }
        New-ShortcutFile @params
        'Create the shortcut for Windows Admin Center on the desktop completed.' | Write-ScriptLog
    } | Out-String | Write-ScriptLog
    'Install Windows Admin Center within the VM completed.' | Write-ScriptLog
    #>

    'Create a new shortcut on the desktop for connecting to the first HCI node using Remote Desktop connection.' | Write-ScriptLog
    Invoke-CommandWithinVM @invokeWithinVMParams -ScriptBlockParamList $labConfig.hciNode -ScriptBlock {
        param (
            [Parameter(Mandatory = $true)]
            [PSCustomObject] $HciNodeConfig
        )

        $firstHciNodeName = Format-HciNodeName -Format $HciNodeConfig.vmName -Offset $HciNodeConfig.vmNameOffset -Index 0
        $params = @{
            ShortcutFilePath = 'C:\Users\Public\Desktop\{0}.lnk' -f $firstHciNodeName
            TargetPath       = '%windir%\System32\mstsc.exe'
            Arguments        = '/v:{0}' -f $firstHciNodeName  # The VM name is also the computer name.
            Description      = 'Make a remote desktop connection to the member node "{0}" VM of the HCI cluster in your lab environment.' -f $firstHciNodeName
        }
        New-ShortcutFile @params
    } | Out-String | Write-ScriptLog
    'Create a new shortcut on the desktop for connecting to the first HCI node using Remote Desktop connection completed.' | Write-ScriptLog

    # We need to wait for the domain controller VM deployment completion before update the NuGet package provider and the PowerShellGet module.
    'Wait for the domain controller VM deployment completion.' | Write-ScriptLog
    Wait-AddsDcDeploymentCompletion
    'The domain controller VM deployment completed.' | Write-ScriptLog

    'Wait for the domain controller with DNS capability to be ready.' | Write-ScriptLog
    $domainAdminCredential = New-LogonCredential -DomainFqdn $labConfig.addsDomain.fqdn -Password $adminPassword
    $params = @{
        AddsDcVMName       = $labConfig.addsDC.vmName
        AddsDcComputerName = $labConfig.addsDC.vmName  # The DC's computer name is the same as the VM name. It's specified in the unattend.xml.
        Credential         = $domainAdminCredential    # Domain Administrator credential
    }
    Wait-DomainControllerServiceReady @params
    'The domain controller with DNS capability is ready.' | Write-ScriptLog

    # NOTE: The package provider installation needs internet connection and name resolution.
    'Install the NuGet package provider within the VM.' | Write-ScriptLog
    Invoke-CommandWithinVM @invokeWithinVMParams -WithRetry -ScriptBlock {
        Install-PackageProvider -Name 'NuGet' -Scope 'AllUsers' -Force -Verbose | Out-String -Width 200 | Write-ScriptLog
    } | Out-String -Width 200 | Write-ScriptLog
    'Install the NuGet package provider within the VM completed.' | Write-ScriptLog

    # NOTE: The PowerShellGet module installation needs internet connection and name resolution.
    'Install the PowerShellGet module within the VM.' | Write-ScriptLog
    Invoke-CommandWithinVM @invokeWithinVMParams -WithRetry -ScriptBlock {
        Install-Module -Name 'PowerShellGet' -Scope 'AllUsers' -Force -Verbose | Out-String -Width 200 | Write-ScriptLog
    } | Out-String -Width 200 | Write-ScriptLog
    'Install the PowerShellGet module within the VM completed.' | Write-ScriptLog

    'Join the VM to the AD domain.' | Write-ScriptLog
    $params = @{
        VMName                = $labConfig.wac.vmName
        LocalAdminCredential  = $localAdminCredential
        DomainFqdn            = $labConfig.addsDomain.fqdn
        DomainAdminCredential = $domainAdminCredential
    }
    Add-VMToADDomain @params
    'Join the VM to the AD domain completed.' | Write-ScriptLog

    # Reboot the VM.
    Stop-VMSurely -VMName $labConfig.wac.vmName
    Start-VMSurely -VMName $labConfig.wac.vmName

    'Wait for the VM to be ready.' | Write-ScriptLog
    Wait-PowerShellDirectReady -VMName $labConfig.wac.vmName -Credential $domainAdminCredential
    'The VM is ready.' | Write-ScriptLog

    # Temporary comment out the WAC related code because of the WAC installation issue.
    <#
    # NOTE: To preset WAC connections for the domain Administrator, the preset operation is required by
    # the domain Administrator because WAC connections are managed based on each user.
    'Configure Windows Admin Center for the domain Administrator.' | Write-ScriptLog
    $params = @{
        InputObject = [PSCustomObject] @{
            LabConfig = $LabConfig
        }
    }
    Invoke-Command @params -Session $domainAdminCredPSSession -ScriptBlock {
        param (
            [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
            [PSCustomObject] $LabConfig
        )

        'Import the ConnectionTools module.' | Write-ScriptLog
        $wacConnectionToolsPSModulePath = [IO.Path]::Combine($env:ProgramFiles, 'Windows Admin Center\PowerShell\Modules\ConnectionTools\ConnectionTools.psm1')
        Import-Module -Name $wacConnectionToolsPSModulePath -Force
        'Import the ConnectionTools module completed.' | Write-ScriptLog

        # Create a connection entry list to import to Windows Admin Center.
        $connectionEntries = @(
            (New-WacConnectionFileEntry -Name ('{0}.{1}' -f $LabConfig.addsDC.vmName, $LabConfig.addsDomain.fqdn) -Type 'msft.sme.connection-type.server'),  # Entry for the AD DS DC.
            (New-WacConnectionFileEntry -Name ('{0}.{1}' -f $LabConfig.wac.vmName, $LabConfig.addsDomain.fqdn) -Type 'msft.sme.connection-type.server')  # Entry for the management server (WAC).
        )

        # Entry for the HCI nodes.
        if ($LabConfig.hciNode.shouldJoinToAddsDomain) {
            $tagParam = @{}
            if ($LabConfig.hciCluster.shouldCreateCluster) {
                # Add the cluster's FQDN to tag if the cluster will be created.
                $tagParam.Tag = '{0}.{1}' -f $LabConfig.hciCluster.name, $LabConfig.addsDomain.fqdn
            }

            for ($nodeIndex = 0; $nodeIndex -lt $LabConfig.hciNode.nodeCount; $nodeIndex++) {
                $nodeName = Format-HciNodeName -Format $LabConfig.hciNode.vmName -Offset $LabConfig.hciNode.vmNameOffset -Index $nodeIndex
                $nodeFqdn = '{0}.{1}' -f $nodeName, $LabConfig.addsDomain.fqdn
                $connectionEntries += New-WacConnectionFileEntry -Name $nodeFqdn -Type 'msft.sme.connection-type.server' @tagParam
            }
        }
        else {
            for ($nodeIndex = 0; $nodeIndex -lt $LabConfig.hciNode.nodeCount; $nodeIndex++) {
                $nodeName = Format-HciNodeName -Format $LabConfig.hciNode.vmName -Offset $LabConfig.hciNode.vmNameOffset -Index $nodeIndex
                $connectionEntries += New-WacConnectionFileEntry -Name $nodeName -Type 'msft.sme.connection-type.server'
            }
        }

        'Create a connection list file to import to Windows Admin Center.' | Write-ScriptLog
        $wacConnectionFilePathInVM = [IO.Path]::Combine('C:\Windows\Temp', 'wac-connections.txt')
        New-WacConnectionFileContent -ConnectionEntry $connectionEntries | Set-Content -LiteralPath $wacConnectionFilePathInVM -Force
        'Create a connection list file to import to Windows Admin Center completed.' | Write-ScriptLog

        'Import server connections to Windows Admin Center for the domain Administrator.' | Write-ScriptLog
        [Uri] $gatewayEndpointUri = 'https://{0}' -f $env:ComputerName
        Import-Connection -GatewayEndpoint $gatewayEndpointUri -FileName $wacConnectionFilePathInVM
        'Import server connections to Windows Admin Center for the domain Administrator completed.' | Write-ScriptLog

        'Delete the Windows Admin Center connection list file.' | Write-ScriptLog
        Remove-Item -LiteralPath $wacConnectionFilePathInVM -Force
        'Delete the Windows Admin Center connection list file completed.' | Write-ScriptLog
    } | Out-String | Write-ScriptLog
    'Configure Windows Admin Center for the domain Administrator completed.' | Write-ScriptLog
    #>

    'Delete the module files within the VM.' | Write-ScriptLog
    $params = @{
        VMName               = $invokeWithinVMParams.VMName
        Credential           = $invokeWithinVMParams.Credential
        FilePathToRemoveInVM = $invokeWithinVMParams.ImportModuleInVM
        ImportModuleInVM     = $invokeWithinVMParams.ImportModuleInVM
    }
    Remove-FileWithinVM @params
    'Delete the module files within the VM completed.' | Write-ScriptLog

    'The WAC VM creation has been successfully completed.' | Write-ScriptLog
}
catch {
    $exceptionMessage = New-ExceptionMessage -ErrorRecord $_
    $exceptionMessage | Write-ScriptLog -Level Error
    throw $exceptionMessage
}
finally {
    'The WAC VM creation has been finished.' | Write-ScriptLog
    $stopWatch.Stop()
    'Duration of this script ran: {0}' -f $stopWatch.Elapsed.toString('hh\:mm\:ss') | Write-ScriptLog
    Stop-ScriptLogging
}
