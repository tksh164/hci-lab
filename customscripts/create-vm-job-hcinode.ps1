[CmdletBinding()]
param (
    [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
    [uint32] $NodeIndex,

    [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
    [string[]] $PSModuleNameToImport,

    [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
    [string] $LogFileName
)

function Invoke-HciNodeRamSizeCalculation
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [int] $NodeCount,

        [Parameter(Mandatory = $true)]
        [ValidateRange(0, [long]::MaxValue)]
        [long] $AddsDcVMRamBytes,

        [Parameter(Mandatory = $true)]
        [ValidateRange(0, [long]::MaxValue)]
        [long] $WacVMRamBytes
    )

    $totalRamBytes = (Get-VMHost).MemoryCapacity
    $labHostReservedRamBytes = [Math]::Floor($totalRamBytes * 0.06)  # Reserve a few percent of the total RAM for the lab host.

    'TotalRamBytes: {0}' -f $totalRamBytes | Write-ScriptLog -Context $env:ComputerName
    'LabHostReservedRamBytes: {0}' -f $labHostReservedRamBytes | Write-ScriptLog -Context $env:ComputerName
    'AddsDcVMRamBytes: {0}' -f $AddsDcVMRamBytes | Write-ScriptLog -Context $env:ComputerName
    'WacVMRamBytes: {0}' -f $WacVMRamBytes | Write-ScriptLog -Context $env:ComputerName

    # StartupBytes should be a multiple of 2 MB (2 * 1024 * 1024 bytes).
    return [Math]::Floor((($totalRamBytes - $labHostReservedRamBytes - $AddsDcVMRamBytes - $WacVMRamBytes) / $NodeCount) / 2MB) * 2MB
}

function Get-WindowsFeatureToInstall
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string] $HciNodeOperatingSystemSku
    )

    $featureNames = @(
        'Hyper-V',  # Note: https://twitter.com/pronichkin/status/1294308601276719104
        'Failover-Clustering',
        'FS-FileServer',
        'Data-Center-Bridging',
        'RSAT-AD-PowerShell',
        'RSAT-Hyper-V-Tools',
        'RSAT-Clustering'
    )
    if ($C_AzureStackHciOperatingSystemSkus -contains $HciNodeOperatingSystemSku) {
        $featureNames += 'FS-Data-Deduplication'
        $featureNames += 'BitLocker'
    
        if ($HciNodeOperatingSystemSku -ne $C_OperatingSystemSku.AzureStackHci20H2) {
            $featureNames += 'NetworkATC'
        }
    }
    return $featureNames
}

$ErrorActionPreference = [Management.Automation.ActionPreference]::Stop
$WarningPreference = [Management.Automation.ActionPreference]::Continue
$VerbosePreference = [Management.Automation.ActionPreference]::Continue
$ProgressPreference = [Management.Automation.ActionPreference]::SilentlyContinue

Import-Module -Name $PSModuleNameToImport -Force

$labConfig = Get-LabDeploymentConfig
Start-ScriptLogging -OutputDirectory $labConfig.labHost.folderPath.log -FileName $LogFileName
$labConfig | ConvertTo-Json -Depth 16 | Out-String | Write-ScriptLog -Context $env:ComputerName

$vmName = Format-HciNodeName -Format $labConfig.hciNode.vmName -Offset $labConfig.hciNode.vmNameOffset -Index $NodeIndex

$params = @{
    OperatingSystem = $labConfig.hciNode.operatingSystem.sku
    ImageIndex      = $labConfig.hciNode.operatingSystem.imageIndex
    Culture         = $labConfig.guestOS.culture
}
$parentVhdPath = [IO.Path]::Combine($labConfig.labHost.folderPath.vhd, (Format-BaseVhdFileName @params))

$params = @{
    NodeCount        = $labConfig.hciNode.nodeCount
    AddsDcVMRamBytes = $labConfig.addsDC.maximumRamBytes
    WacVMRamBytes    = $labConfig.wac.maximumRamBytes
}
$ramBytes = Invoke-HciNodeRamSizeCalculation @params

