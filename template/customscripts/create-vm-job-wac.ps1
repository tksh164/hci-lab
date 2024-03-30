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

Import-Module -Name $PSModuleNameToImport -Force

$labConfig = Get-LabDeploymentConfig
Start-ScriptLogging -OutputDirectory $labConfig.labHost.folderPath.log -FileName $LogFileName
'Lab deployment config:' | Write-ScriptLog
$labConfig | ConvertTo-Json -Depth 16 | Out-String | Write-ScriptLog

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

$vmName = $labConfig.wac.vmName

# Hyper-V VM

'Create the OS disk for the VM.' | Write-ScriptLog -AdditionalContext $vmName
$params = @{
    OperatingSystem = [HciLab.OSSku]::WindowsServer2022
    ImageIndex      = [HciLab.OSImageIndex]::WSDatacenterDesktopExperience  # Datacenter with Desktop Experience
    Culture         = $labConfig.guestOS.culture
}
$parentVhdFileName = Format-BaseVhdFileName @params
$params = @{
    Differencing = $true
    ParentPath   = [IO.Path]::Combine($labConfig.labHost.folderPath.vhd, $parentVhdFileName)
    Path         = [IO.Path]::Combine($labConfig.labHost.folderPath.vm, $vmName, 'osdisk.vhdx')
}
$vmOSDiskVhd = New-VHD  @params
'Create the OS disk for the VM completed.' | Write-ScriptLog -AdditionalContext $vmName

'Create the VM.' | Write-ScriptLog -AdditionalContext $vmName
$params = @{
    Name       = $vmName
    Path       = $labConfig.labHost.folderPath.vm
    VHDPath    = $vmOSDiskVhd.Path
    Generation = 2
}
New-VM @params | Out-String | Write-ScriptLog -AdditionalContext $vmName
'Create the VM completed.' | Write-ScriptLog -AdditionalContext $vmName

'Change the VM''s automatic stop action.' | Write-ScriptLog -AdditionalContext $vmName
Set-VM -Name $vmName -AutomaticStopAction ShutDown
'Change the VM''s automatic stop action completed' | Write-ScriptLog -AdditionalContext $vmName

'Configure the VM''s processor.' | Write-ScriptLog -AdditionalContext $vmName
$vmProcessorCount = 6
if ((Get-VMHost).LogicalProcessorCount -lt $vmProcessorCount) { $vmProcessorCount = (Get-VMHost).LogicalProcessorCount }
Set-VMProcessor -VMName $vmName -Count $vmProcessorCount
'Configure the VM''s processor completed.' | Write-ScriptLog -AdditionalContext $vmName

'Configure the VM''s memory.' | Write-ScriptLog -AdditionalContext $vmName
$params = @{
    VMName               = $vmName
    StartupBytes         = 1GB
    DynamicMemoryEnabled = $true
    MinimumBytes         = 512MB
    MaximumBytes         = $labConfig.wac.maximumRamBytes
}
Set-VMMemory @params
'Configure the VM''s memory completed.' | Write-ScriptLog -AdditionalContext $vmName

'Enable the VM''s vTPM.' | Write-ScriptLog -AdditionalContext $vmName
$params = @{
    VMName               = $vmName
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
    ) | Write-ScriptLog -Level Warning -AdditionalContext $vmName

    # Rescue only once by retry.
    Set-VMKeyProtector @params | Enable-VMTPM
}
'Enable the VM''s vTPM completed.' | Write-ScriptLog -AdditionalContext $vmName

'Configure the VM''s network adapters.' | Write-ScriptLog -AdditionalContext $vmName
Get-VMNetworkAdapter -VMName $vmName | Remove-VMNetworkAdapter

