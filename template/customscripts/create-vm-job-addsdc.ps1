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

$vmName = $labConfig.addsDC.vmName

'Start blocking the AD DS domain operations on other VMs.' | Write-ScriptLog -AdditionalContext $vmName
Block-AddsDomainOperation

# Hyper-V VM

'Create the OS disk for the VM.' | Write-ScriptLog -AdditionalContext $vmName
$params = @{
    OperatingSystem = [HciLab.OSSku]::WindowsServer2022
    ImageIndex      = [HciLab.OSImageIndex]::WSDatacenterServerCore  # Datacenter (Server Core)
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
'Change the VM''s automatic stop action completed.' | Write-ScriptLog -AdditionalContext $vmName

'Configure the VM''s processor.' | Write-ScriptLog -AdditionalContext $vmName
$vmProcessorCount = 4
if ((Get-VMHost).LogicalProcessorCount -lt $vmProcessorCount) { $vmProcessorCount = (Get-VMHost).LogicalProcessorCount }
Set-VMProcessor -VMName $vmName -Count $vmProcessorCount
'Configure the VM''s processor completed.' | Write-ScriptLog -AdditionalContext $vmName

'Configure the VM''s memory.' | Write-ScriptLog -AdditionalContext $vmName
$params = @{
    VMName               = $vmName
    StartupBytes         = 1GB
    DynamicMemoryEnabled = $true
    MinimumBytes         = 512MB
    MaximumBytes         = $labConfig.addsDC.maximumRamBytes
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
'Configure the {0} network adapter.' -f $labConfig.addsDC.netAdapters.management.name | Write-ScriptLog -AdditionalContext $vmName
$paramsForAdd = @{
    VMName       = $vmName
    Name         = $labConfig.addsDC.netAdapters.management.name
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
'Configure the {0} network adapter completed.' -f $labConfig.addsDC.netAdapters.management.name | Write-ScriptLog -AdditionalContext $vmName

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
        'AD-Domain-Services'
        # DNS, FS-FileServer, RSAT-AD-PowerShell are automatically installed as dependencies.
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
} | Out-String | Write-ScriptLog -AdditionalContext $vmName
'Configure registry values within the VM completed.' | Write-ScriptLog -AdditionalContext $vmName

'Configure network settings within the VM.' | Write-ScriptLog -AdditionalContext $vmName
$params = @{
    InputObject = [PSCustomObject] @{
        VMConfig = $LabConfig.addsDC
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
    'Configure the IP & DNS on the {0} network adapter completed.' -f $VMConfig.netAdapters.management.name | Write-ScriptLog

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

'Install AD DS (Creating a new forest) within the VM.' | Write-ScriptLog -AdditionalContext $vmName
$params = @{
    InputObject = [PSCustomObject] @{
        DomainName    = $labConfig.addsDomain.fqdn
        AdminPassword = $adminPassword
    }
}
Invoke-Command @params -Session $localAdminCredPSSession -ScriptBlock {
    param (
        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [string] $DomainName,

        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [SecureString] $AdminPassword
    )

    $params = @{
        DomainName                    = $DomainName
        InstallDns                    = $true
        SafeModeAdministratorPassword = $AdminPassword
        NoRebootOnCompletion          = $true
        Force                         = $true
    }
    Install-ADDSForest @params
} | Out-String | Write-ScriptLog -AdditionalContext $vmName
'Install AD DS (Creating a new forest) within the VM completed.' | Write-ScriptLog -AdditionalContext $vmName

'Clean up the PowerShell Direct session.' | Write-ScriptLog -AdditionalContext $vmName
Invoke-PSDirectSessionCleanup -Session $localAdminCredPSSession -CommonModuleFilePathInVM $commonModuleFilePathInVM
'Clean up the PowerShell Direct session completed.' | Write-ScriptLog -AdditionalContext $vmName

'Stop the VM.' | Write-ScriptLog -AdditionalContext $vmName
Stop-VM -Name $vmName
'Stop the VM completed.' | Write-ScriptLog -AdditionalContext $vmName

'Start the VM.' | Write-ScriptLog -AdditionalContext $vmName
Start-VM -Name $vmName
'Start the VM completed.' | Write-ScriptLog -AdditionalContext $vmName

'Wait for ready to the domain controller.' | Write-ScriptLog -AdditionalContext $vmName
$domainAdminCredential = New-LogonCredential -DomainFqdn $labConfig.addsDomain.fqdn -Password $adminPassword
# The DC's computer name is the same as the VM name. It's specified in the unattend.xml.
Wait-DomainControllerServiceReady -AddsDcVMName $vmName -AddsDcComputerName $vmName -Credential $domainAdminCredential
'The domain controller is ready.' | Write-ScriptLog -AdditionalContext $vmName

'Allow the AD DS domain operations on other VMs.' | Write-ScriptLog -AdditionalContext $vmName
Unblock-AddsDomainOperation

'The AD DS Domain Controller VM creation has been completed.' | Write-ScriptLog -AdditionalContext $vmName
Stop-ScriptLogging
