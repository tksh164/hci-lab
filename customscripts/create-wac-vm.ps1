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

$vmName = $labConfig.wac.vmName

'Creating the OS disk for the VM...' | WriteLog -Context $vmName
$imageIndex = 4  # Datacenter with Desktop Experience
$params = @{
    Differencing = $true
    ParentPath   = [IO.Path]::Combine($labConfig.labHost.folderPath.vhd, (GetBaseVhdFileName -OperatingSystem 'ws2022' -ImageIndex $imageIndex -Culture $labConfig.guestOS.culture))
    Path         = [IO.Path]::Combine($labConfig.labHost.folderPath.vm, $vmName, 'osdisk.vhdx')
}
$vmOSDiskVhd = New-VHD  @params

'Creating the VM...' | WriteLog -Context $vmName
$params = @{
    Name       = $vmName
    Path       = $labConfig.labHost.folderPath.vm
    VHDPath    = $vmOSDiskVhd.Path
    Generation = 2
}
New-VM @params

'Setting the VM''s processor configuration...' | WriteLog -Context $vmName
Set-VMProcessor -VMName $vmName -Count 4

'Setting the VM''s memory configuration...' | WriteLog -Context $vmName
$params = @{
    VMName               = $vmName
    StartupBytes         = 1GB
    DynamicMemoryEnabled = $true
    MinimumBytes         = 512MB
    MaximumBytes         = 6GB
}
Set-VMMemory @params

'Setting the VM''s network adapter configuration...' | WriteLog -Context $vmName
Get-VMNetworkAdapter -VMName $vmName | Remove-VMNetworkAdapter
$params = @{
    VMName       = $vmName
    Name         = $labConfig.wac.netAdapter.management.name
    SwitchName   = $labConfig.labHost.vSwitch.nat.name
    DeviceNaming = 'On'
}
Add-VMNetworkAdapter @params

'Generating the unattend answer XML...' | WriteLog -Context $vmName
$adminPassword = GetSecret -KeyVaultName $labConfig.keyVault.name -SecretName $labConfig.keyVault.secretName
$unattendAnswerFileContent = GetUnattendAnswerFileContent -ComputerName $vmName -Password $adminPassword -Culture $labConfig.guestOS.culture

'Injecting the unattend answer file to the VM...' | WriteLog -Context $vmName
InjectUnattendAnswerFile -VhdPath $vmOSDiskVhd.Path -UnattendAnswerFileContent $unattendAnswerFileContent

'Installing the roles and features to the VHD...' | WriteLog -Context $vmName
$features = @(
    'RSAT-ADDS-Tools',
    'RSAT-AD-AdminCenter',
    'RSAT-AD-PowerShell',
    'RSAT-Clustering-Mgmt',
    'RSAT-Clustering-PowerShell',
    'Hyper-V-Tools',
    'Hyper-V-PowerShell'
)
Install-WindowsFeature -Vhd $vmOSDiskVhd.Path -Name $features

'Starting the VM...' | WriteLog -Context $vmName
WaitingForStartingVM -VMName $vmName

'Waiting for ready to the VM...' | WriteLog -Context $vmName
$params = @{
    TypeName     = 'System.Management.Automation.PSCredential'
    ArgumentList = 'Administrator', $adminPassword
}
$localAdminCredential = New-Object @params
WaitingForReadyToVM -VMName $vmName -Credential $localAdminCredential

'Downloading the Windows Admin Center installer...' | WriteLog -Context $vmName
$params = @{
    SourceUri      = 'https://aka.ms/WACDownload'
    DownloadFolder = $labConfig.labHost.folderPath.temp
    FileNameToSave = 'WindowsAdminCenter.msi'
}
$wacInstallerFile = DownloadFile @params
$wacInstallerFile

'Creating a new SSL server authentication certificate for Windows Admin Center...' | WriteLog -Context $vmName
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

'Exporting the Windows Admin Center certificate...' | WriteLog -Context $vmName
$wacPfxFilePathOnLabHost = [IO.Path]::Combine($labConfig.labHost.folderPath.temp, 'wac.pfx')
$wacCret | Export-PfxCertificate -FilePath $wacPfxFilePathOnLabHost -Password $adminPassword

$psSession = New-PSSession -VMName $vmName -Credential $localAdminCredential

'Copying the Windows Admin Center installer into the VM...' | WriteLog -Context $vmName
$wacInstallerFilePathInVM = [IO.Path]::Combine('C:\Windows\Temp', [IO.Path]::GetFileName($wacInstallerFile.FullName))
Copy-Item -ToSession $psSession -Path $wacInstallerFile.FullName -Destination $wacInstallerFilePathInVM

'Copying the Windows Admin Center certificate into the VM...' | WriteLog -Context $vmName
$wacPfxFilePathInVM = [IO.Path]::Combine('C:\Windows\Temp', [IO.Path]::GetFileName($wacPfxFilePathOnLabHost))
Copy-Item -ToSession $psSession -Path $wacPfxFilePathOnLabHost -Destination $wacPfxFilePathInVM

$psSession | Remove-PSSession

