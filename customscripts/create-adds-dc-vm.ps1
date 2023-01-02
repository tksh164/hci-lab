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

function WaitingForReadyToDC
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string] $VMName,

        [Parameter(Mandatory = $true)]
        [PSCredential] $Credential,

        [Parameter(Mandatory = $false)]
        [int] $CheckInternal = 5
    )

    $params = @{
        VMName       = $VMName
        Credential   = $Credential
        ArgumentList = $VMName  # The DC's computer name is the same as the VM name. It's specified in the unattend.xml.
        ScriptBlock  = {
            $dcComputerName = $args[0]
            (Get-ADDomainController -Server $dcComputerName).Enabled
        }
        ErrorAction  = [Management.Automation.ActionPreference]::SilentlyContinue
    }
    while ((Invoke-Command @params) -ne $true) {
        Start-Sleep -Seconds $CheckInternal
        Write-Verbose -Message 'Waiting...'
    }
}

$vmName = $configParams.addsDC.vmName
$vmStorePath = [IO.Path]::Combine($configParams.labHost.folderPath.vm, $vmName)

Write-Verbose -Message 'Creating the OS disk for the VM...'
$params = @{
    Differencing = $true
    ParentPath   = [IO.Path]::Combine($configParams.labHost.folderPath.vhd, ('{0}_{1}.vhdx' -f 'ws2022', $configParams.guestOS.culture))
    Path         = [IO.Path]::Combine($vmStorePath, 'osdisk.vhdx')
}
$vmOSDiskVhd = New-VHD  @params

Write-Verbose -Message 'Creating the VM...'
$params = @{
    Name       = $vmName
    Path       = $vmStorePath
    VHDPath    = $vmOSDiskVhd.Path
    Generation = 2
}
New-VM @params

Write-Verbose -Message 'Setting the VM''s processor configuration...'
Set-VMProcessor -VMName $vmName -Count 2

Write-Verbose -Message 'Setting the VM''s memory configuration...'
$params = @{
    VMName               = $vmName
    StartupBytes         = 2GB
    DynamicMemoryEnabled = $true
    MinimumBytes         = 512MB
    MaximumBytes         = 2GB
}
Set-VMMemory @params

Write-Verbose -Message 'Setting the VM''s network adapter configuration...'
Get-VMNetworkAdapter -VMName $vmName | Remove-VMNetworkAdapter
$params = @{
    VMName       = $vmName
    Name         = $configParams.addsDC.netAdapter.management.name
    SwitchName   = $configParams.labHost.vSwitch.nat.name
    DeviceNaming = 'On'
}
Add-VMNetworkAdapter @params

Write-Verbose -Message 'Generating the unattend answer XML...'
$adminPassword = GetSecret -KeyVaultName $configParams.keyVault.name -SecretName $configParams.keyVault.secretName
$encodedAdminPassword = GetEncodedAdminPasswordForUnattendAnswerFile -Password $adminPassword
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
'@ -f $encodedAdminPassword, $configParams.guestOS.culture, $vmName

Write-Verbose -Message 'Injecting the unattend answer file to the VM...'
InjectUnattendAnswerFile -VhdPath $vmOSDiskVhd.Path -UnattendAnswerFileContent $unattendAnswerFileContent

Write-Verbose -Message 'Starting the VM...'
Start-VM -Name $vmName

Write-Verbose -Message 'Waiting for ready to the VM...'
$params = @{
    TypeName     = 'System.Management.Automation.PSCredential'
    ArgumentList = 'Administrator', $adminPassword
}
$localAdminCredential = New-Object @params
WaitingForReadyToVM -VMName $vmName -Credential $localAdminCredential

Write-Verbose -Message 'Configuring the new VM...'
Invoke-Command -VMName $vmName -Credential $localAdminCredential -ArgumentList $configParams, $adminPassword -ScriptBlock {
    $ErrorActionPreference = [Management.Automation.ActionPreference]::Stop
    $WarningPreference = [Management.Automation.ActionPreference]::Continue
    $VerbosePreference = [Management.Automation.ActionPreference]::Continue
    $ProgressPreference = [Management.Automation.ActionPreference]::SilentlyContinue

    $configParams = $args[0]
    $adminPassword = $args[1]

    Write-Verbose -Message 'Stop Server Manager launch at logon.'
    Set-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\ServerManager' -Name 'DoNotOpenServerManagerAtLogon' -Value 1

    Write-Verbose -Message 'Stop Windows Admin Center popup at Server Manager launch.'
    Set-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\ServerManager' -Name 'DoNotPopWACConsoleAtSMLaunch' -Value 1

    Write-Verbose -Message 'Hide the Network Location wizard. All networks will be Public.'
    New-Item -ItemType Directory -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Network' -Name 'NewNetworkWindowOff'

    Write-Verbose -Message 'Renaming the network adapters...'
    Get-NetAdapterAdvancedProperty -RegistryKeyword 'HyperVNetworkAdapterName' | ForEach-Object -Process {
        Rename-NetAdapter -Name $_.Name -NewName $_.DisplayValue
    }

    Write-Verbose -Message 'Setting the IP configuration on the network adapter...'
    $params = @{
        AddressFamily  = 'IPv4'
        IPAddress      = $configParams.addsDC.netAdapter.management.ipAddress
        PrefixLength   = $configParams.addsDC.netAdapter.management.prefixLength
        DefaultGateway = $configParams.addsDC.netAdapter.management.defaultGateway
    }
    Get-NetAdapter -Name $configParams.addsDC.netAdapter.management.name | New-NetIPAddress @params
    
    Write-Verbose -Message 'Setting the DNS configuration on the network adapter...'
    Get-NetAdapter -Name $configParams.addsDC.netAdapter.management.name |
        Set-DnsClientServerAddress -ServerAddresses $configParams.addsDC.netAdapter.management.dnsServerAddresses

    Write-Verbose -Message 'Installing the roles and features...'
    Install-WindowsFeature -Name 'AD-Domain-Services' -IncludeManagementTools

    Write-Verbose -Message 'Installing AD DS (Create a new forest)...'
    $params = @{
        DomainName                    = $configParams.addsDC.domainFqdn
        InstallDns                    = $true
        SafeModeAdministratorPassword = $adminPassword
        NoRebootOnCompletion          = $true
        Force                         = $true
    }
    Install-ADDSForest @params
}

Write-Verbose -Message 'Stopping the VM...'
Stop-VM -Name $vmName

Write-Verbose -Message 'Starting the VM...'
Start-VM -Name $vmName

Write-Verbose -Message 'Waiting for ready to the domain controller...'
$domainAdminCredential = CreateDomainCredential -DomainFqdn $configParams.addsDC.domainFqdn -Password $adminPassword
WaitingForReadyToDC -VMName $vmName -Credential $domainAdminCredential

Write-Verbose -Message 'The AD DS Domain Controller VM creation has been completed.'

Stop-Transcript
