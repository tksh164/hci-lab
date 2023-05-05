[CmdletBinding()]
param ()

$ErrorActionPreference = [Management.Automation.ActionPreference]::Stop
$WarningPreference = [Management.Automation.ActionPreference]::Continue
$VerbosePreference = [Management.Automation.ActionPreference]::Continue
$ProgressPreference = [Management.Automation.ActionPreference]::SilentlyContinue

Import-Module -Name ([IO.Path]::Combine($PSScriptRoot, 'shared.psm1')) -Force

$labConfig = Get-LabDeploymentConfig
Start-ScriptLogging -OutputDirectory $labConfig.labHost.folderPath.log
$labConfig | ConvertTo-Json -Depth 16

function CalculateHciNodeRamBytes
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [int] $NodeCount,

        [Parameter(Mandatory = $true)]
        [string] $AddsDcVMName,

        [Parameter(Mandatory = $true)]
        [string] $WacVMName
    )

    $totalRamBytes = (Get-ComputerInfo).OsTotalVisibleMemorySize * 1KB
    $labHostReservedRamBytes = [Math]::Floor($totalRamBytes * 0.04)  # Reserve a few percent of the total RAM for the lab host.
    $addsDcVMRamBytes = (Get-VM -Name $AddsDcVMName).MemoryMaximum
    $wacVMRamBytes = (Get-VM -Name $WacVMName).MemoryMaximum

    'totalRamBytes: {0}' -f $totalRamBytes | Write-ScriptLog -Context $env:ComputerName
    'labHostReservedRamBytes: {0}' -f $labHostReservedRamBytes | Write-ScriptLog -Context $env:ComputerName
    'addsDcVMRamBytes: {0}' -f $addsDcVMRamBytes | Write-ScriptLog -Context $env:ComputerName
    'wacVMRamBytes: {0}' -f $wacVMRamBytes | Write-ScriptLog -Context $env:ComputerName

    # StartupBytes should be a multiple of 2 MB (2 * 1024 * 1024 bytes).
    [Math]::Floor((($totalRamBytes - $labHostReservedRamBytes - $addsDcVMRamBytes - $wacVMRamBytes) / $NodeCount) / 2MB) * 2MB
}

'Creating the HCI node VMs configuraton...' | Write-ScriptLog -Context $env:ComputerName

$parentVhdPath = [IO.Path]::Combine($labConfig.labHost.folderPath.vhd, (GetBaseVhdFileName -OperatingSystem $labConfig.hciNode.operatingSystem.sku -ImageIndex $labConfig.hciNode.operatingSystem.imageIndex -Culture $labConfig.guestOS.culture))
$ramBytes = CalculateHciNodeRamBytes -NodeCount $labConfig.hciNode.nodeCount -AddsDcVMName $labConfig.addsDC.vmName -WacVMName $labConfig.wac.vmName
$adminPassword = GetSecret -KeyVaultName $labConfig.keyVault.name -SecretName $labConfig.keyVault.secretName

