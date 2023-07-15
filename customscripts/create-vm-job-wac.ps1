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
$labConfig | ConvertTo-Json -Depth 16 | Out-String | Write-ScriptLog -Context $env:ComputerName

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

'Creating the OS disk for the VM...' | Write-ScriptLog -Context $vmName
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

'Creating the VM...' | Write-ScriptLog -Context $vmName
$params = @{
    Name       = $vmName
    Path       = $labConfig.labHost.folderPath.vm
    VHDPath    = $vmOSDiskVhd.Path
    Generation = 2
}
New-VM @params | Out-String | Write-ScriptLog -Context $vmName

'Changing the VM''s automatic stop action...' | Write-ScriptLog -Context $vmName
Set-VM -Name $vmName -AutomaticStopAction ShutDown

'Setting the VM''s processor configuration...' | Write-ScriptLog -Context $vmName
$vmProcessorCount = 6
if ((Get-VMHost).LogicalProcessorCount -lt $vmProcessorCount) { $vmProcessorCount = (Get-VMHost).LogicalProcessorCount }
Set-VMProcessor -VMName $vmName -Count $vmProcessorCount

'Setting the VM''s memory configuration...' | Write-ScriptLog -Context $vmName
$params = @{
    VMName               = $vmName
    StartupBytes         = 1GB
    DynamicMemoryEnabled = $true
    MinimumBytes         = 512MB
    MaximumBytes         = $labConfig.wac.maximumRamBytes
}
Set-VMMemory @params

'Setting the VM''s network adapter configuration...' | Write-ScriptLog -Context $vmName
Get-VMNetworkAdapter -VMName $vmName | Remove-VMNetworkAdapter

# Management
$paramsForAdd = @{
    VMName       = $vmName
    Name         = $labConfig.wac.netAdapter.management.name
    SwitchName   = $labConfig.labHost.vSwitch.nat.name
    DeviceNaming = [Microsoft.HyperV.PowerShell.OnOffState]::On
    Passthru     = $true
}
$paramsForSet = @{
    MacAddressSpoofing = [Microsoft.HyperV.PowerShell.OnOffState]::On
    AllowTeaming       = [Microsoft.HyperV.PowerShell.OnOffState]::On
}
Add-VMNetworkAdapter @paramsForAdd |
Set-VMNetworkAdapter @paramsForSet

'Generating the unattend answer XML...' | Write-ScriptLog -Context $vmName
$adminPassword = Get-Secret -KeyVaultName $labConfig.keyVault.name -SecretName $labConfig.keyVault.secretName.adminPassword
$params = @{
    ComputerName = $vmName
    Password     = $adminPassword
    Culture      = $labConfig.guestOS.culture
    TimeZone     = $labConfig.guestOS.timeZone
}
$unattendAnswerFileContent = New-UnattendAnswerFileContent @params

'Injecting the unattend answer file to the VM...' | Write-ScriptLog -Context $vmName
$params = @{
    VhdPath                   = $vmOSDiskVhd.Path
    UnattendAnswerFileContent = $unattendAnswerFileContent
    LogFolder                 = $labConfig.labHost.folderPath.log
}
Set-UnattendAnswerFileToVhd @params

'Installing the roles and features to the VHD...' | Write-ScriptLog -Context $vmName
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

'Starting the VM...' | Write-ScriptLog -Context $vmName
Start-VMWithRetry -VMName $vmName

'Waiting for ready to the VM...' | Write-ScriptLog -Context $vmName
$localAdminCredential = New-LogonCredential -DomainFqdn '.' -Password $adminPassword
Wait-PowerShellDirectReady -VMName $vmName -Credential $localAdminCredential

'Create a PowerShell Direct session...' | Write-ScriptLog -Context $vmName
$localAdminCredPSSession = New-PSSession -VMName $vmName -Credential $localAdminCredential
$localAdminCredPSSession |
    Format-Table -Property 'Id', 'Name', 'ComputerName', 'ComputerType', 'State', 'Availability' |
    Out-String |
    Write-ScriptLog -Context $env:ComputerName

