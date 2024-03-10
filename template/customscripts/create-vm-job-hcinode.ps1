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

    'TotalRamBytes: {0}' -f $totalRamBytes | Write-ScriptLog
    'LabHostReservedRamBytes: {0}' -f $labHostReservedRamBytes | Write-ScriptLog
    'AddsDcVMRamBytes: {0}' -f $AddsDcVMRamBytes | Write-ScriptLog
    'WacVMRamBytes: {0}' -f $WacVMRamBytes | Write-ScriptLog

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
'Lab deployment config:' | Write-ScriptLog
$labConfig | ConvertTo-Json -Depth 16 | Out-String | Write-ScriptLog

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

'Create a VM configuraton for the HCI node VM.' -f $vmName | Write-ScriptLog -AdditionalContext $vmName
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
$nodeConfig | ConvertTo-Json -Depth 16 | Out-String | Write-ScriptLog -AdditionalContext $vmName
'Create a VM configuraton for the HCI node VM completed.' -f $vmName | Write-ScriptLog -AdditionalContext $vmName

# Hyper-V VM

'Create the OS disk.' | Write-ScriptLog -AdditionalContext $nodeConfig.VMName
$params = @{
    Path         = [IO.Path]::Combine($labConfig.labHost.folderPath.vm, $nodeConfig.VMName, 'osdisk.vhdx')
    Differencing = $true
    ParentPath   = $nodeConfig.ParentVhdPath
}
$vmOSDiskVhd = New-VHD @params
'Create the OS disk completed.' | Write-ScriptLog -AdditionalContext $nodeConfig.VMName

'Create the VM.' | Write-ScriptLog -AdditionalContext $nodeConfig.VMName
$params = @{
    Name       = $nodeConfig.VMName
    Path       = $labConfig.labHost.folderPath.vm
    VHDPath    = $vmOSDiskVhd.Path
    Generation = 2
}
New-VM @params | Out-String | Write-ScriptLog -AdditionalContext $vmName
'Create the VM completed.' | Write-ScriptLog -AdditionalContext $nodeConfig.VMName

'Change the VM''s automatic stop action.' | Write-ScriptLog -AdditionalContext $nodeConfig.VMName
Set-VM -Name $nodeConfig.VMName -AutomaticStopAction ShutDown
'Change the VM''s automatic stop action completed.' | Write-ScriptLog -AdditionalContext $nodeConfig.VMName

'Configure the VM''s processor.' | Write-ScriptLog -AdditionalContext $nodeConfig.VMName
$vmProcessorCount = (Get-VMHost).LogicalProcessorCount
Set-VMProcessor -VMName $nodeConfig.VMName -Count $vmProcessorCount -ExposeVirtualizationExtensions $true
'Configure the VM''s processor completed.' | Write-ScriptLog -AdditionalContext $nodeConfig.VMName

'Configure the VM''s memory.' | Write-ScriptLog -AdditionalContext $nodeConfig.VMName
$params = @{
    VMName               = $nodeConfig.VMName
    StartupBytes         = $nodeConfig.RamBytes
    DynamicMemoryEnabled = $true
    MinimumBytes         = 512MB
    MaximumBytes         = $nodeConfig.RamBytes
}
Set-VMMemory @params
'Configure the VM''s memory completed.' | Write-ScriptLog -AdditionalContext $nodeConfig.VMName

'Enable the VM''s vTPM.' | Write-ScriptLog -AdditionalContext $nodeConfig.VMName
$params = @{
    VMName               = $nodeConfig.VMName
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
    ) | Write-ScriptLog -Level Warning -AdditionalContext $nodeConfig.VMName

    # Rescue only once by retry.
    Set-VMKeyProtector @params | Enable-VMTPM
}
'Enable the VM''s vTPM completed.' | Write-ScriptLog -AdditionalContext $nodeConfig.VMName

'Configure the VM''s network adapters.' | Write-ScriptLog -AdditionalContext $nodeConfig.VMName
Get-VMNetworkAdapter -VMName $nodeConfig.VMName | Remove-VMNetworkAdapter

