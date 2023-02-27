[CmdletBinding()]
param ()

$ErrorActionPreference = [Management.Automation.ActionPreference]::Stop
$WarningPreference = [Management.Automation.ActionPreference]::Continue
$VerbosePreference = [Management.Automation.ActionPreference]::Continue
$ProgressPreference = [Management.Automation.ActionPreference]::SilentlyContinue

Import-Module -Name '.\shared.psm1' -Force

$labConfig = GetConfigParameters
Start-ScriptTranscript -OutputDirectory $labConfig.labHost.folderPath.log -ScriptName $MyInvocation.MyCommand.Name
$labConfig | ConvertTo-Json -Depth 16

function CalculateHciNodeRamBytes
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [int] $NodeCount,

        [Parameter(Mandatory = $true)]
        [long] $LabHostReservedRamBytes,

        [Parameter(Mandatory = $true)]
        [string] $AddsDcVMName,

        [Parameter(Mandatory = $true)]
        [string] $WacVMName
    )

    $totalRamBytes = (Get-ComputerInfo).OsTotalVisibleMemorySize * 1KB
    $addsDcVMRamBytes = (Get-VM -Name $AddsDcVMName).MemoryMaximum
    $wacVMRamBytes = (Get-VM -Name $WacVMName).MemoryMaximum

    # StartupBytes should be a multiple of 2 MB (2 * 1024 * 1024 bytes).
    [Math]::Floor((($totalRamBytes - $LabHostReservedRamBytes - $addsDcVMRamBytes - $wacVMRamBytes) / $NodeCount) / 2MB) * 2MB
}

'Creating the HCI node VMs configuraton...' | WriteLog -Context $env:ComputerName

$parentVhdPath = [IO.Path]::Combine($labConfig.labHost.folderPath.vhd, (BuildBaseVhdFileName -OperatingSystem $labConfig.hciNode.operatingSystem.sku -ImageIndex $labConfig.hciNode.operatingSystem.imageIndex -Culture $labConfig.guestOS.culture))
$ramBytes = CalculateHciNodeRamBytes -NodeCount $labConfig.hciNode.nodeCount -LabHostReservedRamBytes $labConfig.labHost.reservedRamBytes -AddsDcVMName $labConfig.addsDC.vmName -WacVMName $labConfig.wac.vmName
$adminPassword = GetSecret -KeyVaultName $labConfig.keyVault.name -SecretName $labConfig.keyVault.secretName

$hciNodeConfigs = @()
for ($i = 0; $i -lt $labConfig.hciNode.nodeCount; $i++) {
    $hciNodeConfigs += @{
        VMName            = $labConfig.hciNode.vmName -f ($labConfig.hciNode.vmNameOffset + $i)
        ParentVhdPath     = $parentVhdPath
        RamBytes          = $ramBytes
        OperatingSystem   = $labConfig.hciNode.operatingSystem.sku
        ImageIndex        = $labConfig.hciNode.operatingSystem.imageIndex
        AdminPassword     = $adminPassword
        DataDiskSizeBytes = $labConfig.hciNode.dataDiskSizeBytes
        NetAdapter        = @{
            Management = @{
                Name               = $labConfig.hciNode.netAdapter.management.name
                VSwitchName        = $labConfig.labHost.vSwitch.nat.name
                IPAddress          = $labConfig.hciNode.netAdapter.management.ipAddress -f ($labConfig.hciNode.netAdapter.ipAddressOffset + $i)
                PrefixLength       = $labConfig.hciNode.netAdapter.management.prefixLength
                DefaultGateway     = $labConfig.hciNode.netAdapter.management.defaultGateway
                DnsServerAddresses = $labConfig.hciNode.netAdapter.management.dnsServerAddresses
            }
            Storage1 = @{
                Name         = $labConfig.hciNode.netAdapter.storage1.name
                VSwitchName  = $labConfig.labHost.vSwitch.nat.name
                IPAddress    = $labConfig.hciNode.netAdapter.storage1.ipAddress -f ($labConfig.hciNode.netAdapter.ipAddressOffset + $i)
                PrefixLength = $labConfig.hciNode.netAdapter.storage1.prefixLength
            }
            Storage2 = @{
                Name         = $labConfig.hciNode.netAdapter.storage2.name
                VSwitchName  = $labConfig.labHost.vSwitch.nat.name
                IPAddress    = $labConfig.hciNode.netAdapter.storage2.ipAddress -f ($labConfig.hciNode.netAdapter.ipAddressOffset + $i)
                PrefixLength = $labConfig.hciNode.netAdapter.storage2.prefixLength
            }
        }
    }
}
$hciNodeConfigs | ConvertTo-Json -Depth 16