'Copying the shared module file into the VM...' | Write-ScriptLog -Context $vmName
$sharedModuleFilePathInVM = Copy-PSModuleIntoVM -Session $localAdminCredPSSession -ModuleFilePathToCopy (Get-Module -Name 'shared').Path

'Setup the PowerShell Direct session...' | Write-ScriptLog -Context $vmName
Invoke-PSDirectSessionSetup -Session $localAdminCredPSSession -SharedModuleFilePathInVM $sharedModuleFilePathInVM

'Configuring registry values within the VM...' | Write-ScriptLog -Context $vmName
Invoke-Command -Session $localAdminCredPSSession -ScriptBlock {
    'Stop Server Manager launch at logon.' | Write-ScriptLog -Context $env:ComputerName-UseInScriptBlock
    Set-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\ServerManager' -Name 'DoNotOpenServerManagerAtLogon' -Value 1

    'Stop Windows Admin Center popup at Server Manager launch.' | Write-ScriptLog -Context $env:ComputerName -UseInScriptBlock
    Set-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\ServerManager' -Name 'DoNotPopWACConsoleAtSMLaunch' -Value 1

    'Hide the Network Location wizard. All networks will be Public.' | Write-ScriptLog -Context $env:ComputerName -UseInScriptBlock
    New-RegistryKey -ParentPath 'HKLM:\SYSTEM\CurrentControlSet\Control\Network' -KeyName 'NewNetworkWindowOff'

    'Setting to hide the first run experience of Microsoft Edge.' | Write-ScriptLog -Context $env:ComputerName -UseInScriptBlock
    New-RegistryKey -ParentPath 'HKLM:\SOFTWARE\Policies\Microsoft' -KeyName 'Edge'
    Set-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' -Name 'HideFirstRunExperience' -Value 1
} | Out-String | Write-ScriptLog -Context $vmName

'Configuring network settings within the VM...' | Write-ScriptLog -Context $vmName
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

    'Renaming the network adapters...' | Write-ScriptLog -Context $env:ComputerName -UseInScriptBlock
    Get-NetAdapterAdvancedProperty -RegistryKeyword 'HyperVNetworkAdapterName' | ForEach-Object -Process {
        Rename-NetAdapter -Name $_.Name -NewName $_.DisplayValue
    }

    'Setting the IP configuration on the network adapter...' | Write-ScriptLog -Context $env:ComputerName -UseInScriptBlock
    $params = @{
        AddressFamily  = 'IPv4'
        IPAddress      = $VMConfig.netAdapter.management.ipAddress
        PrefixLength   = $VMConfig.netAdapter.management.prefixLength
        DefaultGateway = $VMConfig.netAdapter.management.defaultGateway
    }
    Get-NetAdapter -Name $VMConfig.netAdapter.management.name | New-NetIPAddress @params
    
    'Setting the DNS configuration on the network adapter...' | Write-ScriptLog -Context $env:ComputerName -UseInScriptBlock
    Get-NetAdapter -Name $VMConfig.netAdapter.management.name |
        Set-DnsClientServerAddress -ServerAddresses $VMConfig.netAdapter.management.dnsServerAddresses
} | Out-String | Write-ScriptLog -Context $vmName

'Downloading the Windows Admin Center installer...' | Write-ScriptLog -Context $vmName
$wacInstallerFile = Invoke-WindowsAdminCenterInstallerDownload -DownloadFolderPath $labConfig.labHost.folderPath.temp
$wacInstallerFile | Out-String | Write-ScriptLog -Context $vmName

'Creating a new SSL server authentication certificate for Windows Admin Center...' | Write-ScriptLog -Context $vmName
$wacCret = New-CertificateForWindowsAdminCenter -VMName $vmName

