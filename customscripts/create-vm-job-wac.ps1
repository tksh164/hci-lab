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

$vmName = $labConfig.wac.vmName

'Creating the OS disk for the VM...' | Write-ScriptLog -Context $vmName
$params = @{
    OperatingSystem = 'ws2022'
    ImageIndex      = 4  # Datacenter with Desktop Experience
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

'Setting the VM''s processor configuration...' | Write-ScriptLog -Context $vmName
Set-VMProcessor -VMName $vmName -Count 4

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
        'RSAT-DNS-Server',
        'RSAT-Clustering-Mgmt',
        'RSAT-Clustering-PowerShell',
        'Hyper-V-Tools',
        'Hyper-V-PowerShell'
    )
    LogFolder   = $labConfig.labHost.folderPath.log
}
Install-WindowsFeatureToVhd @params

'Starting the VM...' | Write-ScriptLog -Context $vmName
Start-VMWithRetry -VMName $vmName

'Waiting for ready to the VM...' | Write-ScriptLog -Context $vmName
$params = @{
    TypeName     = 'System.Management.Automation.PSCredential'
    ArgumentList = '.\Administrator', $adminPassword
}
$localAdminCredential = New-Object @params
WaitingForReadyToVM -VMName $vmName -Credential $localAdminCredential

'Downloading the Windows Admin Center installer...' | Write-ScriptLog -Context $vmName
$params = @{
    SourceUri      = 'https://aka.ms/WACDownload'
    DownloadFolder = $labConfig.labHost.folderPath.temp
    FileNameToSave = 'WindowsAdminCenter.msi'
}
$wacInstallerFile = Invoke-FileDownload @params
$wacInstallerFile | Out-String | Write-ScriptLog -Context $vmName

'Creating a new SSL server authentication certificate for Windows Admin Center...' | Write-ScriptLog -Context $vmName
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
        ('2.5.29.17={{text}}DNS={0}' -f $vmName)
    )
}
$wacCret = New-SelfSignedCertificate @params | Move-Item -Destination 'Cert:\LocalMachine\Root' -PassThru

'Exporting the Windows Admin Center certificate...' | Write-ScriptLog -Context $vmName
$wacPfxFilePathOnLabHost = [IO.Path]::Combine($labConfig.labHost.folderPath.temp, 'wac.pfx')
$wacCret | Export-PfxCertificate -FilePath $wacPfxFilePathOnLabHost -Password $adminPassword | Out-String | Write-ScriptLog -Context $vmName

# Copy the Windows Admin Center related files into the VM.
$psSession = New-PSSession -VMName $vmName -Credential $localAdminCredential

'Copying the Windows Admin Center installer into the VM...' | Write-ScriptLog -Context $vmName
$wacInstallerFilePathInVM = [IO.Path]::Combine('C:\Windows\Temp', [IO.Path]::GetFileName($wacInstallerFile.FullName))
Copy-Item -ToSession $psSession -Path $wacInstallerFile.FullName -Destination $wacInstallerFilePathInVM

'Copying the Windows Admin Center certificate into the VM...' | Write-ScriptLog -Context $vmName
$wacPfxFilePathInVM = [IO.Path]::Combine('C:\Windows\Temp', [IO.Path]::GetFileName($wacPfxFilePathOnLabHost))
Copy-Item -ToSession $psSession -Path $wacPfxFilePathOnLabHost -Destination $wacPfxFilePathInVM

$psSession | Remove-PSSession