# Management
'Configure the {0} network adapter.' -f $nodeConfig.NetAdapters.Management.Name | Write-ScriptLog -AdditionalContext $nodeConfig.VMName
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
    Passthru           = $true
}
Add-VMNetworkAdapter @paramsForAdd |
Set-VMNetworkAdapter @paramsForSet |
Set-VMNetworkAdapterVlan -Trunk -NativeVlanId 0 -AllowedVlanIdList '1-4094'
'Configure the {0} network adapter completed.' -f $nodeConfig.NetAdapters.Management.Name | Write-ScriptLog -AdditionalContext $nodeConfig.VMName

# Compute
'Configure the {0} network adapter.' -f $nodeConfig.NetAdapters.Compute.Name | Write-ScriptLog -AdditionalContext $nodeConfig.VMName
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
    Passthru           = $true
}
Add-VMNetworkAdapter @paramsForAdd |
Set-VMNetworkAdapter @paramsForSet |
Set-VMNetworkAdapterVlan -Trunk -NativeVlanId 0 -AllowedVlanIdList '1-4094'
'Configure the {0} network adapter completed.' -f $nodeConfig.NetAdapters.Compute.Name | Write-ScriptLog -AdditionalContext $nodeConfig.VMName

# Storage 1
'Configure the {0} network adapter.' -f $nodeConfig.NetAdapters.Storage1.Name | Write-ScriptLog -AdditionalContext $nodeConfig.VMName
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
Add-VMNetworkAdapter @paramsForAdd |
Set-VMNetworkAdapter @paramsForSet |
Set-VMNetworkAdapterVlan -Trunk -NativeVlanId 0 -AllowedVlanIdList '1-4094'
'Configure the {0} network adapter completed.' -f $nodeConfig.NetAdapters.Storage1.Name | Write-ScriptLog -AdditionalContext $nodeConfig.VMName

# Storage 2
'Configure the {0} network adapter.' -f $nodeConfig.NetAdapters.Storage2.Name | Write-ScriptLog -AdditionalContext $nodeConfig.VMName
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
Add-VMNetworkAdapter @paramsForAdd |
Set-VMNetworkAdapter @paramsForSet |
Set-VMNetworkAdapterVlan -Trunk -NativeVlanId 0 -AllowedVlanIdList '1-4094'
'Configure the {0} network adapter completed.' -f $nodeConfig.NetAdapters.Storage2.Name | Write-ScriptLog -AdditionalContext $nodeConfig.VMName

'Create the data disks.' | Write-ScriptLog -AdditionalContext $nodeConfig.VMName
$diskCount = 8
for ($diskIndex = 1; $diskIndex -le $diskCount; $diskIndex++) {
    $params = @{
        Path      = [IO.Path]::Combine($labConfig.labHost.folderPath.vm, $nodeConfig.VMName, ('datadisk{0}.vhdx' -f $diskIndex))
        Dynamic   = $true
        SizeBytes = $nodeConfig.DataDiskSizeBytes
    }
    $vmDataDiskVhd = New-VHD @params
    Add-VMHardDiskDrive -VMName $nodeConfig.VMName -Path $vmDataDiskVhd.Path -Passthru | Out-String | Write-ScriptLog -AdditionalContext $vmName
}
'Create the data disks completed.' | Write-ScriptLog -AdditionalContext $nodeConfig.VMName

'Generate the unattend answer XML.'| Write-ScriptLog -AdditionalContext $nodeConfig.VMName
$params = @{
    ComputerName = $nodeConfig.VMName
    Password     = $nodeConfig.AdminPassword
    Culture      = $labConfig.guestOS.culture
    TimeZone     = $labConfig.guestOS.timeZone
}
$unattendAnswerFileContent = New-UnattendAnswerFileContent @params
'Generate the unattend answer XML completed.'| Write-ScriptLog -AdditionalContext $nodeConfig.VMName

