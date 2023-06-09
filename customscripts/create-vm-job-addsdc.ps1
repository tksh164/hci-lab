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
        # DNS, FS-FileServer, RSAT-AD-PowerShell are automatically installed as dependencies.
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
$sharedModuleFilePath = (Get-Module -Name 'shared').Path
$sharedModuleFilePathInVM = [IO.Path]::Combine('C:\Windows\Temp', [IO.Path]::GetFileName($sharedModuleFilePath))
Copy-Item -ToSession $localAdminCredPSSession -Path $sharedModuleFilePath -Destination $sharedModuleFilePathInVM

'Setup the PowerShell Direct session...' | Write-ScriptLog -Context $vmName
$params = @{
    InputObject = [PSCustomObject] @{
        SharedModuleFilePath = $sharedModuleFilePathInVM
    }
}
Invoke-Command @params -Session $localAdminCredPSSession -ScriptBlock {
    param (
        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [string] $SharedModuleFilePath
    )

    $ErrorActionPreference = [Management.Automation.ActionPreference]::Stop
    $WarningPreference = [Management.Automation.ActionPreference]::Continue
    $VerbosePreference = [Management.Automation.ActionPreference]::Continue
    $ProgressPreference = [Management.Automation.ActionPreference]::SilentlyContinue
    Import-Module -Name $SharedModuleFilePath -Force
} #| Out-String | Write-ScriptLog -Context $vmName

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
$params = @{
    InputObject = [PSCustomObject] @{
        SharedModuleFilePath = $sharedModuleFilePathInVM
    }
}
Invoke-Command @params -Session $localAdminCredPSSession -ScriptBlock {
    param (
        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [string] $SharedModuleFilePath
    )

    'Deleting the shared module file "{0}" within the VM...' -f $SharedModuleFilePath | Write-ScriptLog -Context $env:ComputerName -UseInScriptBlock
    Remove-Item -LiteralPath $SharedModuleFilePath -Force
} | Out-String | Write-ScriptLog -Context $vmName

$localAdminCredPSSession | Remove-PSSession

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