'Exporting the Windows Admin Center certificate...' | Write-ScriptLog -Context $vmName
$wacPfxFilePathOnLabHost = [IO.Path]::Combine($labConfig.labHost.folderPath.temp, 'wac.pfx')
$wacCret | Export-PfxCertificate -FilePath $wacPfxFilePathOnLabHost -Password $adminPassword | Out-String | Write-ScriptLog -Context $vmName

# Copy the Windows Admin Center related files into the VM.
'Copying the Windows Admin Center installer into the VM...' | Write-ScriptLog -Context $vmName
$wacInstallerFilePathInVM = [IO.Path]::Combine('C:\Windows\Temp', [IO.Path]::GetFileName($wacInstallerFile.FullName))
Copy-Item -ToSession $localAdminCredPSSession -Path $wacInstallerFile.FullName -Destination $wacInstallerFilePathInVM

'Copying the Windows Admin Center certificate into the VM...' | Write-ScriptLog -Context $vmName
$wacPfxFilePathInVM = [IO.Path]::Combine('C:\Windows\Temp', [IO.Path]::GetFileName($wacPfxFilePathOnLabHost))
Copy-Item -ToSession $localAdminCredPSSession -Path $wacPfxFilePathOnLabHost -Destination $wacPfxFilePathInVM

'Installing Windows Admin Center within the VM...' | Write-ScriptLog -Context $vmName
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

    # Import the certificate to Root and My both stores required.
    'Importing Windows Admin Center certificate...' | Write-ScriptLog -Context $env:ComputerName -UseInScriptBlock
    Import-PfxCertificate -CertStoreLocation 'Cert:\LocalMachine\Root' -FilePath $WacPfxFilePathInVM -Password $WacPfxPassword -Exportable
    $wacCert = Import-PfxCertificate -CertStoreLocation 'Cert:\LocalMachine\My' -FilePath $WacPfxFilePathInVM -Password $WacPfxPassword -Exportable
    Remove-Item -LiteralPath $WacPfxFilePathInVM -Force

    'Installing Windows Admin Center...' | Write-ScriptLog -Context $env:ComputerName -UseInScriptBlock
    $msiArgs = @(
        '/i',
        ('"{0}"' -f $WacInstallerFilePathInVM),
        '/qn',
        '/L*v',
        '"C:\Windows\Temp\wac-install-log.txt"',
        'SME_PORT=443',
        ('SME_THUMBPRINT={0}' -f $wacCert.Thumbprint),
        'SSL_CERTIFICATE_OPTION=installed'
        #'SSL_CERTIFICATE_OPTION=generate'
    )
    $result = Start-Process -FilePath 'msiexec.exe' -ArgumentList $msiArgs -Wait -PassThru
    $result | Format-List -Property '*'
    if ($result.ExitCode -ne 0) {
        throw ('Windows Admin Center installation failed with exit code {0}.' -f $result.ExitCode)
    }
    Remove-Item -LiteralPath $WacInstallerFilePathInVM -Force

    &{
        $wacConnectionTestTimeout = (New-TimeSpan -Minutes 5)
        $wacConnectionTestIntervalSeconds = 5
        $startTime = Get-Date
        while ((Get-Date) -lt ($startTime + $wacConnectionTestTimeout)) {
            'Testing connection to the ServerManagementGateway service...' | Write-ScriptLog -Context $env:ComputerName -UseInScriptBlock
            if ((Test-NetConnection -ComputerName 'localhost' -Port 443).TcpTestSucceeded) {
                'Connection test to the ServerManagementGateway service succeeded.' | Write-ScriptLog -Context $env:ComputerName -UseInScriptBlock
                return
            }
            Start-Sleep -Seconds $wacConnectionTestIntervalSeconds
        }
        'Connection test to the ServerManagementGateway service failed.' | Write-ScriptLog -Context $env:ComputerName -UseInScriptBlock
    }

    'Updating Windows Admin Center extensions...' | Write-ScriptLog -Context $env:ComputerName -UseInScriptBlock
    $wacExtensionToolsPSModulePath = [IO.Path]::Combine($env:ProgramFiles, 'Windows Admin Center\PowerShell\Modules\ExtensionTools\ExtensionTools.psm1')
    Import-Module -Name $wacExtensionToolsPSModulePath -Force

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
                'Windows Admin Center extension update succeeded.' | Write-ScriptLog -Context $env:ComputerName -UseInScriptBlock

                Get-Extension -GatewayEndpoint $gatewayEndpointUri |
                    Sort-Object -Property id |
                    Format-table -Property id, status, version, isLatestVersion, title
                return
            }
            catch {
                'Will retry updating Windows Admin Center extensions...' | Write-ScriptLog -Context $env:ComputerName -UseInScriptBlock
                Start-Sleep -Seconds $retryInterval
            }
        }
        'Windows Admin Center extension update failed. Need manual update later.' | Write-ScriptLog -Context $env:ComputerName -UseInScriptBlock
    }

    'Setting Windows Integrated Authentication registry for Windows Admin Center...' | Write-ScriptLog -Context $env:ComputerName -UseInScriptBlock
    New-RegistryKey -ParentPath 'HKLM:\SOFTWARE\Policies\Microsoft' -KeyName 'Edge'
    Set-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' -Name 'AuthServerAllowlist' -Value $env:ComputerName

    'Creating shortcut for Windows Admin Center on the desktop...' | Write-ScriptLog -Context $env:ComputerName -UseInScriptBlock
    $params = @{
        ShortcutFilePath = 'C:\Users\Public\Desktop\Windows Admin Center.lnk'
        TargetPath       = 'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe'
        Arguments        = 'https://{0}' -f $env:ComputerName
        Description      = 'Windows Admin Center for the lab environment.'
        IconLocation     = 'imageres.dll,1'
    }
    New-ShortcutFile @params
} | Out-String | Write-ScriptLog -Context $vmName

