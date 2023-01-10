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

WriteLog -Context $env:ComputerName -Message 'Creating the HCI node VMs configuraton...'

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
    WriteLog -Context $nodeConfig.VMName -Message 'Creating the OS disk...'
    $params = @{
        Differencing = $true
        ParentPath   = [IO.Path]::Combine($configParams.labHost.folderPath.vhd, ('{0}_{1}.vhdx' -f $nodeConfig.OperatingSystem, $nodeConfig.GuestOSCulture))
        Path         = [IO.Path]::Combine($configParams.labHost.folderPath.vm, $nodeConfig.VMName, 'osdisk.vhdx')
    }
    $vmOSDiskVhd = New-VHD  @params

    WriteLog -Context $nodeConfig.VMName -Message 'Creating the VM...'
    $params = @{
        Name       = $nodeConfig.VMName
        Path       = $configParams.labHost.folderPath.vm
        VHDPath    = $vmOSDiskVhd.Path
        Generation = 2
    }
    New-VM @params
    
    WriteLog -Context $nodeConfig.VMName -Message 'Setting processor configuration...'
    Set-VMProcessor -VMName $nodeConfig.VMName -Count 8 -ExposeVirtualizationExtensions $true

    WriteLog -Context $nodeConfig.VMName -Message 'Setting memory configuration...'
    $params = @{
        VMName               = $nodeConfig.VMName
        StartupBytes         = 54GB
        DynamicMemoryEnabled = $true
        MinimumBytes         = 512MB
        MaximumBytes         = 54GB
    }
    Set-VMMemory @params
    
    WriteLog -Context $nodeConfig.VMName -Message 'Setting network adapter configuration...'
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

    WriteLog -Context $nodeConfig.VMName -Message 'Generating the unattend answer XML...'
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

    WriteLog -Context $nodeConfig.VMName -Message 'Injecting the unattend answer file to the VHD...'
    InjectUnattendAnswerFile -VhdPath $vmOSDiskVhd.Path -UnattendAnswerFileContent $unattendAnswerFileContent

    WriteLog -Context $nodeConfig.VMName -Message 'Installing the roles and features to the VHD...'
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

    WriteLog -Context $nodeConfig.VMName -Message 'Starting the VM...'
    while ((Start-VM -Name $nodeConfig.VMName -Passthru -ErrorAction SilentlyContinue) -eq $null) {
        WriteLog -Context $nodeConfig.VMName -Message 'Will retry start the VM. Waiting for unmount the VHD...'
        Start-Sleep -Seconds 5
    }
}

foreach ($nodeConfig in $hciNodeConfigs) {
    WriteLog -Context $nodeConfig.VMName -Message 'Waiting for ready to the VM...'
    $params = @{
        TypeName     = 'System.Management.Automation.PSCredential'
        ArgumentList = 'Administrator', $nodeConfig.AdminPassword
    }
    $localAdminCredential = New-Object @params
    WaitingForReadyToVM -VMName $nodeConfig.VMName -Credential $localAdminCredential
}

foreach ($nodeConfig in $hciNodeConfigs) {
    WriteLog -Context $nodeConfig.VMName -Message 'Configuring the VM...'

    $params = @{
        TypeName     = 'System.Management.Automation.PSCredential'
        ArgumentList = 'Administrator', $nodeConfig.AdminPassword
    }
    $localAdminCredential = New-Object @params

    Invoke-Command -VMName $nodeConfig.VMName -Credential $localAdminCredential -ArgumentList $nodeConfig -ScriptBlock {
        $ErrorActionPreference = [Management.Automation.ActionPreference]::Stop
        $WarningPreference = [Management.Automation.ActionPreference]::Continue
        $VerbosePreference = [Management.Automation.ActionPreference]::Continue
        $ProgressPreference = [Management.Automation.ActionPreference]::SilentlyContinue
    
        $nodeConfig = $args[0]

        if ($nodeConfig.OperatingSystem -eq 'ws2022') {
            WriteLog -Context $nodeConfig.VMName -Message 'Stop Server Manager launch at logon.'
            Set-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\ServerManager' -Name 'DoNotOpenServerManagerAtLogon' -Value 1
        
            WriteLog -Context $nodeConfig.VMName -Message 'Stop Windows Admin Center popup at Server Manager launch.'
            Set-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\ServerManager' -Name 'DoNotPopWACConsoleAtSMLaunch' -Value 1
        
            WriteLog -Context $nodeConfig.VMName -Message 'Hide the Network Location wizard. All networks will be Public.'
            New-Item -ItemType Directory -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Network' -Name 'NewNetworkWindowOff'
        }
    
        WriteLog -Context $nodeConfig.VMName -Message 'Renaming the network adapters...'
        Get-NetAdapterAdvancedProperty -RegistryKeyword 'HyperVNetworkAdapterName' | ForEach-Object -Process {
            Rename-NetAdapter -Name $_.Name -NewName $_.DisplayValue
        }
    
        WriteLog -Context $nodeConfig.VMName -Message 'Setting the IP configuration on the network adapter...'

        # Management
        $params = @{
            AddressFamily  = 'IPv4'
            IPAddress      = $nodeConfig.NetAdapter.Management.IPAddress
            PrefixLength   = $nodeConfig.NetAdapter.Management.PrefixLength
            DefaultGateway = $nodeConfig.NetAdapter.Management.DefaultGateway
        }
        Get-NetAdapter -Name $nodeConfig.NetAdapter.Management.Name | New-NetIPAddress @params

        WriteLog -Context $nodeConfig.VMName -Message 'Setting the DNS configuration on the network adapter...'
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

    WriteLog -Context $nodeConfig.VMName -Message 'Joining the VM the AD domain...'
    $domainAdminCredential = CreateDomainCredential -DomainFqdn $configParams.addsDC.domainFqdn -Password $nodeConfig.AdminPassword
    $params = @{
        VMName                = $nodeConfig.VMName
        LocalAdminCredential  = $localAdminCredential
        DomainFqdn            = $configParams.addsDC.domainFqdn
        DomainAdminCredential = $domainAdminCredential
    }
    JoinVMToADDomain @params
    
    WriteLog -Context $nodeConfig.VMName -Message 'Stopping the VM...'
    Stop-VM -Name $nodeConfig.VMName
    
    WriteLog -Context $nodeConfig.VMName -Message 'Starting the VM...'
    Start-VM -Name $nodeConfig.VMName
}

foreach ($nodeConfig in $hciNodeConfigs) {
    WriteLog -Context $nodeConfig.VMName -Message 'Waiting for ready to the VM...'
    $domainAdminCredential = CreateDomainCredential -DomainFqdn $configParams.addsDC.domainFqdn -Password $nodeConfig.AdminPassword
    WaitingForReadyToVM -VMName $nodeConfig.VMName -Credential $domainAdminCredential
}

WriteLog -Context $env:ComputerName -Message 'The HCI node VMs creation has been completed.'

Stop-Transcript