'Inject the unattend answer file to the VHD.' | Write-ScriptLog -AdditionalContext $nodeConfig.VMName
$params = @{
    VhdPath                   = $vmOSDiskVhd.Path
    UnattendAnswerFileContent = $unattendAnswerFileContent
    LogFolder                 = $labConfig.labHost.folderPath.log
}
Set-UnattendAnswerFileToVhd @params
'Inject the unattend answer file to the VHD completed.' | Write-ScriptLog -AdditionalContext $nodeConfig.VMName

'Install the roles and features to the VHD.' | Write-ScriptLog -AdditionalContext $nodeConfig.VMName
$params = @{
    VhdPath     = $vmOSDiskVhd.Path
    FeatureName = Get-WindowsFeatureToInstall -HciNodeOperatingSystemSku $labConfig.hciNode.operatingSystem.sku
    LogFolder   = $labConfig.labHost.folderPath.log
}
Install-WindowsFeatureToVhd @params
'Install the roles and features to the VHD completed' | Write-ScriptLog -AdditionalContext $nodeConfig.VMName

'Start the VM.' | Write-ScriptLog -AdditionalContext $nodeConfig.VMName
Start-VMWithRetry -VMName $nodeConfig.VMName
'Start the VM completed.' | Write-ScriptLog -AdditionalContext $nodeConfig.VMName

'Wait for the VM to be ready.' | Write-ScriptLog -AdditionalContext $nodeConfig.VMName
$localAdminCredential = New-LogonCredential -DomainFqdn '.' -Password $nodeConfig.AdminPassword
Wait-PowerShellDirectReady -VMName $nodeConfig.VMName -Credential $localAdminCredential
'The VM is ready.' | Write-ScriptLog -AdditionalContext $nodeConfig.VMName

# Guest OS

'Create a PowerShell Direct session.' | Write-ScriptLog -AdditionalContext $nodeConfig.VMName
$localAdminCredPSSession = New-PSSession -VMName $nodeConfig.VMName -Credential $localAdminCredential
$localAdminCredPSSession | Format-Table -Property 'Id', 'Name', 'ComputerName', 'ComputerType', 'State', 'Availability' | Out-String | Write-ScriptLog
'Create a PowerShell Direct session completed.' | Write-ScriptLog -AdditionalContext $nodeConfig.VMName

'Copy the common module file into the VM.' | Write-ScriptLog -AdditionalContext $nodeConfig.VMName
$commonModuleFilePathInVM = Copy-PSModuleIntoVM -Session $localAdminCredPSSession -ModuleFilePathToCopy (Get-Module -Name 'common').Path
'Copy the common module file into the VM completed.' | Write-ScriptLog -AdditionalContext $nodeConfig.VMName

'Setup the PowerShell Direct session.' | Write-ScriptLog -AdditionalContext $nodeConfig.VMName
Invoke-PSDirectSessionSetup -Session $localAdminCredPSSession -CommonModuleFilePathInVM $commonModuleFilePathInVM
'Setup the PowerShell Direct session completed.' | Write-ScriptLog -AdditionalContext $nodeConfig.VMName

# If the HCI node OS is Windows Server 2022 with Desktop Experience.
if (($NodeConfig.OperatingSystem -eq [HciLab.OSSku]::WindowsServer2022) -and ($NodeConfig.ImageIndex -eq [HciLab.OSImageIndex]::WSDatacenterDesktopExperience)) {
    'Configure registry values within the VM.' | Write-ScriptLog -AdditionalContext $nodeConfig.VMName
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

        'Hide the first run experience of Microsoft Edge.' | Write-ScriptLog
        New-RegistryKey -ParentPath 'HKLM:\SOFTWARE\Policies\Microsoft' -KeyName 'Edge'
        Set-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' -Name 'HideFirstRunExperience' -Value 1
        'Hide the first run experience of Microsoft Edge completed.' | Write-ScriptLog
    } | Out-String | Write-ScriptLog -AdditionalContext $nodeConfig.VMName
}
'Configure registry values within the VM completed.' | Write-ScriptLog -AdditionalContext $nodeConfig.VMName