'Configuring the inside of the VM...' | Write-ScriptLog -Context $vmName
$params = @{
    VMName      = $vmName
    Credential  = $localAdminCredential
    InputObject = [PSCustomObject] @{
        VMName                   = $vmName
        WacInstallerFilePathInVM = $wacInstallerFilePathInVM
        WacPfxFilePathInVM       = $wacPfxFilePathInVM
        WacPfxPassword           = $adminPassword
        LabConfig                = $labConfig
        FunctionsToInject        = @(
            [PSCustomObject] @{
                Name           = 'Write-ScriptLog'
                Implementation = (${function:Write-ScriptLog}).ToString()
            },
            [PSCustomObject] @{
                Name           = 'New-RegistryKey'
                Implementation = (${function:New-RegistryKey}).ToString()
            }
        )
    }
}
Invoke-Command @params -ScriptBlock {
    param (
        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [string] $VMName,

        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [string] $WacInstallerFilePathInVM,

        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [string] $WacPfxFilePathInVM,

        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [SecureString] $WacPfxPassword,

        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [PSCustomObject] $LabConfig,

        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [PSCustomObject[]] $FunctionsToInject
    )

    $ErrorActionPreference = [Management.Automation.ActionPreference]::Stop
    $WarningPreference = [Management.Automation.ActionPreference]::Continue
    $VerbosePreference = [Management.Automation.ActionPreference]::Continue
    $ProgressPreference = [Management.Automation.ActionPreference]::SilentlyContinue

    # Create injected functions.
    foreach ($func in $FunctionsToInject) {
        New-Item -Path 'function:' -Name $func.Name -Value $func.Implementation -Force | Out-Null
    }

    'Stop Server Manager launch at logon.' | Write-ScriptLog -Context $VMName -UseInScriptBlock
    Set-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\ServerManager' -Name 'DoNotOpenServerManagerAtLogon' -Value 1

    'Stop Windows Admin Center popup at Server Manager launch.' | Write-ScriptLog -Context $VMName -UseInScriptBlock
    Set-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\ServerManager' -Name 'DoNotPopWACConsoleAtSMLaunch' -Value 1

    'Hide the Network Location wizard. All networks will be Public.' | Write-ScriptLog -Context $VMName -UseInScriptBlock
    New-RegistryKey -ParentPath 'HKLM:\SYSTEM\CurrentControlSet\Control\Network' -KeyName 'NewNetworkWindowOff'

    'Setting to hide the first run experience of Microsoft Edge.' | Write-ScriptLog -Context $VMName -UseInScriptBlock
    New-RegistryKey -ParentPath 'HKLM:\SOFTWARE\Policies\Microsoft' -KeyName 'Edge'
    Set-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' -Name 'HideFirstRunExperience' -Value 1

    'Renaming the network adapters...' | Write-ScriptLog -Context $VMName -UseInScriptBlock
    Get-NetAdapterAdvancedProperty -RegistryKeyword 'HyperVNetworkAdapterName' | ForEach-Object -Process {
        Rename-NetAdapter -Name $_.Name -NewName $_.DisplayValue
    }

    'Setting the IP configuration on the network adapter...' | Write-ScriptLog -Context $VMName -UseInScriptBlock
    $params = @{
        AddressFamily  = 'IPv4'
        IPAddress      = $LabConfig.wac.netAdapter.management.ipAddress
        PrefixLength   = $LabConfig.wac.netAdapter.management.prefixLength
        DefaultGateway = $LabConfig.wac.netAdapter.management.defaultGateway
    }
    Get-NetAdapter -Name $LabConfig.wac.netAdapter.management.name | New-NetIPAddress @params
    
    'Setting the DNS configuration on the network adapter...' | Write-ScriptLog -Context $VMName -UseInScriptBlock
    Get-NetAdapter -Name $LabConfig.wac.netAdapter.management.name |
        Set-DnsClientServerAddress -ServerAddresses $LabConfig.wac.netAdapter.management.dnsServerAddresses

    # Import required to Root and My both stores.
    'Importing Windows Admin Center certificate...' | Write-ScriptLog -Context $VMName -UseInScriptBlock
    Import-PfxCertificate -CertStoreLocation 'Cert:\LocalMachine\Root' -FilePath $WacPfxFilePathInVM -Password $WacPfxPassword -Exportable
    $wacCert = Import-PfxCertificate -CertStoreLocation 'Cert:\LocalMachine\My' -FilePath $WacPfxFilePathInVM -Password $WacPfxPassword -Exportable
    Remove-Item -LiteralPath $WacPfxFilePathInVM -Force

    'Installing Windows Admin Center...' | Write-ScriptLog -Context $VMName -UseInScriptBlock
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

    'Updating Windows Admin Center extensions...' | Write-ScriptLog -Context $VMName -UseInScriptBlock
    $wacExtensionToolsPSModulePath = [IO.Path]::Combine($env:ProgramFiles, 'Windows Admin Center\PowerShell\Modules\ExtensionTools\ExtensionTools.psm1')
    Import-Module -Name $wacExtensionToolsPSModulePath -Force
    [Uri] $gatewayEndpointUri = 'https://{0}' -f $env:ComputerName

    $retryLimit = 50
    $retryInterval = 5
    for ($retryCount = 0; $retryCount -lt $retryLimit; $retryCount++) {
        try {
            # NOTE: Windows Admin Center extension updating will fail sometimes due to unable to connect remote server.
            Get-Extension -GatewayEndpoint $gatewayEndpointUri -ErrorAction Stop |
                Where-Object -Property 'isLatestVersion' -EQ $false |
                ForEach-Object -Process {
                    $wacExtension = $_
                    Update-Extension -GatewayEndpoint $gatewayEndpointUri -ExtensionId $wacExtension.id -Verbose -ErrorAction Stop | Out-Null
                }
            break
        }
        catch {
            'Will retry updating Windows Admin Center extensions...' | Write-ScriptLog -Context $VMName -UseInScriptBlock
            Start-Sleep -Seconds $retryInterval
        }
    }
    if ($retryCount -ge $retryLimit) {
        'Failed Windows Admin Center extension update. Need manual update later.' | Write-ScriptLog -Context $VMName -UseInScriptBlock
    }

    Get-Extension -GatewayEndpoint $gatewayEndpointUri |
        Sort-Object -Property id |
        Format-table -Property id, status, version, isLatestVersion, title

    'Setting Windows Integrated Authentication registry for Windows Admin Center...' | Write-ScriptLog -Context $VMName -UseInScriptBlock
    New-RegistryKey -ParentPath 'HKLM:\SOFTWARE\Policies\Microsoft' -KeyName 'Edge'
    Set-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' -Name 'AuthServerAllowlist' -Value $VMName

    'Creating shortcut for Windows Admin Center on the desktop...' | Write-ScriptLog -Context $VMName -UseInScriptBlock
    $wshShell = New-Object -ComObject 'WScript.Shell'
    $shortcut = $wshShell.CreateShortcut('C:\Users\Public\Desktop\Windows Admin Center.lnk')
    $shortcut.TargetPath = 'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe'
    $shortcut.Arguments = 'https://{0}' -f $env:ComputerName
    $shortcut.Description = 'Windows Admin Center for the lab environment.'
    $shortcut.IconLocation = 'imageres.dll,1'
    $shortcut.Save()
} | Out-String | Write-ScriptLog -Context $vmName