'Creating a VM configuraton for the HCI node VM...' -f $vmName | Write-ScriptLog -Context $vmName
$nodeConfig = [PSCustomObject] @{
    VMName            = $vmName
    ParentVhdPath     = $parentVhdPath
    RamBytes          = $ramBytes
    OperatingSystem   = $labConfig.hciNode.operatingSystem.sku
    ImageIndex        = $labConfig.hciNode.operatingSystem.imageIndex
    AdminPassword     = Get-Secret -KeyVaultName $labConfig.keyVault.name -SecretName $labConfig.keyVault.secretName.adminPassword
    DataDiskSizeBytes = $labConfig.hciNode.dataDiskSizeBytes
    NetAdapter        = [PSCustomObject] @{
        Management = [PSCustomObject] @{
            Name               = $labConfig.hciNode.netAdapter.management.name
            VSwitchName        = $labConfig.labHost.vSwitch.nat.name
            IPAddress          = $labConfig.hciNode.netAdapter.management.ipAddress -f ($labConfig.hciNode.netAdapter.ipAddressOffset + $NodeIndex)
            PrefixLength       = $labConfig.hciNode.netAdapter.management.prefixLength
            DefaultGateway     = $labConfig.hciNode.netAdapter.management.defaultGateway
            DnsServerAddresses = $labConfig.hciNode.netAdapter.management.dnsServerAddresses
        }
        Compute = [PSCustomObject] @{
            Name         = $labConfig.hciNode.netAdapter.compute.name
            VSwitchName  = $labConfig.labHost.vSwitch.nat.name
            IPAddress    = $labConfig.hciNode.netAdapter.compute.ipAddress -f ($labConfig.hciNode.netAdapter.ipAddressOffset + $NodeIndex)
            PrefixLength = $labConfig.hciNode.netAdapter.compute.prefixLength
        }
        Storage1 = [PSCustomObject] @{
            Name         = $labConfig.hciNode.netAdapter.storage1.name
            VSwitchName  = $labConfig.labHost.vSwitch.nat.name
            IPAddress    = $labConfig.hciNode.netAdapter.storage1.ipAddress -f ($labConfig.hciNode.netAdapter.ipAddressOffset + $NodeIndex)
            PrefixLength = $labConfig.hciNode.netAdapter.storage1.prefixLength
            VlanId       = $labConfig.hciNode.netAdapter.storage1.vlanId
        }
        Storage2 = [PSCustomObject] @{
            Name         = $labConfig.hciNode.netAdapter.storage2.name
            VSwitchName  = $labConfig.labHost.vSwitch.nat.name
            IPAddress    = $labConfig.hciNode.netAdapter.storage2.ipAddress -f ($labConfig.hciNode.netAdapter.ipAddressOffset + $NodeIndex)
            PrefixLength = $labConfig.hciNode.netAdapter.storage2.prefixLength
            VlanId       = $labConfig.hciNode.netAdapter.storage2.vlanId
        }
    }
}
$nodeConfig | ConvertTo-Json -Depth 16 | Out-String | Write-ScriptLog -Context $vmName

'Creating the OS disk...' | Write-ScriptLog -Context $nodeConfig.VMName
$params = @{
    Path         = [IO.Path]::Combine($labConfig.labHost.folderPath.vm, $nodeConfig.VMName, 'osdisk.vhdx')
    Differencing = $true
    ParentPath   = $nodeConfig.ParentVhdPath
}
$vmOSDiskVhd = New-VHD @params

'Creating the VM...' | Write-ScriptLog -Context $nodeConfig.VMName
$params = @{
    Name       = $nodeConfig.VMName
    Path       = $labConfig.labHost.folderPath.vm
    VHDPath    = $vmOSDiskVhd.Path
    Generation = 2
}
New-VM @params | Out-String | Write-ScriptLog -Context $vmName

'Setting processor configuration...' | Write-ScriptLog -Context $nodeConfig.VMName
Set-VMProcessor -VMName $nodeConfig.VMName -Count 8 -ExposeVirtualizationExtensions $true

'Setting memory configuration...' | Write-ScriptLog -Context $nodeConfig.VMName
$params = @{
    VMName               = $nodeConfig.VMName
    StartupBytes         = $nodeConfig.RamBytes
    DynamicMemoryEnabled = $true
    MinimumBytes         = 512MB
    MaximumBytes         = $nodeConfig.RamBytes
}
Set-VMMemory @params