'Configure network settings within the VM.' | Write-ScriptLog -AdditionalContext $nodeConfig.VMName
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

    'Rename the network adapters.' | Write-ScriptLog
    Get-NetAdapterAdvancedProperty -RegistryKeyword 'HyperVNetworkAdapterName' | ForEach-Object -Process {
        Rename-NetAdapter -Name $_.Name -NewName $_.DisplayValue
    }
    'Rename the network adapters completed.' | Write-ScriptLog

    # Management
    'Configure the IP & DNS on the {0} network adapter.' -f $VMConfig.NetAdapters.Management.Name | Write-ScriptLog
    $paramsForSetNetIPInterface = @{
        AddressFamily = 'IPv4'
        Dhcp          = 'Disabled'
        PassThru      = $true
    }
    $paramsForNewIPAddress = @{
        AddressFamily  = 'IPv4'
        IPAddress      = $VMConfig.NetAdapters.Management.IPAddress
        PrefixLength   = $VMConfig.NetAdapters.Management.PrefixLength
        DefaultGateway = $VMConfig.NetAdapters.Management.DefaultGateway
    }
    $paramsForSetDnsClientServerAddress = @{
        ServerAddresses = $VMConfig.netAdapters.management.dnsServerAddresses
    }
    Get-NetAdapter -Name $VMConfig.NetAdapters.Management.Name |
    Set-NetIPInterface @paramsForSetNetIPInterface |
    New-NetIPAddress @paramsForNewIPAddress |
    Set-DnsClientServerAddress @paramsForSetDnsClientServerAddress
    'Configure the IP & DNS on the {0} network adapter completed.' -f $VMConfig.NetAdapters.Management.Name | Write-ScriptLog

    # Compute
    'Configure the IP & DNS on the {0} network adapter.' -f $VMConfig.NetAdapters.Compute.Name | Write-ScriptLog
    $paramsForSetNetIPInterface = @{
        AddressFamily = 'IPv4'
        Dhcp          = 'Disabled'
        PassThru      = $true
    }
    $paramsForNewIPAddress = @{
        AddressFamily  = 'IPv4'
        IPAddress      = $VMConfig.NetAdapters.Compute.IPAddress
        PrefixLength   = $VMConfig.NetAdapters.Compute.PrefixLength
    }
    Get-NetAdapter -Name $VMConfig.NetAdapters.Compute.Name |
    Set-NetIPInterface @paramsForSetNetIPInterface |
    New-NetIPAddress @paramsForNewIPAddress
    'Configure the IP & DNS on the {0} network adapter completed.' -f $VMConfig.NetAdapters.Compute.Name | Write-ScriptLog

    # Storage 1
    'Configure the IP & DNS on the {0} network adapter.' -f $VMConfig.NetAdapters.Storage1.Name | Write-ScriptLog
    $paramsForSetNetAdapter = @{
        VlanID   = $VMConfig.NetAdapters.Storage1.VlanId
        Confirm  = $false
        PassThru = $true
    }
    $paramsForSetNetIPInterface = @{
        AddressFamily = 'IPv4'
        Dhcp          = 'Disabled'
        PassThru      = $true
    }
    $paramsForNewIPAddress = @{
        AddressFamily = 'IPv4'
        IPAddress     = $VMConfig.NetAdapters.Storage1.IPAddress
        PrefixLength  = $VMConfig.NetAdapters.Storage1.PrefixLength
    }
    Get-NetAdapter -Name $VMConfig.NetAdapters.Storage1.Name |
    Set-NetAdapter @paramsForSetNetAdapter |
    Set-NetIPInterface @paramsForSetNetIPInterface |
    New-NetIPAddress @paramsForNewIPAddress
    'Configure the IP & DNS on the {0} network adapter completed.' -f $VMConfig.NetAdapters.Storage1.Name | Write-ScriptLog

    # Storage 2
    'Configure the IP & DNS on the {0} network adapter.' -f $VMConfig.NetAdapters.Storage2.Name | Write-ScriptLog
    $paramsForSetNetAdapter = @{
        VlanID   = $VMConfig.NetAdapters.Storage2.VlanId
        Confirm  = $false
        PassThru = $true
    }
    $paramsForSetNetIPInterface = @{
        AddressFamily = 'IPv4'
        Dhcp          = 'Disabled'
        PassThru      = $true
    }
    $paramsForNewIPAddress = @{
        AddressFamily = 'IPv4'
        IPAddress     = $VMConfig.NetAdapters.Storage2.IPAddress
        PrefixLength  = $VMConfig.NetAdapters.Storage2.PrefixLength
    }
    Get-NetAdapter -Name $VMConfig.NetAdapters.Storage2.Name |
    Set-NetAdapter @paramsForSetNetAdapter |
    Set-NetIPInterface @paramsForSetNetIPInterface |
    New-NetIPAddress @paramsForNewIPAddress
    'Configure the IP & DNS on the {0} network adapter completed.' -f $VMConfig.NetAdapters.Storage2.Name | Write-ScriptLog
} | Out-String | Write-ScriptLog -AdditionalContext $nodeConfig.VMName