$hciNodeConfigs = @()
for ($i = 0; $i -lt $labConfig.hciNode.nodeCount; $i++) {
    $hciNodeConfigs += [PSCustomObject] @{
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
    'Creating the OS disk...' | Write-ScriptLog -Context $nodeConfig.VMName
    $params = @{
        Path         = [IO.Path]::Combine($labConfig.labHost.folderPath.vm, $nodeConfig.VMName, 'osdisk.vhdx')
        Differencing = $true
        ParentPath   = $nodeConfig.ParentVhdPath
    }
    $vmOSDiskVhd = New-VHD  @params

    'Creating the VM...' | Write-ScriptLog -Context $nodeConfig.VMName
    $params = @{
        Name       = $nodeConfig.VMName
        Path       = $labConfig.labHost.folderPath.vm
        VHDPath    = $vmOSDiskVhd.Path
        Generation = 2
    }
    New-VM @params
    
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

    'Creating the data disks...' | Write-ScriptLog -Context $nodeConfig.VMName
    for ($diskIndex = 0; $diskIndex -lt 6; $diskIndex++) {
        $params = @{
            Path      = [IO.Path]::Combine($labConfig.labHost.folderPath.vm, $nodeConfig.VMName, ('datadisk{0}.vhdx' -f ($diskIndex + 1)))
            Dynamic   = $true
            SizeBytes = $nodeConfig.DataDiskSizeBytes
        }
        $vmDataDiskVhd = New-VHD @params
        Add-VMHardDiskDrive -VMName $nodeConfig.VMName -Path $vmDataDiskVhd.Path -Passthru
    }

    'Generating the unattend answer XML...' | Write-ScriptLog -Context $nodeConfig.VMName
    $unattendAnswerFileContent = GetUnattendAnswerFileContent -ComputerName $nodeConfig.VMName -Password $nodeConfig.AdminPassword -Culture $labConfig.guestOS.culture

    'Injecting the unattend answer file to the VHD...' | Write-ScriptLog -Context $nodeConfig.VMName
    InjectUnattendAnswerFile -VhdPath $vmOSDiskVhd.Path -UnattendAnswerFileContent $unattendAnswerFileContent -LogFolder $labConfig.labHost.folderPath.log

    'Installing the roles and features to the VHD...' | Write-ScriptLog -Context $nodeConfig.VMName
    $features = @(
        'Hyper-V',  # Note: https://twitter.com/pronichkin/status/1294308601276719104
        'Failover-Clustering',
        'FS-FileServer',
        'Data-Center-Bridging',  # Needs for WS2022 clsuter by WAC
        'RSAT-Hyper-V-Tools',
        'RSAT-Clustering',
        'RSAT-AD-PowerShell'  # Needs for WS2022 clsuter by WAC
    )
    Install-WindowsFeatureToVhd -VhdPath $vmOSDiskVhd.Path -FeatureName $features -LogFolder $labConfig.labHost.folderPath.log

    'Starting the VM...' | Write-ScriptLog -Context $nodeConfig.VMName
    WaitingForStartingVM -VMName $nodeConfig.VMName
}

foreach ($nodeConfig in $hciNodeConfigs) {
    'Waiting for ready to the VM...' | Write-ScriptLog -Context $nodeConfig.VMName
    $params = @{
        TypeName     = 'System.Management.Automation.PSCredential'
        ArgumentList = 'Administrator', $nodeConfig.AdminPassword
    }
    $localAdminCredential = New-Object @params
    WaitingForReadyToVM -VMName $nodeConfig.VMName -Credential $localAdminCredential
}

foreach ($nodeConfig in $hciNodeConfigs) {
    'Configuring the VM...' | Write-ScriptLog -Context $nodeConfig.VMName

    $params = @{
        TypeName     = 'System.Management.Automation.PSCredential'
        ArgumentList = 'Administrator', $nodeConfig.AdminPassword
    }
    $localAdminCredential = New-Object @params

    $params = @{
        VMName      = $nodeConfig.VMName
        Credential  = $localAdminCredential
        InputObject = [PSCustomObject] @{
            NodeConfig             = $nodeConfig
            WriteLogImplementation = (${function:Write-ScriptLog}).ToString()
        }
    }
    Invoke-Command @params -ScriptBlock {
        param (
            [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
            [PSCustomObject] $NodeConfig,
    
            [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
            [string] $WriteLogImplementation
        )

        $ErrorActionPreference = [Management.Automation.ActionPreference]::Stop
        $WarningPreference = [Management.Automation.ActionPreference]::Continue
        $VerbosePreference = [Management.Automation.ActionPreference]::Continue
        $ProgressPreference = [Management.Automation.ActionPreference]::SilentlyContinue
    
        New-Item -Path 'function:' -Name 'Write-ScriptLog' -Value $WriteLogImplementation -Force | Out-Null

        # If the HCI node OS is Windows Server 2022 with Desktop Experience.
        if (($NodeConfig.OperatingSystem -eq 'ws2022') -and ($NodeConfig.ImageIndex -eq 4)) {
            'Stop Server Manager launch at logon.' | Write-ScriptLog -Context $NodeConfig.VMName -UseInScriptBlock
            Set-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\ServerManager' -Name 'DoNotOpenServerManagerAtLogon' -Value 1
        
            'Stop Windows Admin Center popup at Server Manager launch.' | Write-ScriptLog -Context $NodeConfig.VMName -UseInScriptBlock
            Set-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\ServerManager' -Name 'DoNotPopWACConsoleAtSMLaunch' -Value 1
        
            'Hide the Network Location wizard. All networks will be Public.' | Write-ScriptLog -Context $NodeConfig.VMName -UseInScriptBlock
            New-Item -ItemType Directory -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Network' -Name 'NewNetworkWindowOff'
        }
    
        'Renaming the network adapters...' | Write-ScriptLog -Context $NodeConfig.VMName -UseInScriptBlock
        Get-NetAdapterAdvancedProperty -RegistryKeyword 'HyperVNetworkAdapterName' | ForEach-Object -Process {
            Rename-NetAdapter -Name $_.Name -NewName $_.DisplayValue
        }
    
        'Setting the IP configuration on the network adapter...' | Write-ScriptLog -Context $NodeConfig.VMName -UseInScriptBlock

        # Management
        $params = @{
            AddressFamily  = 'IPv4'
            IPAddress      = $NodeConfig.NetAdapter.Management.IPAddress
            PrefixLength   = $NodeConfig.NetAdapter.Management.PrefixLength
            DefaultGateway = $NodeConfig.NetAdapter.Management.DefaultGateway
        }
        Get-NetAdapter -Name $NodeConfig.NetAdapter.Management.Name | New-NetIPAddress @params

        'Setting the DNS configuration on the network adapter...' | Write-ScriptLog -Context $NodeConfig.VMName -UseInScriptBlock
        Get-NetAdapter -Name $NodeConfig.NetAdapter.Management.Name |
            Set-DnsClientServerAddress -ServerAddresses $NodeConfig.NetAdapter.Management.DnsServerAddresses
    
        # Storage 1
        $params = @{
            AddressFamily  = 'IPv4'
            IPAddress      = $NodeConfig.NetAdapter.Storage1.IPAddress
            PrefixLength   = $NodeConfig.NetAdapter.Storage1.PrefixLength
        }
        Get-NetAdapter -Name $NodeConfig.NetAdapter.Storage1.Name | New-NetIPAddress @params
    
        # Storage 2
        $params = @{
            AddressFamily  = 'IPv4'
            IPAddress      = $NodeConfig.NetAdapter.Storage2.IPAddress
            PrefixLength   = $NodeConfig.NetAdapter.Storage2.PrefixLength
        }
        Get-NetAdapter -Name $NodeConfig.NetAdapter.Storage2.Name | New-NetIPAddress @params
    }

    'Joining the VM the AD domain...' | Write-ScriptLog -Context $NodeConfig.VMName
    $domainAdminCredential = CreateDomainCredential -DomainFqdn $labConfig.addsDomain.fqdn -Password $NodeConfig.AdminPassword
    $params = @{
        VMName                = $NodeConfig.VMName
        LocalAdminCredential  = $localAdminCredential
        DomainFqdn            = $labConfig.addsDomain.fqdn
        DomainAdminCredential = $domainAdminCredential
    }
    JoinVMToADDomain @params
    
    'Stopping the VM...' | Write-ScriptLog -Context $NodeConfig.VMName
    Stop-VM -Name $NodeConfig.VMName
    
    'Starting the VM...' | Write-ScriptLog -Context $NodeConfig.VMName
    Start-VM -Name $NodeConfig.VMName
}

foreach ($nodeConfig in $hciNodeConfigs) {
    'Waiting for ready to the VM...' | Write-ScriptLog -Context $nodeConfig.VMName
    $domainAdminCredential = CreateDomainCredential -DomainFqdn $labConfig.addsDomain.fqdn -Password $nodeConfig.AdminPassword
    WaitingForReadyToVM -VMName $nodeConfig.VMName -Credential $domainAdminCredential
}

'The HCI node VMs creation has been completed.' | Write-ScriptLog -Context $env:ComputerName

Stop-ScriptLogging