foreach ($nodeConfig in $hciNodeConfigs) {
    'Creating the OS disk...' | WriteLog -Context $nodeConfig.VMName
    $params = @{
        Path         = [IO.Path]::Combine($labConfig.labHost.folderPath.vm, $nodeConfig.VMName, 'osdisk.vhdx')
        Differencing = $true
        ParentPath   = $nodeConfig.ParentVhdPath
    }
    $vmOSDiskVhd = New-VHD  @params

    'Creating the VM...' | WriteLog -Context $nodeConfig.VMName
    $params = @{
        Name       = $nodeConfig.VMName
        Path       = $labConfig.labHost.folderPath.vm
        VHDPath    = $vmOSDiskVhd.Path
        Generation = 2
    }
    New-VM @params
    
    'Setting processor configuration...' | WriteLog -Context $nodeConfig.VMName
    Set-VMProcessor -VMName $nodeConfig.VMName -Count 8 -ExposeVirtualizationExtensions $true

    'Setting memory configuration...' | WriteLog -Context $nodeConfig.VMName
    $params = @{
        VMName               = $nodeConfig.VMName
        StartupBytes         = $nodeConfig.RamBytes
        DynamicMemoryEnabled = $true
        MinimumBytes         = 512MB
        MaximumBytes         = $nodeConfig.RamBytes
    }
    Set-VMMemory @params
    
    'Setting network adapter configuration...' | WriteLog -Context $nodeConfig.VMName
    Get-VMNetworkAdapter -VMName $nodeConfig.VMName | Remove-VMNetworkAdapter

    # Management
    $params = @{
        VMName       = $nodeConfig.VMName
        Name         = $nodeConfig.NetAdapter.Management.Name
        SwitchName   = $nodeConfig.NetAdapter.Management.VSwitchName
        DeviceNaming = 'On'
    }
    Add-VMNetworkAdapter @params

    # Storage 1
    $params = @{
        VMName       = $nodeConfig.VMName
        Name         = $nodeConfig.NetAdapter.Storage1.Name
        SwitchName   = $nodeConfig.NetAdapter.Storage1.VSwitchName
        DeviceNaming = 'On'
    }
    Add-VMNetworkAdapter @params

    # Storage 2
    $params = @{
        VMName       = $nodeConfig.VMName
        Name         = $nodeConfig.NetAdapter.Storage2.Name
        SwitchName   = $nodeConfig.NetAdapter.Storage2.VSwitchName
        DeviceNaming = 'On'
    }
    Add-VMNetworkAdapter @params

    'Creating the data disks...' | WriteLog -Context $nodeConfig.VMName
    for ($diskIndex = 0; $diskIndex -lt 6; $diskIndex++) {
        $params = @{
            Path      = [IO.Path]::Combine($labConfig.labHost.folderPath.vm, $nodeConfig.VMName, ('datadisk{0}.vhdx' -f ($diskIndex + 1)))
            Dynamic   = $true
            SizeBytes = $nodeConfig.DataDiskSizeBytes
        }
        $vmDataDiskVhd = New-VHD @params
        Add-VMHardDiskDrive -VMName $nodeConfig.VMName -Path $vmDataDiskVhd.Path -Passthru
    }

    'Generating the unattend answer XML...' | WriteLog -Context $nodeConfig.VMName
    $unattendAnswerFileContent = GetUnattendAnswerFileContent -ComputerName $nodeConfig.VMName -Password $nodeConfig.AdminPassword -Culture $labConfig.guestOS.culture

    'Injecting the unattend answer file to the VHD...' | WriteLog -Context $nodeConfig.VMName
    InjectUnattendAnswerFile -VhdPath $vmOSDiskVhd.Path -UnattendAnswerFileContent $unattendAnswerFileContent

    'Installing the roles and features to the VHD...' | WriteLog -Context $nodeConfig.VMName
    $features = @(
        'Hyper-V',  # Note: https://twitter.com/pronichkin/status/1294308601276719104
        'Failover-Clustering',
        'FS-FileServer',
        'Data-Center-Bridging',  # Needs for WS2022 clsuter by WAC
        'RSAT-Hyper-V-Tools',
        'RSAT-Clustering',
        'RSAT-AD-PowerShell'  # Needs for WS2022 clsuter by WAC
    )
    Install-WindowsFeature -Vhd $vmOSDiskVhd.Path -Name $features

    'Starting the VM...' | WriteLog -Context $nodeConfig.VMName
    WaitingForStartingVM -VMName $nodeConfig.VMName
}

foreach ($nodeConfig in $hciNodeConfigs) {
    'Waiting for ready to the VM...' | WriteLog -Context $nodeConfig.VMName
    $params = @{
        TypeName     = 'System.Management.Automation.PSCredential'
        ArgumentList = 'Administrator', $nodeConfig.AdminPassword
    }
    $localAdminCredential = New-Object @params
    WaitingForReadyToVM -VMName $nodeConfig.VMName -Credential $localAdminCredential
}