'Clean up the PowerShell Direct session.' | Write-ScriptLog -AdditionalContext $nodeConfig.VMName
Invoke-PSDirectSessionCleanup -Session $localAdminCredPSSession -CommonModuleFilePathInVM $commonModuleFilePathInVM
'Clean up the PowerShell Direct session completed.' | Write-ScriptLog -AdditionalContext $nodeConfig.VMName

if ($labConfig.hciNode.shouldJoinToAddsDomain) {
    'Wait for the domain controller to complete deployment.' | Write-ScriptLog -AdditionalContext $nodeConfig.VMName
    Wait-AddsDcDeploymentCompletion
    'The domain controller deployment completed.' | Write-ScriptLog -AdditionalContext $nodeConfig.VMName

    'Wait for the domain controller to be ready.' | Write-ScriptLog -AdditionalContext $nodeConfig.VMName
    $domainAdminCredential = New-LogonCredential -DomainFqdn $labConfig.addsDomain.fqdn -Password $nodeConfig.AdminPassword
    # The DC's computer name is the same as the VM name. It's specified in the unattend.xml.
    $params = @{
        AddsDcVMName       = $labConfig.addsDC.vmName
        AddsDcComputerName = $labConfig.addsDC.vmName
        Credential         = $domainAdminCredential
    }
    Wait-DomainControllerServiceReady @params
    'The domain controller is ready.' | Write-ScriptLog -AdditionalContext $nodeConfig.VMName
    
    'Join the VM to the AD domain.'  | Write-ScriptLog -AdditionalContext $nodeConfig.VMName
    $params = @{
        VMName                = $nodeConfig.VMName
        LocalAdminCredential  = $localAdminCredential
        DomainFqdn            = $labConfig.addsDomain.fqdn
        DomainAdminCredential = $domainAdminCredential
    }
    Add-VMToADDomain @params
    'Join the VM to the AD domain completed.'  | Write-ScriptLog -AdditionalContext $nodeConfig.VMName
}

'Stop the VM.' | Write-ScriptLog -AdditionalContext $nodeConfig.VMName
Stop-VM -Name $nodeConfig.VMName
'Stop the VM completed.' | Write-ScriptLog -AdditionalContext $nodeConfig.VMName

'Start the VM.' | Write-ScriptLog -AdditionalContext $nodeConfig.VMName
Start-VM -Name $nodeConfig.VMName
'Start the VM completed.' | Write-ScriptLog -AdditionalContext $nodeConfig.VMName

'Wait for the VM to be ready.' | Write-ScriptLog -AdditionalContext $nodeConfig.VMName
$credentialForWaiting = if ($labConfig.hciNode.shouldJoinToAddsDomain) {
    New-LogonCredential -DomainFqdn $labConfig.addsDomain.fqdn -Password $nodeConfig.AdminPassword
}
else {
    $localAdminCredential
}
Wait-PowerShellDirectReady -VMName $nodeConfig.VMName -Credential $credentialForWaiting
'The VM is ready.' | Write-ScriptLog -AdditionalContext $nodeConfig.VMName

'The HCI node VM creation has been completed.' | Write-ScriptLog -AdditionalContext $nodeConfig.VMName
Stop-ScriptLogging