'Setting network adapter configuration...' | Write-ScriptLog -Context $nodeConfig.VMName
Get-VMNetworkAdapter -VMName $nodeConfig.VMName | Remove-VMNetworkAdapter

# Management
$paramsForAdd = @{
    VMName       = $nodeConfig.VMName
    Name         = $nodeConfig.NetAdapter.Management.Name
    SwitchName   = $nodeConfig.NetAdapter.Management.VSwitchName
    DeviceNaming = [Microsoft.HyperV.PowerShell.OnOffState]::On
    Passthru     = $true
}
$paramsForSet = @{
    MacAddressSpoofing = [Microsoft.HyperV.PowerShell.OnOffState]::On
    AllowTeaming       = [Microsoft.HyperV.PowerShell.OnOffState]::On
}
Add-VMNetworkAdapter @paramsForAdd |
Set-VMNetworkAdapter @paramsForSet

# Compute
$paramsForAdd = @{
    VMName       = $nodeConfig.VMName
    Name         = $nodeConfig.NetAdapter.Compute.Name
    SwitchName   = $nodeConfig.NetAdapter.Compute.VSwitchName
    DeviceNaming = [Microsoft.HyperV.PowerShell.OnOffState]::On
    Passthru     = $true
}
$paramsForSet = @{
    MacAddressSpoofing = [Microsoft.HyperV.PowerShell.OnOffState]::On
    AllowTeaming       = [Microsoft.HyperV.PowerShell.OnOffState]::On
}
Add-VMNetworkAdapter @paramsForAdd |
Set-VMNetworkAdapter @paramsForSet

# Storage 1
$paramsForAdd = @{
    VMName       = $nodeConfig.VMName
    Name         = $nodeConfig.NetAdapter.Storage1.Name
    SwitchName   = $nodeConfig.NetAdapter.Storage1.VSwitchName
    DeviceNaming = [Microsoft.HyperV.PowerShell.OnOffState]::On
    Passthru     = $true
}
$paramsForSet = @{
    AllowTeaming = [Microsoft.HyperV.PowerShell.OnOffState]::On
    Passthru     = $true
}
$paramsForVlan = @{
    Access = $true
    VlanId = $nodeConfig.NetAdapter.Storage1.VlanId
}
Add-VMNetworkAdapter @paramsForAdd |
Set-VMNetworkAdapter @paramsForSet |
Set-VMNetworkAdapterVlan @paramsForVlan

# Storage 2
$paramsForAdd = @{
    VMName       = $nodeConfig.VMName
    Name         = $nodeConfig.NetAdapter.Storage2.Name
    SwitchName   = $nodeConfig.NetAdapter.Storage2.VSwitchName
    DeviceNaming = [Microsoft.HyperV.PowerShell.OnOffState]::On
    Passthru     = $true
}
$paramsForSet = @{
    AllowTeaming = [Microsoft.HyperV.PowerShell.OnOffState]::On
    Passthru     = $true
}
$paramsForVlan = @{
    Access = $true
    VlanId = $nodeConfig.NetAdapter.Storage2.VlanId
}
Add-VMNetworkAdapter @paramsForAdd |
Set-VMNetworkAdapter @paramsForSet |
Set-VMNetworkAdapterVlan @paramsForVlan

'Creating the data disks...' | Write-ScriptLog -Context $nodeConfig.VMName
$diskCount = 6
for ($diskIndex = 1; $diskIndex -le $diskCount; $diskIndex++) {
    $params = @{
        Path      = [IO.Path]::Combine($labConfig.labHost.folderPath.vm, $nodeConfig.VMName, ('datadisk{0}.vhdx' -f $diskIndex))
        Dynamic   = $true
        SizeBytes = $nodeConfig.DataDiskSizeBytes
    }
    $vmDataDiskVhd = New-VHD @params
    Add-VMHardDiskDrive -VMName $nodeConfig.VMName -Path $vmDataDiskVhd.Path -Passthru | Out-String | Write-ScriptLog -Context $vmName
}