foreach ($nodeConfig in $hciNodeConfigs) {
    'Configuring the VM...' | WriteLog -Context $nodeConfig.VMName

    $params = @{
        TypeName     = 'System.Management.Automation.PSCredential'
        ArgumentList = 'Administrator', $nodeConfig.AdminPassword
    }
    $localAdminCredential = New-Object @params

    $params = @{
        VMName       = $nodeConfig.VMName
        Credential   = $localAdminCredential
        ArgumentList = ${function:WriteLog}, $nodeConfig
    }
    Invoke-Command @params -ScriptBlock {
        $ErrorActionPreference = [Management.Automation.ActionPreference]::Stop
        $WarningPreference = [Management.Automation.ActionPreference]::Continue
        $VerbosePreference = [Management.Automation.ActionPreference]::Continue
        $ProgressPreference = [Management.Automation.ActionPreference]::SilentlyContinue
    
        $WriteLog = [scriptblock]::Create($args[0])
        $nodeConfig = $args[1]

        # If the HCI node OS is Windows Server 2022 with Desktop Experience.
        if (($nodeConfig.OperatingSystem -eq 'ws2022') -and ($nodeConfig.ImageIndex -eq 4)) {
            'Stop Server Manager launch at logon.' | &$WriteLog -Context $nodeConfig.VMName
            Set-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\ServerManager' -Name 'DoNotOpenServerManagerAtLogon' -Value 1
        
            'Stop Windows Admin Center popup at Server Manager launch.' | &$WriteLog -Context $nodeConfig.VMName
            Set-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\ServerManager' -Name 'DoNotPopWACConsoleAtSMLaunch' -Value 1
        
            'Hide the Network Location wizard. All networks will be Public.' | &$WriteLog -Context $nodeConfig.VMName
            New-Item -ItemType Directory -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Network' -Name 'NewNetworkWindowOff'
        }
    
        'Renaming the network adapters...' | &$WriteLog -Context $nodeConfig.VMName
        Get-NetAdapterAdvancedProperty -RegistryKeyword 'HyperVNetworkAdapterName' | ForEach-Object -Process {
            Rename-NetAdapter -Name $_.Name -NewName $_.DisplayValue
        }
    
        'Setting the IP configuration on the network adapter...' | &$WriteLog -Context $nodeConfig.VMName

        # Management
        $params = @{
            AddressFamily  = 'IPv4'
            IPAddress      = $nodeConfig.NetAdapter.Management.IPAddress
            PrefixLength   = $nodeConfig.NetAdapter.Management.PrefixLength
            DefaultGateway = $nodeConfig.NetAdapter.Management.DefaultGateway
        }
        Get-NetAdapter -Name $nodeConfig.NetAdapter.Management.Name | New-NetIPAddress @params

        'Setting the DNS configuration on the network adapter...' | &$WriteLog -Context $nodeConfig.VMName
        Get-NetAdapter -Name $nodeConfig.NetAdapter.Management.Name |
            Set-DnsClientServerAddress -ServerAddresses $nodeConfig.NetAdapter.Management.DnsServerAddresses
    
        # Storage 1
        $params = @{
            AddressFamily  = 'IPv4'
            IPAddress      = $nodeConfig.NetAdapter.Storage1.IPAddress
            PrefixLength   = $nodeConfig.NetAdapter.Storage1.PrefixLength
        }
        Get-NetAdapter -Name $nodeConfig.NetAdapter.Storage1.Name | New-NetIPAddress @params
    
        # Storage 2
        $params = @{
            AddressFamily  = 'IPv4'
            IPAddress      = $nodeConfig.NetAdapter.Storage2.IPAddress
            PrefixLength   = $nodeConfig.NetAdapter.Storage2.PrefixLength
        }
        Get-NetAdapter -Name $nodeConfig.NetAdapter.Storage2.Name | New-NetIPAddress @params
    }

    'Joining the VM the AD domain...' | WriteLog -Context $nodeConfig.VMName
    $domainAdminCredential = CreateDomainCredential -DomainFqdn $labConfig.addsDomain.fqdn -Password $nodeConfig.AdminPassword
    $params = @{
        VMName                = $nodeConfig.VMName
        LocalAdminCredential  = $localAdminCredential
        DomainFqdn            = $labConfig.addsDomain.fqdn
        DomainAdminCredential = $domainAdminCredential
    }
    JoinVMToADDomain @params
    
    'Stopping the VM...' | WriteLog -Context $nodeConfig.VMName
    Stop-VM -Name $nodeConfig.VMName
    
    'Starting the VM...' | WriteLog -Context $nodeConfig.VMName
    Start-VM -Name $nodeConfig.VMName
}

foreach ($nodeConfig in $hciNodeConfigs) {
    'Waiting for ready to the VM...' | WriteLog -Context $nodeConfig.VMName
    $domainAdminCredential = CreateDomainCredential -DomainFqdn $labConfig.addsDomain.fqdn -Password $nodeConfig.AdminPassword
    WaitingForReadyToVM -VMName $nodeConfig.VMName -Credential $domainAdminCredential
}

'The HCI node VMs creation has been completed.' | WriteLog -Context $env:ComputerName

Stop-ScriptTranscript