# Management
'Configure the {0} network adapter.' -f $labConfig.wac.netAdapters.management.name | Write-ScriptLog -AdditionalContext $vmName
$paramsForAdd = @{
    VMName       = $vmName
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
'Configure the {0} network adapter completed.' -f $labConfig.wac.netAdapters.management.name | Write-ScriptLog -AdditionalContext $vmName

'Generate the unattend answer XML.' | Write-ScriptLog -AdditionalContext $vmName
$adminPassword = Get-Secret -KeyVaultName $labConfig.keyVault.name -SecretName $labConfig.keyVault.secretName.adminPassword
$params = @{
    ComputerName = $vmName
    Password     = $adminPassword
    Culture      = $labConfig.guestOS.culture
    TimeZone     = $labConfig.guestOS.timeZone
}
$unattendAnswerFileContent = New-UnattendAnswerFileContent @params
'Generate the unattend answer XML completed.' | Write-ScriptLog -AdditionalContext $vmName

'Inject the unattend answer file to the VM.' | Write-ScriptLog -AdditionalContext $vmName
$params = @{
    VhdPath                   = $vmOSDiskVhd.Path
    UnattendAnswerFileContent = $unattendAnswerFileContent
    LogFolder                 = $labConfig.labHost.folderPath.log
}
Set-UnattendAnswerFileToVhd @params
'Inject the unattend answer file to the VM completed.' | Write-ScriptLog -AdditionalContext $vmName

'Install the roles and features to the VHD.' | Write-ScriptLog -AdditionalContext $vmName
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
'Install the roles and features to the VHD completed.' | Write-ScriptLog -AdditionalContext $vmName

'Start the VM.' | Write-ScriptLog -AdditionalContext $vmName
Start-VMWithRetry -VMName $vmName
'Start the VM completed.' | Write-ScriptLog -AdditionalContext $vmName

'Wait for the VM to be ready.' | Write-ScriptLog -AdditionalContext $vmName
$localAdminCredential = New-LogonCredential -DomainFqdn '.' -Password $adminPassword
Wait-PowerShellDirectReady -VMName $vmName -Credential $localAdminCredential
'The VM is ready.' | Write-ScriptLog -AdditionalContext $vmName

# Guest OS

'Create a PowerShell Direct session.' | Write-ScriptLog -AdditionalContext $vmName
$localAdminCredPSSession = New-PSSession -VMName $vmName -Credential $localAdminCredential
$localAdminCredPSSession | Format-Table -Property 'Id', 'Name', 'ComputerName', 'ComputerType', 'State', 'Availability' | Out-String | Write-ScriptLog -AdditionalContext $vmName
'Create a PowerShell Direct session completed.' | Write-ScriptLog -AdditionalContext $vmName

'Copy the common module file into the VM.' | Write-ScriptLog -AdditionalContext $vmName
$commonModuleFilePathInVM = Copy-PSModuleIntoVM -Session $localAdminCredPSSession -ModuleFilePathToCopy (Get-Module -Name 'common').Path
'Copy the common module file into the VM completed.' | Write-ScriptLog -AdditionalContext $vmName

'Setup the PowerShell Direct session.' | Write-ScriptLog -AdditionalContext $vmName
Invoke-PSDirectSessionSetup -Session $localAdminCredPSSession -CommonModuleFilePathInVM $commonModuleFilePathInVM
'Setup the PowerShell Direct session completed.' | Write-ScriptLog -AdditionalContext $vmName

'Configure registry values within the VM.' | Write-ScriptLog -AdditionalContext $vmName
Invoke-Command -Session $localAdminCredPSSession -ScriptBlock {
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
} | Out-String | Write-ScriptLog -AdditionalContext $vmName
'Configure registry values within the VM completed.' | Write-ScriptLog -AdditionalContext $vmName

'Configure network settings within the VM.' | Write-ScriptLog -AdditionalContext $vmName
$params = @{
    InputObject = [PSCustomObject] @{
        VMConfig = $LabConfig.wac
    }
}
Invoke-Command @params -Session $localAdminCredPSSession -ScriptBlock {
    param (
        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [PSCustomObject] $VMConfig
    )

    'Rename the network adapters.' | Write-ScriptLog
    Get-NetAdapterAdvancedProperty -RegistryKeyword 'HyperVNetworkAdapterName' | ForEach-Object -Process {
        Rename-NetAdapter -Name $_.Name -NewName $_.DisplayValue
    }
    'Rename the network adapters completed.' | Write-ScriptLog

    # Management
    'Configure the IP & DNS on the {0} network adapter.' -f $VMConfig.netAdapters.management.name | Write-ScriptLog
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
    'Configure the IP & DNS on the {0} network adapter completed.' -f $VMConfig.NetAdapters.Management.Name | Write-ScriptLog

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
} | Out-String | Write-ScriptLog -AdditionalContext $vmName
'Configure network settings within the VM completed.' | Write-ScriptLog -AdditionalContext $vmName

# Windows Admin Center

'Donwload the Windows Admin Center installer.' | Write-ScriptLog -AdditionalContext $vmName
$wacInstallerFile = Invoke-WindowsAdminCenterInstallerDownload -DownloadFolderPath $labConfig.labHost.folderPath.temp
$wacInstallerFile | Out-String | Write-ScriptLog -AdditionalContext $vmName
'Donwload the Windows Admin Center installer completed.' | Write-ScriptLog -AdditionalContext $vmName

'Create a new SSL server authentication certificate for Windows Admin Center.' | Write-ScriptLog -AdditionalContext $vmName
$wacCret = New-CertificateForWindowsAdminCenter -VMName $vmName
'Create a new SSL server authentication certificate for Windows Admin Center completed.' | Write-ScriptLog -AdditionalContext $vmName

'Export the Windows Admin Center certificate.' | Write-ScriptLog -AdditionalContext $vmName
$wacPfxFilePathOnLabHost = [IO.Path]::Combine($labConfig.labHost.folderPath.temp, 'wac.pfx')
$wacCret | Export-PfxCertificate -FilePath $wacPfxFilePathOnLabHost -Password $adminPassword | Out-String | Write-ScriptLog -AdditionalContext $vmName
'Export the Windows Admin Center certificate completed.' | Write-ScriptLog -AdditionalContext $vmName

'Copy the Windows Admin Center installer into the VM.' | Write-ScriptLog -AdditionalContext $vmName
$wacInstallerFilePathInVM = [IO.Path]::Combine('C:\Windows\Temp', [IO.Path]::GetFileName($wacInstallerFile.FullName))
Copy-Item -ToSession $localAdminCredPSSession -Path $wacInstallerFile.FullName -Destination $wacInstallerFilePathInVM
'Copy the Windows Admin Center installer into the VM completed.' | Write-ScriptLog -AdditionalContext $vmName

'Copy the Windows Admin Center certificate into the VM.' | Write-ScriptLog -AdditionalContext $vmName
$wacPfxFilePathInVM = [IO.Path]::Combine('C:\Windows\Temp', [IO.Path]::GetFileName($wacPfxFilePathOnLabHost))
Copy-Item -ToSession $localAdminCredPSSession -Path $wacPfxFilePathOnLabHost -Destination $wacPfxFilePathInVM
'Copy the Windows Admin Center certificate into the VM completed.' | Write-ScriptLog -AdditionalContext $vmName

'Install Windows Admin Center within the VM.' | Write-ScriptLog -AdditionalContext $vmName
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
        '"C:\Windows\Temp\wac-install-log.txt"',
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
        $exceptionMessage = 'Windows Admin Center installation failed with exit code {0}.' -f $result.ExitCode
        $exceptionMessage | Write-ScriptLog -Level Error
        throw $exceptionMessage
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
        IconLocation     = 'imageres.dll,1'
    }
    New-ShortcutFile @params
    'Create the shortcut for Windows Admin Center on the desktop completed.' | Write-ScriptLog
} | Out-String | Write-ScriptLog -AdditionalContext $vmName
'Install Windows Admin Center within the VM completed.' | Write-ScriptLog -AdditionalContext $vmName

