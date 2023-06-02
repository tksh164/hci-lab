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
    OperatingSystem = 'ws2022'
    ImageIndex      = 3  # Datacenter (Server Core)
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
Set-VMProcessor -VMName $vmName -Count 2

'Setting the VM''s memory configuration...' | Write-ScriptLog -Context $vmName
$params = @{
    VMName               = $vmName
    StartupBytes         = 1GB
    DynamicMemoryEnabled = $true
    MinimumBytes         = 512MB
    MaximumBytes         = $labConfig.addsDC.maximumRamBytes
}
Set-VMMemory @params

'Setting the VM''s network adapter configuration...' | Write-ScriptLog -Context $vmName
Get-VMNetworkAdapter -VMName $vmName | Remove-VMNetworkAdapter

# Management
$paramsForAdd = @{
    VMName       = $vmName
    Name         = $labConfig.addsDC.netAdapter.management.name
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
        'AD-Domain-Services'
    )
    LogFolder   = $labConfig.labHost.folderPath.log
}
Install-WindowsFeatureToVhd @params

'Starting the VM...' | Write-ScriptLog -Context $vmName
Start-VMWithRetry -VMName $vmName

'Waiting for ready to the VM...' | Write-ScriptLog -Context $vmName
$localAdminCredential = New-LogonCredential -DomainFqdn '.' -Password $adminPassword
Wait-PowerShellDirectReady -VMName $vmName -Credential $localAdminCredential

'Configuring the inside of the VM...' | Write-ScriptLog -Context $vmName
$params = @{
    VMName      = $vmName
    Credential  = $localAdminCredential
    InputObject = [PSCustomObject] @{
        VMName                 = $vmName
        AdminPassword          = $adminPassword
        LabConfig              = $labConfig
        FunctionsToInject      = @(
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
        [SecureString] $AdminPassword,

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

    'Renaming the network adapters...' | Write-ScriptLog -Context $VMName -UseInScriptBlock
    Get-NetAdapterAdvancedProperty -RegistryKeyword 'HyperVNetworkAdapterName' | ForEach-Object -Process {
        Rename-NetAdapter -Name $_.Name -NewName $_.DisplayValue
    }

    'Setting the IP configuration on the network adapter...' | Write-ScriptLog -Context $VMName -UseInScriptBlock
    $params = @{
        AddressFamily  = 'IPv4'
        IPAddress      = $LabConfig.addsDC.netAdapter.management.ipAddress
        PrefixLength   = $LabConfig.addsDC.netAdapter.management.prefixLength
        DefaultGateway = $LabConfig.addsDC.netAdapter.management.defaultGateway
    }
    Get-NetAdapter -Name $LabConfig.addsDC.netAdapter.management.name | New-NetIPAddress @params
    
    'Setting the DNS configuration on the network adapter...' | Write-ScriptLog -Context $VMName -UseInScriptBlock
    Get-NetAdapter -Name $LabConfig.addsDC.netAdapter.management.name |
        Set-DnsClientServerAddress -ServerAddresses $LabConfig.addsDC.netAdapter.management.dnsServerAddresses

    'Installing AD DS (Creating a new forest)...' | Write-ScriptLog -Context $VMName -UseInScriptBlock
    $params = @{
        DomainName                    = $LabConfig.addsDomain.fqdn
        InstallDns                    = $true
        SafeModeAdministratorPassword = $AdminPassword
        NoRebootOnCompletion          = $true
        Force                         = $true
    }
    Install-ADDSForest @params
} | Out-String | Write-ScriptLog -Context $vmName

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
