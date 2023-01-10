[CmdletBinding()]
param ()

$ErrorActionPreference = [Management.Automation.ActionPreference]::Stop
$WarningPreference = [Management.Automation.ActionPreference]::Continue
$VerbosePreference = [Management.Automation.ActionPreference]::Continue
$ProgressPreference = [Management.Automation.ActionPreference]::SilentlyContinue

Import-Module -Name '.\shared.psm1' -Force

$configParams = GetConfigParameters
Start-Transcript -OutputDirectory $configParams.labHost.folderPath.transcript
$configParams | ConvertTo-Json -Depth 16

'Creating the HCI node VMs configuraton...' | WriteLog -Context $env:ComputerName

$adminPassword = GetSecret -KeyVaultName $configParams.keyVault.name -SecretName $configParams.keyVault.secretName

$hciNodeConfigs = @()
for ($i = 0; $i -lt $configParams.hciNode.nodeCount; $i++) {
    $hciNodeConfigs += @{
        VMName          = $configParams.hciNode.vmName -f ($configParams.hciNode.nodeCountOffset + $i)
        OperatingSystem = $configParams.hciNode.operatingSystem
        GuestOSCulture  = $configParams.guestOS.culture
        AdminPassword   = $adminPassword
        NetAdapter      = @{
            Management = @{
                Name               = $configParams.hciNode.netAdapter.management.name
                VSwitchName        = $configParams.labHost.vSwitch.nat.name
                IPAddress          = $configParams.hciNode.netAdapter.management.ipAddress -f ($configParams.hciNode.nodeCountOffset + $i)
                PrefixLength       = $configParams.hciNode.netAdapter.management.prefixLength
                DefaultGateway     = $configParams.hciNode.netAdapter.management.defaultGateway
                DnsServerAddresses = $configParams.hciNode.netAdapter.management.dnsServerAddresses
            }
            Storage1 = @{
                Name         = $configParams.hciNode.netAdapter.storage1.name
                VSwitchName  = $configParams.labHost.vSwitch.nat.name
                IPAddress    = $configParams.hciNode.netAdapter.storage1.ipAddress -f ($configParams.hciNode.nodeCountOffset + $i)
                PrefixLength = $configParams.hciNode.netAdapter.storage1.prefixLength
            }
            Storage2 = @{
                Name         = $configParams.hciNode.netAdapter.storage2.name
                VSwitchName  = $configParams.labHost.vSwitch.nat.name
                IPAddress    = $configParams.hciNode.netAdapter.storage2.ipAddress -f ($configParams.hciNode.nodeCountOffset + $i)
                PrefixLength = $configParams.hciNode.netAdapter.storage2.prefixLength
            }
        }
    }
}
$hciNodeConfigs | ConvertTo-Json -Depth 16

foreach ($nodeConfig in $hciNodeConfigs) {
    'Creating the OS disk...' | WriteLog -Context $nodeConfig.VMName
    $params = @{
        Differencing = $true
        ParentPath   = [IO.Path]::Combine($configParams.labHost.folderPath.vhd, ('{0}_{1}.vhdx' -f $nodeConfig.OperatingSystem, $nodeConfig.GuestOSCulture))
        Path         = [IO.Path]::Combine($configParams.labHost.folderPath.vm, $nodeConfig.VMName, 'osdisk.vhdx')
    }
    $vmOSDiskVhd = New-VHD  @params

    'Creating the VM...' | WriteLog -Context $nodeConfig.VMName
    $params = @{
        Name       = $nodeConfig.VMName
        Path       = $configParams.labHost.folderPath.vm
        VHDPath    = $vmOSDiskVhd.Path
        Generation = 2
    }
    New-VM @params
    
    'Setting processor configuration...' | WriteLog -Context $nodeConfig.VMName
    Set-VMProcessor -VMName $nodeConfig.VMName -Count 8 -ExposeVirtualizationExtensions $true

    'Setting memory configuration...' | WriteLog -Context $nodeConfig.VMName
    $params = @{
        VMName               = $nodeConfig.VMName
        StartupBytes         = 54GB
        DynamicMemoryEnabled = $true
        MinimumBytes         = 512MB
        MaximumBytes         = 54GB
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

    'Generating the unattend answer XML...' | WriteLog -Context $nodeConfig.VMName
    $encodedAdminPassword = GetEncodedAdminPasswordForUnattendAnswerFile -Password $nodeConfig.AdminPassword
    $unattendAnswerFileContent = @'
    <?xml version="1.0" encoding="utf-8"?>
    <unattend xmlns="urn:schemas-microsoft-com:unattend">
        <servicing></servicing>
        <settings pass="oobeSystem">
            <component name="Microsoft-Windows-Shell-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
                <UserAccounts>
                    <AdministratorPassword>
                        <Value>{0}</Value>
                        <PlainText>false</PlainText>
                    </AdministratorPassword>
                </UserAccounts>
                <OOBE>
                    <SkipMachineOOBE>true</SkipMachineOOBE>
                    <SkipUserOOBE>true</SkipUserOOBE>
                </OOBE>
            </component>
        </settings>
        <settings pass="specialize">
            <component name="Microsoft-Windows-International-Core" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
                <InputLocale>{1}</InputLocale>
                <SystemLocale>{1}</SystemLocale>
                <UILanguage>{1}</UILanguage>
                <UserLocale>{1}</UserLocale>
            </component>
            <component name="Microsoft-Windows-TerminalServices-LocalSessionManager" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
                <fDenyTSConnections>false</fDenyTSConnections>
            </component>
            <component name="Microsoft-Windows-Shell-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
                <ComputerName>{2}</ComputerName>
                <TimeZone>UTC</TimeZone>
            </component>
        </settings>
    </unattend>
'@ -f $encodedAdminPassword, $configParams.guestOS.culture, $nodeConfig.VMName

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
    while ((Start-VM -Name $nodeConfig.VMName -Passthru -ErrorAction SilentlyContinue) -eq $null) {
        'Will retry start the VM. Waiting for unmount the VHD...' | WriteLog -Context $nodeConfig.VMName
        Start-Sleep -Seconds 5
    }
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

        if ($nodeConfig.OperatingSystem -eq 'ws2022') {
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
    $domainAdminCredential = CreateDomainCredential -DomainFqdn $configParams.addsDC.domainFqdn -Password $nodeConfig.AdminPassword
    $params = @{
        VMName                = $nodeConfig.VMName
        LocalAdminCredential  = $localAdminCredential
        DomainFqdn            = $configParams.addsDC.domainFqdn
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
    $domainAdminCredential = CreateDomainCredential -DomainFqdn $configParams.addsDC.domainFqdn -Password $nodeConfig.AdminPassword
    WaitingForReadyToVM -VMName $nodeConfig.VMName -Credential $domainAdminCredential
}

'The HCI node VMs creation has been completed.' | WriteLog -Context $env:ComputerName

Stop-Transcript