'Configuring the new VM...' | WriteLog -Context $vmName
$params = @{
    VMName       = $vmName
    Credential   = $localAdminCredential
    ArgumentList = ${function:WriteLog}, $vmName, $labConfig, $wacPfxFilePathInVM, $adminPassword, $wacInstallerFilePathInVM
}
Invoke-Command @params -ScriptBlock {
    $ErrorActionPreference = [Management.Automation.ActionPreference]::Stop
    $WarningPreference = [Management.Automation.ActionPreference]::Continue
    $VerbosePreference = [Management.Automation.ActionPreference]::Continue
    $ProgressPreference = [Management.Automation.ActionPreference]::SilentlyContinue

    $WriteLog = [scriptblock]::Create($args[0])
    $vmName = $args[1]
    $labConfig = $args[2]
    $wacPfxFilePathInVM = $args[3]
    $wacPfxPassword = $args[4]
    $wacInstallerFilePath = $args[5]

    'Stop Server Manager launch at logon.' | &$WriteLog -Context $vmName
    Set-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\ServerManager' -Name 'DoNotOpenServerManagerAtLogon' -Value 1

    'Stop Windows Admin Center popup at Server Manager launch.' | &$WriteLog -Context $vmName
    Set-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\ServerManager' -Name 'DoNotPopWACConsoleAtSMLaunch' -Value 1

    'Hide the Network Location wizard. All networks will be Public.' | &$WriteLog -Context $vmName
    New-Item -ItemType Directory -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Network' -Name 'NewNetworkWindowOff' -Force

    'Renaming the network adapters...' | &$WriteLog -Context $vmName
    Get-NetAdapterAdvancedProperty -RegistryKeyword 'HyperVNetworkAdapterName' | ForEach-Object -Process {
        Rename-NetAdapter -Name $_.Name -NewName $_.DisplayValue
    }

    'Setting the IP configuration on the network adapter...' | &$WriteLog -Context $vmName
    $params = @{
        AddressFamily  = 'IPv4'
        IPAddress      = $labConfig.wac.netAdapter.management.ipAddress
        PrefixLength   = $labConfig.wac.netAdapter.management.prefixLength
        DefaultGateway = $labConfig.wac.netAdapter.management.defaultGateway
    }
    Get-NetAdapter -Name $labConfig.wac.netAdapter.management.name | New-NetIPAddress @params
    
    'Setting the DNS configuration on the network adapter...' | &$WriteLog -Context $vmName
    Get-NetAdapter -Name $labConfig.wac.netAdapter.management.name |
        Set-DnsClientServerAddress -ServerAddresses $labConfig.wac.netAdapter.management.dnsServerAddresses

    # Import required to Root and My both stores.
    'Importing Windows Admin Center certificate...' | &$WriteLog -Context $vmName
    Import-PfxCertificate -CertStoreLocation 'Cert:\LocalMachine\Root' -FilePath $wacPfxFilePathInVM -Password $wacPfxPassword -Exportable
    $wacCert = Import-PfxCertificate -CertStoreLocation 'Cert:\LocalMachine\My' -FilePath $wacPfxFilePathInVM -Password $wacPfxPassword -Exportable
    Remove-Item -LiteralPath $wacPfxFilePathInVM -Force

    'Installing Windows Admin Center...' | &$WriteLog -Context $vmName
    $msiArgs = @(
        '/i',
        ('"{0}"' -f $wacInstallerFilePath),
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
    Remove-Item -LiteralPath $wacInstallerFilePath -Force

    'Updating Windows Admin Center extensions...' | &$WriteLog -Context $vmName
    $wacPSModulePath = [IO.Path]::Combine($env:ProgramFiles, 'Windows Admin Center\PowerShell\Modules\ExtensionTools\ExtensionTools.psm1')
    Import-Module -Name $wacPSModulePath -Force
    [Uri] $gatewayEndpointUri = 'https://{0}' -f $env:ComputerName
    Get-Extension -GatewayEndpoint $gatewayEndpointUri |
        Where-Object -Property 'isLatestVersion' -EQ $false |
        ForEach-Object -Process {
            $wacExtension = $_
            Update-Extension -GatewayEndpoint $gatewayEndpointUri -ExtensionId $wacExtension.id -Verbose | Out-Null
        }
    Get-Extension -GatewayEndpoint $gatewayEndpointUri |
        Sort-Object -Property id |
        Format-table -Property id, status, version, isLatestVersion, title

    'Setting Windows Integrated Authentication registry for Windows Admin Center...' | &$WriteLog -Context $vmName
    New-Item -ItemType Directory -Path 'HKLM:\SOFTWARE\Policies\Microsoft' -Name 'Edge' -Force
    Set-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' -Name 'AuthServerAllowlist' -Value 'wac'

    'Creating shortcut for Windows Admin Center on the desktop...' | &$WriteLog -Context $vmName
    $wshShell = New-Object -ComObject 'WScript.Shell'
    $shortcut = $wshShell.CreateShortcut('C:\Users\Public\Desktop\Windows Admin Center.lnk')
    $shortcut.TargetPath = 'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe'
    $shortcut.Arguments = 'https://{0}' -f $env:ComputerName
    $shortcut.Description = 'Windows Admin Center for the lab environment.'
    $shortcut.IconLocation = 'imageres.dll,1'
    $shortcut.Save()
}

'Joining the VM to the AD domain...' | WriteLog -Context $vmName
$domainAdminCredential = CreateDomainCredential -DomainFqdn $labConfig.addsDomain.fqdn -Password $adminPassword
$params = @{
    VMName                = $vmName
    LocalAdminCredential  = $localAdminCredential
    DomainFqdn            = $labConfig.addsDomain.fqdn
    DomainAdminCredential = $domainAdminCredential
}
JoinVMToADDomain @params

'Stopping the VM...' | WriteLog -Context $vmName
Stop-VM -Name $vmName

'Starting the VM...' | WriteLog -Context $vmName
Start-VM -Name $vmName

'Waiting for ready to the VM...' | WriteLog -Context $vmName
WaitingForReadyToVM -VMName $vmName -Credential $domainAdminCredential

'The WAC VM creation has been completed.' | WriteLog -Context $vmName

Stop-ScriptTranscript