$firstHciNodeName = Format-HciNodeName -Format $labConfig.hciNode.vmName -Offset $labConfig.hciNode.vmNameOffset -Index 0
'Creating a shortcut for Remote Desktop connection to the {0} VM on the desktop...' -f $firstHciNodeName | Write-ScriptLog -Context $vmName
$params = @{
    InputObject = [PSCustomObject] @{
        FirstHciNodeName = $firstHciNodeName
    }
}
Invoke-Command @params -Session $localAdminCredPSSession -ScriptBlock {
    param (
        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [string] $FirstHciNodeName
    )

    $params = @{
        ShortcutFilePath = 'C:\Users\Public\Desktop\RDC - {0}.lnk' -f $FirstHciNodeName
        TargetPath       = '%windir%\System32\mstsc.exe'
        Arguments        = '/v:{0}' -f $FirstHciNodeName  # The VM name is also the computer name.
        Description      = 'Make a remote desktop connection to the member node "{0}" VM of the HCI cluster in your lab environment.' -f $FirstHciNodeName
    }
    New-ShortcutFile @params
} | Out-String | Write-ScriptLog -Context $vmName

'Cleaning up the PowerShell Direct session...' | Write-ScriptLog -Context $vmName
# NOTE: The shared module not be deleted within the VM at this time because it will be used afterwards.
$localAdminCredPSSession | Remove-PSSession

Wait-AddsDcDeploymentCompletion

'Waiting for ready to the domain controller...' | Write-ScriptLog -Context $vmName
$domainAdminCredential = New-LogonCredential -DomainFqdn $labConfig.addsDomain.fqdn -Password $adminPassword
$params = @{
    AddsDcVMName       = $labConfig.addsDC.vmName
    AddsDcComputerName = $labConfig.addsDC.vmName  # The DC's computer name is the same as the VM name. It's specified in the unattend.xml.
    Credential         = $domainAdminCredential
}
Wait-DomainControllerServiceReady @params

'Joining the VM to the AD domain...' | Write-ScriptLog -Context $vmName
$params = @{
    VMName                = $vmName
    LocalAdminCredential  = $localAdminCredential
    DomainFqdn            = $labConfig.addsDomain.fqdn
    DomainAdminCredential = $domainAdminCredential
}
Add-VMToADDomain @params

