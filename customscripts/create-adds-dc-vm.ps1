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
$labConfig | ConvertTo-Json -Depth 16

$vmName = $labConfig.addsDC.vmName

'Creating the OS disk for the VM...' | Write-ScriptLog -Context $vmName
$imageIndex = 3  # Datacenter (Server Core)
$params = @{
    Differencing = $true
    ParentPath   = [IO.Path]::Combine($labConfig.labHost.folderPath.vhd, (GetBaseVhdFileName -OperatingSystem 'ws2022' -ImageIndex $imageIndex -Culture $labConfig.guestOS.culture))
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
New-VM @params

'Setting the VM''s processor configuration...' | Write-ScriptLog -Context $vmName
Set-VMProcessor -VMName $vmName -Count 2

'Setting the VM''s memory configuration...' | Write-ScriptLog -Context $vmName
$params = @{
    VMName               = $vmName
    StartupBytes         = 1GB
    DynamicMemoryEnabled = $true
    MinimumBytes         = 512MB
    MaximumBytes         = 2GB
}
Set-VMMemory @params

'Setting the VM''s network adapter configuration...' | Write-ScriptLog -Context $vmName
Get-VMNetworkAdapter -VMName $vmName | Remove-VMNetworkAdapter
$params = @{
    VMName       = $vmName
    Name         = $labConfig.addsDC.netAdapter.management.name
    SwitchName   = $labConfig.labHost.vSwitch.nat.name
    DeviceNaming = 'On'
}
Add-VMNetworkAdapter @params

'Generating the unattend answer XML...' | Write-ScriptLog -Context $vmName
$adminPassword = GetSecret -KeyVaultName $labConfig.keyVault.name -SecretName $labConfig.keyVault.secretName
$unattendAnswerFileContent = GetUnattendAnswerFileContent -ComputerName $vmName -Password $adminPassword -Culture $labConfig.guestOS.culture

'Injecting the unattend answer file to the VM...' | Write-ScriptLog -Context $vmName
InjectUnattendAnswerFile -VhdPath $vmOSDiskVhd.Path -UnattendAnswerFileContent $unattendAnswerFileContent -LogFolder $labConfig.labHost.folderPath.log

'Installing the roles and features to the VHD...' | Write-ScriptLog -Context $vmName
$features = @(
    'AD-Domain-Services'
)
Install-WindowsFeatureToVhd -VhdPath $vmOSDiskVhd.Path -FeatureName $features -LogFolder $labConfig.labHost.folderPath.log

'Starting the VM...' | Write-ScriptLog -Context $vmName
WaitingForStartingVM -VMName $vmName

'Waiting for ready to the VM...' | Write-ScriptLog -Context $vmName
$params = @{
    TypeName     = 'System.Management.Automation.PSCredential'
    ArgumentList = 'Administrator', $adminPassword
}
$localAdminCredential = New-Object @params
WaitingForReadyToVM -VMName $vmName -Credential $localAdminCredential

'Configuring the new VM...' | Write-ScriptLog -Context $vmName
$params = @{
    VMName      = $vmName
    Credential  = $localAdminCredential
    InputObject = [PSCustomObject] @{
        VMName                 = $vmName
        AdminPassword          = $adminPassword
        LabConfig              = $labConfig
        WriteLogImplementation = (${function:Write-ScriptLog}).ToString()
    }
}
Invoke-Command @params -ScriptBlock {
    param (
        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [string] $VMName,

        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [SecureString] $AdminPassword,

        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [PSCustomObject] $LabConfig,

        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [string] $WriteLogImplementation
    )

    $ErrorActionPreference = [Management.Automation.ActionPreference]::Stop
    $WarningPreference = [Management.Automation.ActionPreference]::Continue
    $VerbosePreference = [Management.Automation.ActionPreference]::Continue
    $ProgressPreference = [Management.Automation.ActionPreference]::SilentlyContinue

    New-Item -Path 'function:' -Name 'Write-ScriptLog' -Value $WriteLogImplementation -Force | Out-Null

    'Stop Server Manager launch at logon.' | Write-ScriptLog -Context $VMName
    Set-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\ServerManager' -Name 'DoNotOpenServerManagerAtLogon' -Value 1

    'Stop Windows Admin Center popup at Server Manager launch.' | Write-ScriptLog -Context $VMName
    Set-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\ServerManager' -Name 'DoNotPopWACConsoleAtSMLaunch' -Value 1

    'Stop Windows Admin Center popup at Server Manager launch.' | Write-ScriptLog -Context $VMName
    New-Item -ItemType Directory -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Network' -Name 'NewNetworkWindowOff'

    'Renaming the network adapters...' | Write-ScriptLog -Context $VMName
    Get-NetAdapterAdvancedProperty -RegistryKeyword 'HyperVNetworkAdapterName' | ForEach-Object -Process {
        Rename-NetAdapter -Name $_.Name -NewName $_.DisplayValue
    }

    'Setting the IP configuration on the network adapter...' | Write-ScriptLog -Context $VMName
    $params = @{
        AddressFamily  = 'IPv4'
        IPAddress      = $LabConfig.addsDC.netAdapter.management.ipAddress
        PrefixLength   = $LabConfig.addsDC.netAdapter.management.prefixLength
        DefaultGateway = $LabConfig.addsDC.netAdapter.management.defaultGateway
    }
    Get-NetAdapter -Name $LabConfig.addsDC.netAdapter.management.name | New-NetIPAddress @params
    
    'Setting the DNS configuration on the network adapter...' | Write-ScriptLog -Context $VMName
    Get-NetAdapter -Name $LabConfig.addsDC.netAdapter.management.name |
        Set-DnsClientServerAddress -ServerAddresses $LabConfig.addsDC.netAdapter.management.dnsServerAddresses

    'Installing AD DS (Creating a new forest)...' | Write-ScriptLog -Context $VMName
    $params = @{
        DomainName                    = $LabConfig.addsDomain.fqdn
        InstallDns                    = $true
        SafeModeAdministratorPassword = $AdminPassword
        NoRebootOnCompletion          = $true
        Force                         = $true
    }
    Install-ADDSForest @params
}

'Stopping the VM...' | Write-ScriptLog -Context $vmName
Stop-VM -Name $vmName

'Starting the VM...' | Write-ScriptLog -Context $vmName
Start-VM -Name $vmName

'Waiting for ready to the domain controller...' | Write-ScriptLog -Context $vmName
$domainAdminCredential = CreateDomainCredential -DomainFqdn $labConfig.addsDomain.fqdn -Password $adminPassword
# The DC's computer name is the same as the VM name. It's specified in the unattend.xml.
WaitingForReadyToAddsDcVM -AddsDcVMName $vmName -AddsDcComputerName $vmName -Credential $domainAdminCredential

'The AD DS Domain Controller VM creation has been completed.' | Write-ScriptLog -Context $vmName

Stop-ScriptLogging