'Create a new shortcut on the desktop for connecting to the first HCI node using Remote Desktop connection.' | Write-ScriptLog -AdditionalContext $vmName
$params = @{
    InputObject = [PSCustomObject] @{
        FirstHciNodeName = Format-HciNodeName -Format $labConfig.hciNode.vmName -Offset $labConfig.hciNode.vmNameOffset -Index 0
    }
}
Invoke-Command @params -Session $localAdminCredPSSession -ScriptBlock {
    param (
        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [string] $FirstHciNodeName
    )

    $params = @{
        ShortcutFilePath = 'C:\Users\Public\Desktop\{0}.lnk' -f $FirstHciNodeName
        TargetPath       = '%windir%\System32\mstsc.exe'
        Arguments        = '/v:{0}' -f $FirstHciNodeName  # The VM name is also the computer name.
        Description      = 'Make a remote desktop connection to the member node "{0}" VM of the HCI cluster in your lab environment.' -f $FirstHciNodeName
    }
    New-ShortcutFile @params
} | Out-String | Write-ScriptLog -AdditionalContext $vmName
'Create a new shortcut on the desktop for connecting to the first HCI node using Remote Desktop connection completed.' | Write-ScriptLog -AdditionalContext $vmName

'Clean up the PowerShell Direct session.' | Write-ScriptLog -AdditionalContext $vmName
# NOTE: The common module not be deleted within the VM at this time because it will be used afterwards.
$localAdminCredPSSession | Remove-PSSession
'Clean up the PowerShell Direct session completed.' | Write-ScriptLog -AdditionalContext $vmName