'Stopping the VM...' | Write-ScriptLog -Context $vmName
Stop-VM -Name $vmName

'Starting the VM...' | Write-ScriptLog -Context $vmName
Start-VM -Name $vmName

'Waiting for ready to the VM...' | Write-ScriptLog -Context $vmName
Wait-PowerShellDirectReady -VMName $vmName -Credential $domainAdminCredential

'Create a PowerShell Direct session with the domain credential...' | Write-ScriptLog -Context $vmName
$domainAdminCredPSSession = New-PSSession -VMName $vmName -Credential $domainAdminCredential
$domainAdminCredPSSession |
    Format-Table -Property 'Id', 'Name', 'ComputerName', 'ComputerType', 'State', 'Availability' |
    Out-String |
    Write-ScriptLog -Context $env:ComputerName

'Setup the PowerShell Direct session...' | Write-ScriptLog -Context $vmName
Invoke-PSDirectSessionSetup -Session $domainAdminCredPSSession -SharedModuleFilePathInVM $sharedModuleFilePathInVM

# NOTE: To preset WAC connections for the domain Administrator, the preset operation is required by
# the domain Administrator because WAC connections are managed based on each user.
'Configuring Windows Admin Center for the domain Administrator...' | Write-ScriptLog -Context $vmName
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

    'Importing server connections to Windows Admin Center for the domain Administrator...' | Write-ScriptLog -Context $env:ComputerName -UseInScriptBlock
    $wacConnectionToolsPSModulePath = [IO.Path]::Combine($env:ProgramFiles, 'Windows Admin Center\PowerShell\Modules\ConnectionTools\ConnectionTools.psm1')
    Import-Module -Name $wacConnectionToolsPSModulePath -Force

    # Create a connection list file to import to Windows Admin Center.
    $clusterFqdn = '{0}.{1}' -f $LabConfig.hciCluster.name, $LabConfig.addsDomain.fqdn
    $connectionEntries = @(
        (New-WacConnectionFileEntry -Name ('{0}.{1}' -f $LabConfig.addsDC.vmName, $LabConfig.addsDomain.fqdn) -Type 'msft.sme.connection-type.server'),
        (New-WacConnectionFileEntry -Name ('{0}.{1}' -f $LabConfig.wac.vmName, $LabConfig.addsDomain.fqdn) -Type 'msft.sme.connection-type.server')
    )
    for ($nodeIndex = 0; $nodeIndex -lt $LabConfig.hciNode.nodeCount; $nodeIndex++) {
        $nodeName = Format-HciNodeName -Format $LabConfig.hciNode.vmName -Offset $LabConfig.hciNode.vmNameOffset -Index $nodeIndex
        $connectionEntries += New-WacConnectionFileEntry -Name ('{0}.{1}' -f $nodeName, $LabConfig.addsDomain.fqdn) -Type 'msft.sme.connection-type.server' -Tag $clusterFqdn
    }
    $wacConnectionFilePathInVM = [IO.Path]::Combine('C:\Windows\Temp', 'wac-connections.txt')
    New-WacConnectionFileContent -ConnectionEntry $connectionEntries | Set-Content -LiteralPath $wacConnectionFilePathInVM -Force

    # Import connections to Windows Admin Center.
    [Uri] $gatewayEndpointUri = 'https://{0}' -f $env:ComputerName
    Import-Connection -GatewayEndpoint $gatewayEndpointUri -FileName $wacConnectionFilePathInVM
    Remove-Item -LiteralPath $wacConnectionFilePathInVM -Force
} | Out-String | Write-ScriptLog -Context $vmName

'Cleaning up the PowerShell Direct session...' | Write-ScriptLog -Context $vmName
Invoke-PSDirectSessionCleanup -Session $domainAdminCredPSSession -SharedModuleFilePathInVM $sharedModuleFilePathInVM

'The WAC VM creation has been completed.' | Write-ScriptLog -Context $vmName

Stop-ScriptLogging