'Generating the unattend answer XML...' | Write-ScriptLog -Context $nodeConfig.VMName
$params = @{
    ComputerName = $nodeConfig.VMName
    Password     = $nodeConfig.AdminPassword
    Culture      = $labConfig.guestOS.culture
}
$unattendAnswerFileContent = New-UnattendAnswerFileContent @params

'Injecting the unattend answer file to the VHD...' | Write-ScriptLog -Context $nodeConfig.VMName
$params = @{
    VhdPath                   = $vmOSDiskVhd.Path
    UnattendAnswerFileContent = $unattendAnswerFileContent
    LogFolder                 = $labConfig.labHost.folderPath.log
}
Set-UnattendAnswerFileToVhd @params

'Installing the roles and features to the VHD...' | Write-ScriptLog -Context $nodeConfig.VMName
$params = @{
    VhdPath     = $vmOSDiskVhd.Path
    FeatureName = Get-WindowsFeatureToInstall -HciNodeOperatingSystemSku $labConfig.hciNode.operatingSystem.sku
    LogFolder   = $labConfig.labHost.folderPath.log
}
Install-WindowsFeatureToVhd @params

'Starting the VM...' | Write-ScriptLog -Context $nodeConfig.VMName
Start-VMWithRetry -VMName $nodeConfig.VMName

'Waiting for ready to the VM...' | Write-ScriptLog -Context $nodeConfig.VMName
$localAdminCredential = New-LogonCredential -DomainFqdn '.' -Password $nodeConfig.AdminPassword
Wait-PowerShellDirectReady -VMName $nodeConfig.VMName -Credential $localAdminCredential

'Create a PowerShell Direct session...' | Write-ScriptLog -Context $nodeConfig.VMName
$localAdminCredPSSession = New-PSSession -VMName $nodeConfig.VMName -Credential $localAdminCredential

'Copying the shared module file into the VM...' | Write-ScriptLog -Context $nodeConfig.VMName
$sharedModuleFilePath = (Get-Module -Name 'shared').Path
$sharedModuleFilePathInVM = [IO.Path]::Combine('C:\Windows\Temp', [IO.Path]::GetFileName($sharedModuleFilePath))
Copy-Item -ToSession $localAdminCredPSSession -Path $sharedModuleFilePath -Destination $sharedModuleFilePathInVM

'Setup the PowerShell Direct session...' | Write-ScriptLog -Context $nodeConfig.VMName
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
} #| Out-String | Write-ScriptLog -Context $nodeConfig.VMName

# If the HCI node OS is Windows Server 2022 with Desktop Experience.
if (($NodeConfig.OperatingSystem -eq $C_OperatingSystemSku.WindowsServer2022) -and ($NodeConfig.ImageIndex -eq 4)) {
    'Configuring registry values within the VM...' | Write-ScriptLog -Context $nodeConfig.VMName
    Invoke-Command -Session $localAdminCredPSSession -ScriptBlock {
        'Stop Server Manager launch at logon.' | Write-ScriptLog -Context $env:ComputerName -UseInScriptBlock
        Set-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\ServerManager' -Name 'DoNotOpenServerManagerAtLogon' -Value 1
    
        'Stop Windows Admin Center popup at Server Manager launch.' | Write-ScriptLog -Context $env:ComputerName -UseInScriptBlock
        Set-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\ServerManager' -Name 'DoNotPopWACConsoleAtSMLaunch' -Value 1
    
        'Hide the Network Location wizard. All networks will be Public.' | Write-ScriptLog -Context $env:ComputerName -UseInScriptBlock
        New-RegistryKey -ParentPath 'HKLM:\SYSTEM\CurrentControlSet\Control\Network' -KeyName 'NewNetworkWindowOff'

        'Setting to hide the first run experience of Microsoft Edge.' | Write-ScriptLog -Context $env:ComputerName -UseInScriptBlock
        New-RegistryKey -ParentPath 'HKLM:\SOFTWARE\Policies\Microsoft' -KeyName 'Edge'
        Set-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' -Name 'HideFirstRunExperience' -Value 1
    } | Out-String | Write-ScriptLog -Context $nodeConfig.VMName
}

