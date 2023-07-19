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
        'Data-Center-Bridging',
        'RSAT-AD-PowerShell',
        'Hyper-V-PowerShell',
        'RSAT-Clustering-PowerShell'  # This is need for administration from Cluster Manager in Windows Admin Center.
    )
    if ([HciLab.OSSku]::AzureStackHciSkus -contains $HciNodeOperatingSystemSku) {
        $featureNames += 'FS-Data-Deduplication'
        $featureNames += 'BitLocker'
    
        if ($HciNodeOperatingSystemSku -ne [HciLab.OSSku]::AzureStackHci20H2) {
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
    NetAdapters       = [PSCustomObject] @{
        Management = [PSCustomObject] @{
            Name               = $labConfig.hciNode.netAdapters.management.name
            VSwitchName        = $labConfig.labHost.vSwitch.nat.name
            IPAddress          = $labConfig.hciNode.netAdapters.management.ipAddress -f ($labConfig.hciNode.ipAddressOffset + $NodeIndex)
            PrefixLength       = $labConfig.hciNode.netAdapters.management.prefixLength
            DefaultGateway     = $labConfig.hciNode.netAdapters.management.defaultGateway
            DnsServerAddresses = $labConfig.hciNode.netAdapters.management.dnsServerAddresses
        }
        Compute = [PSCustomObject] @{
            Name         = $labConfig.hciNode.netAdapters.compute.name
            VSwitchName  = $labConfig.labHost.vSwitch.nat.name
            IPAddress    = $labConfig.hciNode.netAdapters.compute.ipAddress -f ($labConfig.hciNode.ipAddressOffset + $NodeIndex)
            PrefixLength = $labConfig.hciNode.netAdapters.compute.prefixLength
        }
        Storage1 = [PSCustomObject] @{
            Name         = $labConfig.hciNode.netAdapters.storage1.name
            VSwitchName  = $labConfig.labHost.vSwitch.nat.name
            IPAddress    = $labConfig.hciNode.netAdapters.storage1.ipAddress -f ($labConfig.hciNode.ipAddressOffset + $NodeIndex)
            PrefixLength = $labConfig.hciNode.netAdapters.storage1.prefixLength
            VlanId       = $labConfig.hciNode.netAdapters.storage1.vlanId
        }
        Storage2 = [PSCustomObject] @{
            Name         = $labConfig.hciNode.netAdapters.storage2.name
            VSwitchName  = $labConfig.labHost.vSwitch.nat.name
            IPAddress    = $labConfig.hciNode.netAdapters.storage2.ipAddress -f ($labConfig.hciNode.ipAddressOffset + $NodeIndex)
            PrefixLength = $labConfig.hciNode.netAdapters.storage2.prefixLength
            VlanId       = $labConfig.hciNode.netAdapters.storage2.vlanId
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

'Changing the VM''s automatic stop action...' | Write-ScriptLog -Context $nodeConfig.VMName
Set-VM -Name $nodeConfig.VMName -AutomaticStopAction ShutDown

'Setting processor configuration...' | Write-ScriptLog -Context $nodeConfig.VMName
$vmProcessorCount = (Get-VMHost).LogicalProcessorCount
Set-VMProcessor -VMName $nodeConfig.VMName -Count $vmProcessorCount -ExposeVirtualizationExtensions $true

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
    Name         = $nodeConfig.NetAdapters.Management.Name
    SwitchName   = $nodeConfig.NetAdapters.Management.VSwitchName
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
    Name         = $nodeConfig.NetAdapters.Compute.Name
    SwitchName   = $nodeConfig.NetAdapters.Compute.VSwitchName
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
    Name         = $nodeConfig.NetAdapters.Storage1.Name
    SwitchName   = $nodeConfig.NetAdapters.Storage1.VSwitchName
    DeviceNaming = [Microsoft.HyperV.PowerShell.OnOffState]::On
    Passthru     = $true
}
$paramsForSet = @{
    AllowTeaming = [Microsoft.HyperV.PowerShell.OnOffState]::On
    Passthru     = $true
}
$paramsForVlan = @{
    Access = $true
    VlanId = $nodeConfig.NetAdapters.Storage1.VlanId
}
Add-VMNetworkAdapter @paramsForAdd |
Set-VMNetworkAdapter @paramsForSet |
Set-VMNetworkAdapterVlan @paramsForVlan

# Storage 2
$paramsForAdd = @{
    VMName       = $nodeConfig.VMName
    Name         = $nodeConfig.NetAdapters.Storage2.Name
    SwitchName   = $nodeConfig.NetAdapters.Storage2.VSwitchName
    DeviceNaming = [Microsoft.HyperV.PowerShell.OnOffState]::On
    Passthru     = $true
}
$paramsForSet = @{
    AllowTeaming = [Microsoft.HyperV.PowerShell.OnOffState]::On
    Passthru     = $true
}
$paramsForVlan = @{
    Access = $true
    VlanId = $nodeConfig.NetAdapters.Storage2.VlanId
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
    TimeZone     = $labConfig.guestOS.timeZone
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
$localAdminCredPSSession |
    Format-Table -Property 'Id', 'Name', 'ComputerName', 'ComputerType', 'State', 'Availability' |
    Out-String |
    Write-ScriptLog -Context $env:ComputerName

'Copying the common module file into the VM...' | Write-ScriptLog -Context $nodeConfig.VMName
$commonModuleFilePathInVM = Copy-PSModuleIntoVM -Session $localAdminCredPSSession -ModuleFilePathToCopy (Get-Module -Name 'common').Path

'Setup the PowerShell Direct session...' | Write-ScriptLog -Context $nodeConfig.VMName
Invoke-PSDirectSessionSetup -Session $localAdminCredPSSession -CommonModuleFilePathInVM $commonModuleFilePathInVM

# If the HCI node OS is Windows Server 2022 with Desktop Experience.
if (($NodeConfig.OperatingSystem -eq [HciLab.OSSku]::WindowsServer2022) -and ($NodeConfig.ImageIndex -eq [HciLab.OSImageIndex]::WSDatacenterDesktopExperience)) {
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
        IPAddress      = $VMConfig.NetAdapters.Management.IPAddress
        PrefixLength   = $VMConfig.NetAdapters.Management.PrefixLength
        DefaultGateway = $VMConfig.NetAdapters.Management.DefaultGateway
    }
    Get-NetAdapter -Name $VMConfig.NetAdapters.Management.Name | New-NetIPAddress @params

    'Setting the DNS configuration on the {0} network adapter...' -f $VMConfig.NetAdapters.Management.Name | Write-ScriptLog -Context $env:ComputerName -UseInScriptBlock
    Get-NetAdapter -Name $VMConfig.NetAdapters.Management.Name |
        Set-DnsClientServerAddress -ServerAddresses $VMConfig.NetAdapters.Management.DnsServerAddresses

    # Compute
    $params = @{
        AddressFamily  = 'IPv4'
        IPAddress      = $VMConfig.NetAdapters.Compute.IPAddress
        PrefixLength   = $VMConfig.NetAdapters.Compute.PrefixLength
    }
    Get-NetAdapter -Name $VMConfig.NetAdapters.Compute.Name | New-NetIPAddress @params

    # Storage 1
    $params = @{
        AddressFamily = 'IPv4'
        IPAddress     = $VMConfig.NetAdapters.Storage1.IPAddress
        PrefixLength  = $VMConfig.NetAdapters.Storage1.PrefixLength
    }
    Get-NetAdapter -Name $VMConfig.NetAdapters.Storage1.Name | New-NetIPAddress @params

    # Storage 2
    $params = @{
        AddressFamily = 'IPv4'
        IPAddress     = $VMConfig.NetAdapters.Storage2.IPAddress
        PrefixLength  = $VMConfig.NetAdapters.Storage2.PrefixLength
    }
    Get-NetAdapter -Name $VMConfig.NetAdapters.Storage2.Name | New-NetIPAddress @params
} | Out-String | Write-ScriptLog -Context $nodeConfig.VMName

'Cleaning up the PowerShell Direct session...' | Write-ScriptLog -Context $nodeConfig.VMName
Invoke-PSDirectSessionCleanup -Session $localAdminCredPSSession -CommonModuleFilePathInVM $commonModuleFilePathInVM


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