'Wait for the domain controller to complete deployment.' | Write-ScriptLog -AdditionalContext $vmName
Wait-AddsDcDeploymentCompletion
'The domain controller deployment completed.' | Write-ScriptLog -AdditionalContext $vmName

'Wait for the domain controller to be ready.' | Write-ScriptLog -AdditionalContext $vmName
$domainAdminCredential = New-LogonCredential -DomainFqdn $labConfig.addsDomain.fqdn -Password $adminPassword
$params = @{
    AddsDcVMName       = $labConfig.addsDC.vmName
    AddsDcComputerName = $labConfig.addsDC.vmName  # The DC's computer name is the same as the VM name. It's specified in the unattend.xml.
    Credential         = $domainAdminCredential
}
Wait-DomainControllerServiceReady @params
'The domain controller is ready.' | Write-ScriptLog -AdditionalContext $vmName

'Join the VM to the AD domain.' | Write-ScriptLog -AdditionalContext $vmName
$params = @{
    VMName                = $vmName
    LocalAdminCredential  = $localAdminCredential
    DomainFqdn            = $labConfig.addsDomain.fqdn
    DomainAdminCredential = $domainAdminCredential
}
Add-VMToADDomain @params
'Join the VM to the AD domain completed.' | Write-ScriptLog -AdditionalContext $vmName

'Stop the VM.' | Write-ScriptLog -AdditionalContext $vmName
Stop-VM -Name $vmName
'Stop the VM completed.' | Write-ScriptLog -AdditionalContext $vmName

'Start the VM.' | Write-ScriptLog -AdditionalContext $vmName
Start-VM -Name $vmName
'Start the VM completed.' | Write-ScriptLog -AdditionalContext $vmName

'Wait for the VM to be ready.' | Write-ScriptLog -AdditionalContext $vmName
Wait-PowerShellDirectReady -VMName $vmName -Credential $domainAdminCredential
'The VM is ready.' | Write-ScriptLog -AdditionalContext $vmName

'Create a PowerShell Direct session with the domain credential.' | Write-ScriptLog -AdditionalContext $vmName
$domainAdminCredPSSession = New-PSSession -VMName $vmName -Credential $domainAdminCredential
$domainAdminCredPSSession | Format-Table -Property 'Id', 'Name', 'ComputerName', 'ComputerType', 'State', 'Availability' | Out-String | Write-ScriptLog -AdditionalContext $vmName
'Create a PowerShell Direct session with the domain credential completed.' | Write-ScriptLog -AdditionalContext $vmName

'Setup the PowerShell Direct session.' | Write-ScriptLog -AdditionalContext $vmName
Invoke-PSDirectSessionSetup -Session $domainAdminCredPSSession -CommonModuleFilePathInVM $commonModuleFilePathInVM
'Setup the PowerShell Direct session completed.' | Write-ScriptLog -AdditionalContext $vmName

# NOTE: To preset WAC connections for the domain Administrator, the preset operation is required by
# the domain Administrator because WAC connections are managed based on each user.
'Configure Windows Admin Center for the domain Administrator.' | Write-ScriptLog -AdditionalContext $vmName
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
} | Out-String | Write-ScriptLog -AdditionalContext $vmName
'Configure Windows Admin Center for the domain Administrator completed.' | Write-ScriptLog -AdditionalContext $vmName

'Clean up the PowerShell Direct session.' | Write-ScriptLog -AdditionalContext $vmName
Invoke-PSDirectSessionCleanup -Session $domainAdminCredPSSession -CommonModuleFilePathInVM $commonModuleFilePathInVM
'Clean up the PowerShell Direct session completed.' | Write-ScriptLog -AdditionalContext $vmName

'The WAC VM creation has been completed.' | Write-ScriptLog -AdditionalContext $vmName
Stop-ScriptLogging
