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

$vmName = $labConfig.addsDC.vmName

'Block the AD DS domain operations on other VMs.' | Write-ScriptLog -Context $vmName
Block-AddsDomainOperation

'Creating the OS disk for the VM...' | Write-ScriptLog -Context $vmName
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
$vmProcessorCount = 4
if ((Get-VMHost).LogicalProcessorCount -lt $vmProcessorCount) { $vmProcessorCount = (Get-VMHost).LogicalProcessorCount }
Set-VMProcessor -VMName $vmName -Count $vmProcessorCount

'Setting the VM''s memory configuration...' | Write-ScriptLog -Context $vmName
$params = @{
    VMName               = $vmName
    StartupBytes         = 1GB
    DynamicMemoryEnabled = $true
    MinimumBytes         = 512MB
    MaximumBytes         = $labConfig.addsDC.maximumRamBytes
}
Set-VMMemory @params

'Enabling vTPM...' | Write-ScriptLog -Context $vmName
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
    (
        'Caught exception on enable vTPM, will retry to enable vTPM... ' +
        '(ExceptionMessage: {0} | Exception: {1} | FullyQualifiedErrorId: {2} | CategoryInfo: {3} | ErrorDetailsMessage: {4})'
    ) -f @(
        $_.Exception.Message, $_.Exception.GetType().FullName, $_.FullyQualifiedErrorId, $_.CategoryInfo.ToString(), $_.ErrorDetails.Message
    ) | Write-ScriptLog -Context $vmName

    # Rescue only once by retry.
    Set-VMKeyProtector @params | Enable-VMTPM
}

'Setting the VM''s network adapter configuration...' | Write-ScriptLog -Context $vmName
Get-VMNetworkAdapter -VMName $vmName | Remove-VMNetworkAdapter

# Management
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
        'AD-Domain-Services'
        # DNS, FS-FileServer, RSAT-AD-PowerShell are automatically installed as dependencies.
    )
    LogFolder   = $labConfig.labHost.folderPath.log
}
Install-WindowsFeatureToVhd @params

'Starting the VM...' | Write-ScriptLog -Context $vmName
Start-VMWithRetry -VMName $vmName

'Waiting for the VM to be ready...' | Write-ScriptLog -Context $vmName
$localAdminCredential = New-LogonCredential -DomainFqdn '.' -Password $adminPassword
Wait-PowerShellDirectReady -VMName $vmName -Credential $localAdminCredential

'Create a PowerShell Direct session...' | Write-ScriptLog -Context $vmName
$localAdminCredPSSession = New-PSSession -VMName $vmName -Credential $localAdminCredential
$localAdminCredPSSession |
    Format-Table -Property 'Id', 'Name', 'ComputerName', 'ComputerType', 'State', 'Availability' |
    Out-String |
    Write-ScriptLog -Context $env:ComputerName

'Copying the common module file into the VM...' | Write-ScriptLog -Context $vmName
$commonModuleFilePathInVM = Copy-PSModuleIntoVM -Session $localAdminCredPSSession -ModuleFilePathToCopy (Get-Module -Name 'common').Path

'Setup the PowerShell Direct session...' | Write-ScriptLog -Context $vmName
Invoke-PSDirectSessionSetup -Session $localAdminCredPSSession -CommonModuleFilePathInVM $commonModuleFilePathInVM

'Configuring registry values within the VM...' | Write-ScriptLog -Context $vmName
Invoke-Command -Session $localAdminCredPSSession -ScriptBlock {
    'Stop Server Manager launch at logon.' | Write-ScriptLog -Context $env:ComputerName -UseInScriptBlock
    Set-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\ServerManager' -Name 'DoNotOpenServerManagerAtLogon' -Value 1

    'Stop Windows Admin Center popup at Server Manager launch.' | Write-ScriptLog -Context $env:ComputerName -UseInScriptBlock
    Set-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\ServerManager' -Name 'DoNotPopWACConsoleAtSMLaunch' -Value 1

    'Hide the Network Location wizard. All networks will be Public.' | Write-ScriptLog -Context $env:ComputerName -UseInScriptBlock
    New-RegistryKey -ParentPath 'HKLM:\SYSTEM\CurrentControlSet\Control\Network' -KeyName 'NewNetworkWindowOff'
} | Out-String | Write-ScriptLog -Context $vmName

'Configuring network settings within the VM...' | Write-ScriptLog -Context $vmName
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

    'Renaming the network adapters...' | Write-ScriptLog -Context $env:ComputerName -UseInScriptBlock
    Get-NetAdapterAdvancedProperty -RegistryKeyword 'HyperVNetworkAdapterName' | ForEach-Object -Process {
        Rename-NetAdapter -Name $_.Name -NewName $_.DisplayValue
    }

    # Management
    'Setting the IP & DNS configuration on the {0} network adapter...' -f $VMConfig.netAdapters.management.name | Write-ScriptLog -Context $env:ComputerName -UseInScriptBlock
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
    Set-DnsClientServerAddress @paramsForSetDnsClientServerAddress
    'The IP & DNS configuration on the {0} network adapter is completed.' -f $VMConfig.netAdapters.management.name | Write-ScriptLog -Context $env:ComputerName -UseInScriptBlock

} | Out-String | Write-ScriptLog -Context $vmName

'Installing AD DS (Creating a new forest) within the VM...' | Write-ScriptLog -Context $vmName
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
} | Out-String | Write-ScriptLog -Context $vmName

'Cleaning up the PowerShell Direct session...' | Write-ScriptLog -Context $vmName
Invoke-PSDirectSessionCleanup -Session $localAdminCredPSSession -CommonModuleFilePathInVM $commonModuleFilePathInVM

'Stopping the VM...' | Write-ScriptLog -Context $vmName
Stop-VM -Name $vmName

'Starting the VM...' | Write-ScriptLog -Context $vmName
Start-VM -Name $vmName

'Waiting for ready to the domain controller...' | Write-ScriptLog -Context $vmName
$domainAdminCredential = New-LogonCredential -DomainFqdn $labConfig.addsDomain.fqdn -Password $adminPassword
# The DC's computer name is the same as the VM name. It's specified in the unattend.xml.
Wait-DomainControllerServiceReady -AddsDcVMName $vmName -AddsDcComputerName $vmName -Credential $domainAdminCredential

'Allow the AD DS domain operations on other VMs.' | Write-ScriptLog -Context $vmName
Unblock-AddsDomainOperation

'The AD DS Domain Controller VM creation has been completed.' | Write-ScriptLog -Context $vmName

Stop-ScriptLogging