'Configuring network settings within the VM...' | Write-ScriptLog -Context $nodeConfig.VMName
$params = @{
    InputObject = [PSCustomObject] @{
        VMConfig = $NodeConfig
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

    'Setting the IP configuration on the network adapters...' | Write-ScriptLog -Context $env:ComputerName -UseInScriptBlock

    # Management
    $params = @{
        AddressFamily  = 'IPv4'
        IPAddress      = $VMConfig.NetAdapter.Management.IPAddress
        PrefixLength   = $VMConfig.NetAdapter.Management.PrefixLength
        DefaultGateway = $VMConfig.NetAdapter.Management.DefaultGateway
    }
    Get-NetAdapter -Name $VMConfig.NetAdapter.Management.Name | New-NetIPAddress @params

    'Setting the DNS configuration on the {0} network adapter...' -f $VMConfig.NetAdapter.Management.Name | Write-ScriptLog -Context $env:ComputerName -UseInScriptBlock
    Get-NetAdapter -Name $VMConfig.NetAdapter.Management.Name |
        Set-DnsClientServerAddress -ServerAddresses $VMConfig.NetAdapter.Management.DnsServerAddresses

    # Compute
    $params = @{
        AddressFamily  = 'IPv4'
        IPAddress      = $VMConfig.NetAdapter.Compute.IPAddress
        PrefixLength   = $VMConfig.NetAdapter.Compute.PrefixLength
    }
    Get-NetAdapter -Name $VMConfig.NetAdapter.Compute.Name | New-NetIPAddress @params

    # Storage 1
    $params = @{
        AddressFamily = 'IPv4'
        IPAddress     = $VMConfig.NetAdapter.Storage1.IPAddress
        PrefixLength  = $VMConfig.NetAdapter.Storage1.PrefixLength
    }
    Get-NetAdapter -Name $VMConfig.NetAdapter.Storage1.Name | New-NetIPAddress @params

    # Storage 2
    $params = @{
        AddressFamily = 'IPv4'
        IPAddress     = $VMConfig.NetAdapter.Storage2.IPAddress
        PrefixLength  = $VMConfig.NetAdapter.Storage2.PrefixLength
    }
    Get-NetAdapter -Name $VMConfig.NetAdapter.Storage2.Name | New-NetIPAddress @params
} | Out-String | Write-ScriptLog -Context $nodeConfig.VMName

'Cleaning up the PowerShell Direct session...' | Write-ScriptLog -Context $nodeConfig.VMName
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
} | Out-String | Write-ScriptLog -Context $nodeConfig.VMName

$localAdminCredPSSession | Remove-PSSession

Wait-AddsDcDeploymentCompletion

'Waiting for ready to the domain controller...' | Write-ScriptLog -Context $nodeConfig.VMName
$domainAdminCredential = New-LogonCredential -DomainFqdn $labConfig.addsDomain.fqdn -Password $nodeConfig.AdminPassword
# The DC's computer name is the same as the VM name. It's specified in the unattend.xml.
$params = @{
    AddsDcVMName       = $labConfig.addsDC.vmName
    AddsDcComputerName = $labConfig.addsDC.vmName
    Credential         = $domainAdminCredential
}
Wait-DomainControllerServiceReady @params

'Joining the VM to the AD domain...'  | Write-ScriptLog -Context $nodeConfig.VMName
$params = @{
    VMName                = $nodeConfig.VMName
    LocalAdminCredential  = $localAdminCredential
    DomainFqdn            = $labConfig.addsDomain.fqdn
    DomainAdminCredential = $domainAdminCredential
}
Add-VMToADDomain @params

'Stopping the VM...' | Write-ScriptLog -Context $nodeConfig.VMName
Stop-VM -Name $nodeConfig.VMName

'Starting the VM...' | Write-ScriptLog -Context $nodeConfig.VMName
Start-VM -Name $nodeConfig.VMName

'Waiting for ready to the VM...' | Write-ScriptLog -Context $nodeConfig.VMName
$domainAdminCredential = New-LogonCredential -DomainFqdn $labConfig.addsDomain.fqdn -Password $nodeConfig.AdminPassword
Wait-PowerShellDirectReady -VMName $nodeConfig.VMName -Credential $domainAdminCredential

'The HCI node VM creation has been completed.' | Write-ScriptLog -Context $nodeConfig.VMName

Stop-ScriptLogging
