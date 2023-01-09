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

$vmName = $configParams.wac.vmName

Write-Verbose -Message 'Creating the OS disk for the VM...'
$params = @{
    Differencing = $true
    ParentPath   = [IO.Path]::Combine($configParams.labHost.folderPath.vhd, ('{0}_{1}.vhdx' -f 'ws2022', $configParams.guestOS.culture))
    Path         = [IO.Path]::Combine($configParams.labHost.folderPath.vm, $vmName, 'osdisk.vhdx')
}
$vmOSDiskVhd = New-VHD  @params

Write-Verbose -Message 'Creating the VM...'
$params = @{
    Name       = $vmName
    Path       = $configParams.labHost.folderPath.vm
    VHDPath    = $vmOSDiskVhd.Path
    Generation = 2
}
New-VM @params

Write-Verbose -Message 'Setting the VM''s processor configuration...'
Set-VMProcessor -VMName $vmName -Count 4

Write-Verbose -Message 'Setting the VM''s memory configuration...'
$params = @{
    VMName               = $vmName
    StartupBytes         = 6GB
    DynamicMemoryEnabled = $true
    MinimumBytes         = 512MB
    MaximumBytes         = 6GB
}
Set-VMMemory @params

Write-Verbose -Message 'Setting the VM''s network adapter configuration...'
Get-VMNetworkAdapter -VMName $vmName | Remove-VMNetworkAdapter
$params = @{
    VMName       = $vmName
    Name         = $configParams.wac.netAdapter.management.name
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

Write-Verbose -Message 'Installing the roles and features to the VHD...'
$features = @(
    'RSAT-ADDS-Tools',
    'RSAT-AD-AdminCenter',
    'RSAT-AD-PowerShell',
    'RSAT-Clustering-Mgmt',
    'RSAT-Clustering-PowerShell',
    'Hyper-V-Tools',
    'Hyper-V-PowerShell'
)
Install-WindowsFeature -Vhd $vmOSDiskVhd.Path -Name $features

Write-Verbose -Message 'Starting the VM...'
while ((Start-VM -Name $vmName -Passthru -ErrorAction SilentlyContinue) -eq $null) {
    Write-Verbose -Message ('[{0}] Will retry start the VM. Waiting for unmount the VHD...' -f $vmName)
    Start-Sleep -Seconds 5
}

Write-Verbose -Message 'Waiting for ready to the VM...'
$params = @{
    TypeName     = 'System.Management.Automation.PSCredential'
    ArgumentList = 'Administrator', $adminPassword
}
$localAdminCredential = New-Object @params
WaitingForReadyToVM -VMName $vmName -Credential $localAdminCredential

Write-Verbose -Message 'Downloading the Windows Admin Center installer...'
$params = @{
    SourceUri      = 'https://aka.ms/WACDownload'
    DownloadFolder = $configParams.labHost.folderPath.temp
    FileNameToSave = 'WindowsAdminCenter.msi'
}
$wacInstallerFile = DownloadFile @params
$wacInstallerFile

Write-Verbose -Message 'Copying the Windows Admin Center installer into the VM...'
$wacInstallerFilePathInVM = [IO.Path]::Combine('C:\Windows\Temp', [IO.Path]::GetFileName($wacInstallerFile.FullName))
$psSession = New-PSSession -VMName $vmName -Credential $localAdminCredential
Copy-Item -ToSession $psSession -Path $wacInstallerFile.FullName -Destination $wacInstallerFilePathInVM

Write-Verbose -Message 'Configuring the new VM...'
Invoke-Command -VMName $vmName -Credential $localAdminCredential -ArgumentList $configParams, $wacInstallerFilePathInVM -ScriptBlock {
    $ErrorActionPreference = [Management.Automation.ActionPreference]::Stop
    $WarningPreference = [Management.Automation.ActionPreference]::Continue
    $VerbosePreference = [Management.Automation.ActionPreference]::Continue
    $ProgressPreference = [Management.Automation.ActionPreference]::SilentlyContinue

    $configParams = $args[0]
    $wacInstallerFilePath = $args[1]

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
        IPAddress      = $configParams.wac.netAdapter.management.ipAddress
        PrefixLength   = $configParams.wac.netAdapter.management.prefixLength
        DefaultGateway = $configParams.wac.netAdapter.management.defaultGateway
    }
    Get-NetAdapter -Name $configParams.wac.netAdapter.management.name | New-NetIPAddress @params
    
    Write-Verbose -Message 'Setting the DNS configuration on the network adapter...'
    Get-NetAdapter -Name $configParams.wac.netAdapter.management.name |
        Set-DnsClientServerAddress -ServerAddresses $configParams.wac.netAdapter.management.dnsServerAddresses

    Write-Verbose -Message 'Installing Windows Admin Center...'
    $msiArgs = @(
        '/i',
        ('"{0}"' -f $wacInstallerFilePath),
        '/qn',
        '/L*v',
        '"C:\Windows\Temp\wac-install-log.txt"'
        'SME_PORT=443',
        'SSL_CERTIFICATE_OPTION=generate'
    )
    $result = Start-Process -FilePath 'msiexec.exe' -ArgumentList $msiArgs -Wait -PassThru
    $result | Format-List -Property '*'
    if ($result.ExitCode -ne 0) {
        throw ('Windows Admin Center installation failed with exit code {0}.' -f $result.ExitCode)
    }
    Remove-Item -LiteralPath $wacInstallerFilePath -Force

    Write-Verbose -Message 'Creating shortcut for Windows Admin Center on the desktop....'
    $wshShell = New-Object -ComObject 'WScript.Shell'
    $shortcut = $wshShell.CreateShortcut('C:\Users\Public\Desktop\Windows Admin Center.lnk')
    $shortcut.TargetPath = 'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe'
    $shortcut.Arguments = 'https://{0}' -f $env:ComputerName
    $shortcut.Description = 'Windows Admin Center for the lab environment.'
    $shortcut.IconLocation = 'shell32.dll,34'
    $shortcut.Save()
}

Write-Verbose -Message 'Joining the VM to the AD domain...'
$domainAdminCredential = CreateDomainCredential -DomainFqdn $configParams.addsDC.domainFqdn -Password $adminPassword
$params = @{
    VMName                = $vmName
    LocalAdminCredential  = $localAdminCredential
    DomainFqdn            = $configParams.addsDC.domainFqdn
    DomainAdminCredential = $domainAdminCredential
}
JoinVMToADDomain @params

Write-Verbose -Message 'Stopping the VM...'
Stop-VM -Name $vmName

Write-Verbose -Message 'Starting the VM...'
Start-VM -Name $vmName

Write-Verbose -Message 'Waiting for ready to the VM...'
WaitingForReadyToVM -VMName $vmName -Credential $domainAdminCredential

Write-Verbose -Message 'The WAC VM creation has been completed.'

Stop-Transcript