Wait-AddsDcDeploymentCompletion

'Waiting for ready to the domain controller...' | Write-ScriptLog -Context $vmName
$domainAdminCredential = CreateDomainCredential -DomainFqdn $labConfig.addsDomain.fqdn -Password $adminPassword
# The DC's computer name is the same as the VM name. It's specified in the unattend.xml.
WaitingForReadyToAddsDcVM -AddsDcVMName $labConfig.addsDC.vmName -AddsDcComputerName $labConfig.addsDC.vmName -Credential $domainAdminCredential

'Joining the VM to the AD domain...' | Write-ScriptLog -Context $vmName
$params = @{
    VMName                = $vmName
    LocalAdminCredential  = $localAdminCredential
    DomainFqdn            = $labConfig.addsDomain.fqdn
    DomainAdminCredential = $domainAdminCredential
}
JoinVMToADDomain @params

'Stopping the VM...' | Write-ScriptLog -Context $vmName
Stop-VM -Name $vmName

'Starting the VM...' | Write-ScriptLog -Context $vmName
Start-VM -Name $vmName

'Waiting for ready to the VM...' | Write-ScriptLog -Context $vmName
WaitingForReadyToVM -VMName $vmName -Credential $domainAdminCredential

# NOTE: To preset WAC connections for the domain Administrator, the preset operation is required by
# the domain Administrator because WAC connections are managed based on each user.
'Configuring Windows Admin Center for the domain Administrator...' | Write-ScriptLog -Context $vmName
$params = @{
    VMName      = $vmName
    Credential  = $domainAdminCredential
    InputObject = [PSCustomObject] @{
        VMName            = $vmName
        LabConfig         = $labConfig
        FunctionsToInject = @(
            [PSCustomObject] @{
                Name           = 'Write-ScriptLog'
                Implementation = (${function:Write-ScriptLog}).ToString()
            },
            [PSCustomObject] @{
                Name           = 'Format-HciNodeName'
                Implementation = (${function:Format-HciNodeName}).ToString()
            }
        )
    }
}
Invoke-Command @params -ScriptBlock {
    param (
        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [string] $VMName,

        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [PSCustomObject] $LabConfig,

        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [PSCustomObject[]] $FunctionsToInject
    )

    $ErrorActionPreference = [Management.Automation.ActionPreference]::Stop
    $WarningPreference = [Management.Automation.ActionPreference]::Continue
    $VerbosePreference = [Management.Automation.ActionPreference]::Continue
    $ProgressPreference = [Management.Automation.ActionPreference]::SilentlyContinue

    # Create injected functions.
    foreach ($func in $FunctionsToInject) {
        New-Item -Path 'function:' -Name $func.Name -Value $func.Implementation -Force | Out-Null
    }

    'Importing server connections to Windows Admin Center for the domain Administrator...' | Write-ScriptLog -Context $VMName -UseInScriptBlock
    $wacConnectionToolsPSModulePath = [IO.Path]::Combine($env:ProgramFiles, 'Windows Admin Center\PowerShell\Modules\ConnectionTools\ConnectionTools.psm1')
    Import-Module -Name $wacConnectionToolsPSModulePath -Force

    # Create a connection list file to import to Windows Admin Center.
    $formatValues = @()
    $formatValues += $LabConfig.addsDomain.fqdn
    $formatValues += $LabConfig.addsDC.vmName
    $formatValues += $LabConfig.wac.vmName
    for ($nodeIndex = 0; $nodeIndex -lt $LabConfig.hciNode.nodeCount; $nodeIndex++) {
        $formatValues += Format-HciNodeName -Format $LabConfig.hciNode.vmName -Offset $LabConfig.hciNode.vmNameOffset -Index $nodeIndex
    }
    $formatValues += $LabConfig.hciCluster.name
    $wacConnectionFilePathInVM = [IO.Path]::Combine('C:\Windows\Temp', 'wac-connections.txt')
    @'
"name","type","tags","groupId"
"{1}.{0}","msft.sme.connection-type.server","",
"{2}.{0}","msft.sme.connection-type.server","",
"{3}.{0}","msft.sme.connection-type.server","{5}.{0}",
"{4}.{0}","msft.sme.connection-type.server","{5}.{0}",
"{5}.{0}","msft.sme.connection-type.cluster","{5}.{0}",
'@ -f $formatValues | Set-Content -LiteralPath $wacConnectionFilePathInVM -Force

    # Import connections to Windows Admin Center.
    [Uri] $gatewayEndpointUri = 'https://{0}' -f $env:ComputerName
    Import-Connection -GatewayEndpoint $gatewayEndpointUri -FileName $wacConnectionFilePathInVM
    Remove-Item -LiteralPath $wacConnectionFilePathInVM -Force
} | Out-String | Write-ScriptLog -Context $vmName

'The WAC VM creation has been completed.' | Write-ScriptLog -Context $vmName

Stop-ScriptLogging
