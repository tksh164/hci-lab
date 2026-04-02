[CmdletBinding()]
param (
    [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
    [string[]] $ImportModulePath,

    [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
    [string] $LogFileName,

    [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
    [string] $LogContext,

    [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
    [string] $JobParamsJson
)

$ErrorActionPreference = [Management.Automation.ActionPreference]::Stop
$WarningPreference = [Management.Automation.ActionPreference]::Continue
$VerbosePreference = [Management.Automation.ActionPreference]::Continue
$ProgressPreference = [Management.Automation.ActionPreference]::SilentlyContinue

try {
    # Mandatory pre-processing.
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    Import-Module -Name $ImportModulePath -Force
    $labConfig = Get-LabDeploymentConfig
    Start-ScriptLogging -OutputDirectory $labConfig.labHost.folderPath.log -FileName $LogFileName
    Set-ScriptLogDefaultContext -LogContext $LogContext
    'Lab deployment config: {0}' -f ($labConfig | ConvertTo-Json -Depth 16) | Write-ScriptLog

    # Log the job parameters.
    'Job parameters:' | Write-ScriptLog
    foreach ($key in $PSBoundParameters.Keys) {
        if ($PSBoundParameters[$key].GetType().FullName -eq 'System.String[]') {
            '- {0}: {1}' -f $key, ($PSBoundParameters[$key] -join ',') | Write-ScriptLog
        }
        else {
            '- {0}: {1}' -f $key, $PSBoundParameters[$key] | Write-ScriptLog
        }
    }

    # Retrieve the job parameters from the JSON string.
    $jobParams = $JobParamsJson | ConvertFrom-Json

    'Start blocking the AD DS domain operations on other VMs.' | Write-ScriptLog
    Block-AddsDomainOperation

    #
    # Hyper-V VM creation
    #

    $vmName = $labConfig.addsDC.vmName

    'Create the OS disk for the VM.' | Write-ScriptLog
    $params = @{
        Path                    = [System.IO.Path]::Combine($labConfig.labHost.folderPath.vm, $vmName, 'osdisk.vhdx')
        Differencing            = $true
        ParentPath              = $jobParams.BaseVhdFilePath
        BlockSizeBytes          = 32MB
        PhysicalSectorSizeBytes = 4KB
    }
    $vmOSDiskVhd = New-VHD  @params
    'Create the OS disk for the VM has been completed.' | Write-ScriptLog

    'Create the VM.' | Write-ScriptLog
    $params = @{
        Name       = $vmName
        Path       = $labConfig.labHost.folderPath.vm
        VHDPath    = $vmOSDiskVhd.Path
        Generation = 2
    }
    New-VM @params | Out-String | Write-ScriptLog
    'Create the VM has been completed.' | Write-ScriptLog

    'Change the VM''s automatic stop action.' | Write-ScriptLog
    Set-VM -Name $vmName -AutomaticStopAction ShutDown
    'Change the VM''s automatic stop action has been completed.' | Write-ScriptLog

    'Configure the VM''s processor.' | Write-ScriptLog
    $vmProcessorCount = 4
    if ((Get-VMHost).LogicalProcessorCount -lt $vmProcessorCount) { $vmProcessorCount = (Get-VMHost).LogicalProcessorCount }
    Set-VMProcessor -VMName $vmName -Count $vmProcessorCount
    'Configure the VM''s processor has been completed.' | Write-ScriptLog

    'Configure the VM''s memory.' | Write-ScriptLog
    $params = @{
        VMName               = $vmName
        StartupBytes         = 1GB
        DynamicMemoryEnabled = $true
        MinimumBytes         = 512MB
        MaximumBytes         = $labConfig.addsDC.maximumRamBytes
    }
    Set-VMMemory @params
    'Configure the VM''s memory has been completed.' | Write-ScriptLog

    'Enable the VM''s vTPM.' | Write-ScriptLog
    $params = @{
        VMName               = $vmName
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
        ) | Write-ScriptLog -Level Warning

        # Rescue only once by retry.
        Set-VMKeyProtector @params | Enable-VMTPM
    }
    'Enable the VM''s vTPM has been completed.' | Write-ScriptLog

    'Configure the VM''s network adapters.' | Write-ScriptLog
    Get-VMNetworkAdapter -VMName $vmName | Remove-VMNetworkAdapter

    # Management
    'Configure the {0} network adapter.' -f $labConfig.addsDC.netAdapters.management.name | Write-ScriptLog
    $paramsForAdd = @{
        VMName       = $vmName
        Name         = $labConfig.addsDC.netAdapters.management.name
        SwitchName   = $labConfig.labHost.vSwitch.nat.name
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
    'Configure the {0} network adapter has been completed.' -f $labConfig.addsDC.netAdapters.management.name | Write-ScriptLog

    'Generate the unattend answer XML.' | Write-ScriptLog
    $adminPassword = Get-Secret -KeyVaultName $labConfig.keyVault.name -SecretName $labConfig.keyVault.secretName.adminPassword
    $params = @{
        ComputerName = $vmName
        Password     = $adminPassword
        Culture      = $labConfig.guestOS.culture
        TimeZone     = $labConfig.guestOS.timeZone
    }
    $unattendAnswerFileContent = New-UnattendAnswerFileContent @params
    'Generate the unattend answer XML has been completed.' | Write-ScriptLog

    'Inject the unattend answer file to the "{0}".' -f $vmOSDiskVhd.Path | Write-ScriptLog
    $params = @{
        VhdPath                   = $vmOSDiskVhd.Path
        UnattendAnswerFileContent = $unattendAnswerFileContent
        LogFolder                 = $labConfig.labHost.folderPath.log
    }
    Set-UnattendAnswerFileToVhd @params
    'Inject the unattend answer file to the "{0}" has been completed.' -f $vmOSDiskVhd.Path | Write-ScriptLog

    'Install the roles and features to the "{0}".' -f $vmOSDiskVhd.Path | Write-ScriptLog
    $params = @{
        VhdPath     = $vmOSDiskVhd.Path
        FeatureName = @(
            'AD-Domain-Services'
            # DNS, FS-FileServer, RSAT-AD-PowerShell are automatically installed as dependencies.
        )
        LogFolder   = $labConfig.labHost.folderPath.log
    }
    Install-WindowsFeatureToVhd @params
    'Install the roles and features to the "{0}" has been completed.' -f $vmOSDiskVhd.Path | Write-ScriptLog

    Start-VMSurely -VMName $vmName

    'Wait for the VM to be ready.' | Write-ScriptLog
    $localAdminCredential = New-LogonCredential -DomainFqdn '.' -Password $adminPassword
    Wait-PowerShellDirectReady -VMName $vmName -Credential $localAdminCredential
    'The VM is ready.' | Write-ScriptLog

    #
    # Guest OS configuration
    #

    'Copy the module files into the VM.' | Write-ScriptLog
    $params = @{
        VMName              = $vmName
        Credential          = $localAdminCredential
        SourceFilePath      = (Get-Module -Name 'common').Path
        DestinationPathInVM = 'C:\Windows\Temp'
    }
    $moduleFilePathsWithinVM = Copy-FileIntoVM @params
    'Copy the module files into the VM has been completed.' | Write-ScriptLog

    # The common parameters for Invoke-CommandWithinVM.
    $invokeWithinVMParams = @{
        VMName           = $vmName
        Credential       = $localAdminCredential
        ImportModuleInVM = $moduleFilePathsWithinVM
    }

    'Configure registry values within the VM.' | Write-ScriptLog
    Invoke-CommandWithinVM @invokeWithinVMParams -ScriptBlock {
        'Disable diagnostics data send screen.' | Write-ScriptLog
        New-RegistryKey -ParentPath 'HKLM:\SOFTWARE\Policies\Microsoft\Windows' -KeyName 'OOBE'
        Set-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\OOBE' -Name 'DisablePrivacyExperience' -Value 1
        'Disable diagnostics data send screen has been completed.' | Write-ScriptLog
    
        'Stop Server Manager launch at logon.' | Write-ScriptLog
        Set-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\ServerManager' -Name 'DoNotOpenServerManagerAtLogon' -Value 1
        'Stop Server Manager launch at logon has been completed.' | Write-ScriptLog

        'Stop Windows Admin Center popup at Server Manager launch.' | Write-ScriptLog
        Set-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\ServerManager' -Name 'DoNotPopWACConsoleAtSMLaunch' -Value 1
        'Stop Windows Admin Center popup at Server Manager launch has been completed.' | Write-ScriptLog

        'Hide the Network Location wizard. All networks will be Public.' | Write-ScriptLog
        New-RegistryKey -ParentPath 'HKLM:\SYSTEM\CurrentControlSet\Control\Network' -KeyName 'NewNetworkWindowOff'
        'Hide the Network Location wizard has been completed.' | Write-ScriptLog
    }
    'Configure registry values within the VM has been completed.' | Write-ScriptLog

    'Rename the network adapters.' | Write-ScriptLog
    Invoke-CommandWithinVM @invokeWithinVMParams -WithRetry -ScriptBlock {
        Get-NetAdapterAdvancedProperty -RegistryKeyword 'HyperVNetworkAdapterName' | ForEach-Object -Process {
            Rename-NetAdapter -Name $_.Name -NewName $_.DisplayValue
        }
    }
    'Rename the network adapters has been completed.' | Write-ScriptLog

    # Management
    $netAdapterConfig = $labConfig.addsDC.netAdapters.management
    'Configure the IP & DNS on the "{0}" network adapter.' -f $netAdapterConfig.name | Write-ScriptLog
    Invoke-CommandWithinVM @invokeWithinVMParams -WithRetry -ScriptBlockParamList $netAdapterConfig -ScriptBlock {
        param (
            [Parameter(Mandatory = $true)]
            [PSCustomObject] $NetAdapterConfig
        )

        # Remove default route.
        Get-NetAdapter -Name $NetAdapterConfig.name |
        Get-NetIPInterface -AddressFamily 'IPv4' |
        Remove-NetRoute -DestinationPrefix '0.0.0.0/0' -Confirm:$false -ErrorAction SilentlyContinue

        # Remove existing NetIPAddresses.
        Get-NetAdapter -Name $NetAdapterConfig.name |
        Get-NetIPInterface -AddressFamily 'IPv4' |
        Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue

        # Configure the IP & DNS on the network adapter.
        $paramsForSetNetIPInterface = @{
            AddressFamily = 'IPv4'
            Dhcp          = 'Disabled'
            PassThru      = $true
        }
        $paramsForNewIPAddress = @{
            AddressFamily  = 'IPv4'
            IPAddress      = $NetAdapterConfig.ipAddress
            PrefixLength   = $NetAdapterConfig.prefixLength
            DefaultGateway = $NetAdapterConfig.defaultGateway
        }
        $paramsForSetDnsClientServerAddress = @{
            ServerAddresses = $NetAdapterConfig.dnsServerAddresses
        }
        Get-NetAdapter -Name $NetAdapterConfig.name |
        Set-NetIPInterface @paramsForSetNetIPInterface |
        New-NetIPAddress @paramsForNewIPAddress |
        Set-DnsClientServerAddress @paramsForSetDnsClientServerAddress |
        Out-Null
    }
    'Configure the IP & DNS on the "{0}" network adapter has been completed.' -f $netAdapterConfig.name | Write-ScriptLog

    'Log the network settings within the VM.' | Write-ScriptLog
    Invoke-CommandWithinVM @invokeWithinVMParams -WithRetry -ScriptBlock {
        'Network adapter configurations:' | Write-ScriptLog
        Get-NetAdapter | Sort-Object -Property 'Name' | Format-Table -Property @(
            'Name',
            'InterfaceIndex',
            'InterfaceAlias',
            'VlanID',
            'Status',
            'MediaConnectionState',
            'MtuSize',
            'LinkSpeed',
            'MacAddress',
            'InterfaceDescription'
        ) | Out-String -Width 200 | Write-ScriptLog

        'Network adapter IP configurations:' | Write-ScriptLog
        Get-NetIPAddress | Sort-Object -Property 'InterfaceAlias' | Format-Table -Property @(
            'InterfaceAlias',
            'InterfaceIndex',
            'AddressFamily',
            'IPAddress',
            'PrefixLength',
            'PrefixOrigin',
            'SuffixOrigin',
            'AddressState',
            'Store'
        ) | Out-String -Width 200 | Write-ScriptLog

        'Network adapter DNS configurations:' | Write-ScriptLog
        Get-DnsClientServerAddress | Sort-Object -Property 'InterfaceAlias' | Format-Table -Property @(
            'InterfaceAlias',
            'InterfaceIndex',
            @{ Label = 'AddressFamily'; Expression = { Switch ($_.AddressFamily) { 2 { 'IPv4' } 23 { 'IPv6' } default { $_.AddressFamily } } } }
            @{ Label = 'DNSServers'; Expression = { $_.ServerAddresses } }
        ) | Out-String -Width 200 | Write-ScriptLog
    }
    'Log the network settings within the VM has been completed.' | Write-ScriptLog

    'Install AD DS (Creating a new forest) within the VM.' | Write-ScriptLog
    $scriptBlockParamList = @(
        $labConfig.addsDomain.fqdn,
        $adminPassword
    )
    Invoke-CommandWithinVM @invokeWithinVMParams -ScriptBlockParamList $scriptBlockParamList -ScriptBlock {
        param (
            [Parameter(Mandatory = $true)]
            [string] $DomainName,

            [Parameter(Mandatory = $true)]
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
    } | Out-String | Write-ScriptLog
    'Install AD DS (Creating a new forest) within the VM has been completed.' | Write-ScriptLog

    'Delete the module files within the VM.' | Write-ScriptLog
    $params = @{
        VMName               = $invokeWithinVMParams.VMName
        Credential           = $invokeWithinVMParams.Credential
        FilePathToRemoveInVM = $invokeWithinVMParams.ImportModuleInVM
        ImportModuleInVM     = $invokeWithinVMParams.ImportModuleInVM
    }
    Remove-FileWithinVM @params
    'Delete the module files within the VM has been completed.' | Write-ScriptLog

    # Reboot the VM.
    Stop-VMSurely -VMName $vmName
    Start-VMSurely -VMName $vmName

    'Wait for ready to the domain controller.' | Write-ScriptLog
    $domainAdminCredential = New-LogonCredential -DomainFqdn $labConfig.addsDomain.fqdn -Password $adminPassword
    # The DC's computer name is the same as the VM name. It's specified in the unattend.xml.
    Wait-DomainControllerServiceReady -AddsDcVMName $vmName -AddsDcComputerName $vmName -Credential $domainAdminCredential
    'The domain controller is ready.' | Write-ScriptLog

    'Allow the AD DS domain operations on other VMs.' | Write-ScriptLog
    Unblock-AddsDomainOperation

    'This script has been completed all tasks.' | Write-ScriptLog
}
catch {
    $exceptionMessage = New-ExceptionMessage -ErrorRecord $_
    $exceptionMessage | Write-ScriptLog -Level Error
    throw $exceptionMessage
}
finally {
    # Mandatory post-processing.
    $stopWatch.Stop()
    'Script duration: {0}' -f $stopWatch.Elapsed.toString('hh\:mm\:ss') | Write-ScriptLog
    Stop-ScriptLogging
}
