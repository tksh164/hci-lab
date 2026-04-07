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

function Get-HciNodeRamSize {
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

function Get-HciNodeProcessorCount {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [int] $NodeCount
    )

    # Heuristic calculation.
    # This calculation keeps the ratio of Hyper-V host logical processors : Total Hyper-V VM processors = 1 : approx. 2.5.
    # Approx. 2.5 = ((Floor((Hyper-V host logical processors / Node count) * 2) * Node count) + ADDDS VM processors + WAC VM processors) / Hyper-V host logical processors
    return [Math]::Floor(((Get-VMHost).LogicalProcessorCount / $NodeCount) * 2)
}

function New-HypervVM {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [PSCustomObject] $VMConfig,

        [Parameter(Mandatory = $true)]
        [string] $VMFolderPath
    )

    'Create the OS disk.' | Write-ScriptLog
    $params = @{
        Path                    = [IO.Path]::Combine($VMFolderPath, $VMConfig.VMName, 'osdisk.vhdx')
        Differencing            = $true
        ParentPath              = $VMConfig.ParentVhdPath
        BlockSizeBytes          = 32MB
        PhysicalSectorSizeBytes = 4KB
    }
    $vmOSDiskVhd = New-VHD @params
    'Create the OS disk has been completed.' | Write-ScriptLog

    'Create the VM.' | Write-ScriptLog
    $params = @{
        Name       = $VMConfig.VMName
        Path       = $VMFolderPath
        VHDPath    = $vmOSDiskVhd.Path
        Generation = 2
    }
    New-VM @params | Out-String | Write-ScriptLog
    'Create the VM has been completed.' | Write-ScriptLog

    'Change the VM''s automatic stop action.' | Write-ScriptLog
    Set-VM -Name $VMConfig.VMName -AutomaticStopAction ShutDown
    'Change the VM''s automatic stop action has been completed.' | Write-ScriptLog

    'Configure the VM''s processor.' | Write-ScriptLog
    Set-VMProcessor -VMName $VMConfig.VMName -Count $VMConfig.ProcessorCount -ExposeVirtualizationExtensions $true
    'Configure the VM''s processor has been completed.' | Write-ScriptLog

    'Configure the VM''s memory.' | Write-ScriptLog
    $params = @{
        VMName               = $VMConfig.VMName
        StartupBytes         = $VMConfig.RamBytes
        DynamicMemoryEnabled = $false
    }
    Set-VMMemory @params
    'Configure the VM''s memory has been completed.' | Write-ScriptLog

    'Enable the VM''s vTPM.' | Write-ScriptLog
    $params = @{
        VMName               = $VMConfig.VMName
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
    Get-VMNetworkAdapter -VMName $VMConfig.VMName | Remove-VMNetworkAdapter

    # Management
    'Configure the {0} network adapter.' -f $VMConfig.NetAdapters.Management.Name | Write-ScriptLog
    $paramsForAdd = @{
        VMName       = $VMConfig.VMName
        Name         = $VMConfig.NetAdapters.Management.Name
        SwitchName   = $VMConfig.NetAdapters.Management.VSwitchName
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
    'Configure the {0} network adapter has been completed.' -f $VMConfig.NetAdapters.Management.Name | Write-ScriptLog

    # Compute
    'Configure the {0} network adapter.' -f $VMConfig.NetAdapters.Compute.Name | Write-ScriptLog
    $paramsForAdd = @{
        VMName       = $VMConfig.VMName
        Name         = $VMConfig.NetAdapters.Compute.Name
        SwitchName   = $VMConfig.NetAdapters.Compute.VSwitchName
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
    'Configure the {0} network adapter has been completed.' -f $VMConfig.NetAdapters.Compute.Name | Write-ScriptLog

    # Storage 1
    'Configure the {0} network adapter.' -f $VMConfig.NetAdapters.Storage1.Name | Write-ScriptLog
    $paramsForAdd = @{
        VMName       = $VMConfig.VMName
        Name         = $VMConfig.NetAdapters.Storage1.Name
        SwitchName   = $VMConfig.NetAdapters.Storage1.VSwitchName
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
    'Configure the {0} network adapter has been completed.' -f $VMConfig.NetAdapters.Storage1.Name | Write-ScriptLog

    # Storage 2
    'Configure the {0} network adapter.' -f $VMConfig.NetAdapters.Storage2.Name | Write-ScriptLog
    $paramsForAdd = @{
        VMName       = $VMConfig.VMName
        Name         = $VMConfig.NetAdapters.Storage2.Name
        SwitchName   = $VMConfig.NetAdapters.Storage2.VSwitchName
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
    'Configure the {0} network adapter has been completed.' -f $VMConfig.NetAdapters.Storage2.Name | Write-ScriptLog

    'Create the data disks.' | Write-ScriptLog
    $addDataDisksResult = for ($diskIndex = 1; $diskIndex -le $VMConfig.DataDisk.Count; $diskIndex++) {
        $params = @{
            Path                    = [IO.Path]::Combine($VMFolderPath, $VMConfig.VMName, ('datadisk{0}.vhdx' -f $diskIndex))
            Dynamic                 = $true
            SizeBytes               = $VMConfig.DataDisk.SizeBytes
            BlockSizeBytes          = 32MB
            PhysicalSectorSizeBytes = 4KB
            LogicalSectorSizeBytes  = 4KB
        }
        $vmDataDiskVhd = New-VHD @params
        Add-VMHardDiskDrive -VMName $VMConfig.VMName -Path $vmDataDiskVhd.Path -Passthru
    }
    $addDataDisksResult | Format-Table -Property @(
        'VMName',
        'ControllerType',
        'ControllerNumber',
        'ControllerLocation',
        'DiskNumber',
        'Path'
    ) | Out-String -Width 200 | Write-ScriptLog
    'Create the data disks has been completed.' | Write-ScriptLog

    return [PSCustomObject] @{
        OSDiskVhdFilePath = $vmOSDiskVhd.Path
    }
}

function Get-WindowsFeatureToInstall {
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

function Wait-BootstrapServices {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string] $VMName,

        [Parameter(Mandatory = $true)]
        [PSCredential] $Credential,

        [Parameter(Mandatory = $false)]
        [ValidateRange(0, 3600)]
        [int] $RetryTimeoutSeconds = 600,

        [Parameter(Mandatory = $false)]
        [ValidateRange(0, 3600)]
        [int] $RetryIntervalSeconds = 30,

        [Parameter(Mandatory = $false)]
        [ValidateRange(0, 3600)]
        [int] $LoggingIntervalSeconds = 60
    )

    $startTime = Get-Date
    $endTime = $startTime.AddSeconds($RetryTimeoutSeconds)

    while ((Get-Date) -lt $endTime) {
        try {
            $params = @{
                VMName      = $VMName
                Credential  = $Credential
                ScriptBlock = {
                    ((Get-Service -Name 'BootstrapManagementService').Status -eq 'Running') -and
                    ((Get-Service -Name 'BootstrapRestService').Status -eq 'Running')
                }
                ErrorAction = [Management.Automation.ActionPreference]::Stop
            }
            if ((Invoke-Command @params)) {
                'The Bootstrap services are ready on the VM.' | Write-ScriptLog
                return
            }
        }
        catch {
            '{0} (ExceptionMessage: {1} | Exception: {2} | FullyQualifiedErrorId: {3} | CategoryInfo: {4} | ErrorDetailsMessage: {5})' -f @(
                'Checking the Bootstrap services status...',
                $_.Exception.Message,
                $_.Exception.GetType().FullName,
                $_.FullyQualifiedErrorId,
                $_.CategoryInfo.ToString(),
                $_.ErrorDetails.Message
            ) | Write-ScriptLog -Level Warning
        }

        Start-Sleep -Seconds $RetryIntervalSeconds
        $elapsedSeconds = [int] ((Get-Date) - $startTime).TotalSeconds
        if (($elapsedSeconds % $LoggingIntervalSeconds) -eq 0) {
            Write-Host ('{0} seconds elapsed.' -f $elapsedSeconds)
        }
    }

    throw 'The Bootstrap services did not enter the running state in {0} seconds.' -f $RetryTimeoutSeconds
}

function Invoke-AzureLocalScheduledTask {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string] $VMName,

        [Parameter(Mandatory = $true)]
        [PSCredential] $Credential
    )

    $params = @{
        VMName      = $VMName
        Credential  = $Credential
        ScriptBlock = {
            $task = Get-ScheduledTask -TaskName 'ImageCustomizationScheduledTask'
            if ($task.State -eq 'Ready') {
                $task | Start-ScheduledTask
            }
        }
        ErrorAction = [Management.Automation.ActionPreference]::Stop
    }
    Invoke-Command @params
}

function Wait-AzureLocalScheduledTaskCompletion {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string] $VMName,

        [Parameter(Mandatory = $true)]
        [PSCredential] $Credential,

        [Parameter(Mandatory = $false)]
        [ValidateRange(0, 3600)]
        [int] $RetryTimeoutSeconds = 600,

        [Parameter(Mandatory = $false)]
        [ValidateRange(0, 3600)]
        [int] $RetryIntervalSeconds = 10,

        [Parameter(Mandatory = $false)]
        [ValidateRange(0, 3600)]
        [int] $LoggingIntervalSeconds = 60
    )

    # NOTE: The ImageCustomizationScheduledTask task will disabled after the task has been completed.
    $startTime = Get-Date
    $endTime = $startTime.AddSeconds($RetryTimeoutSeconds)
    while ((Get-Date) -lt $endTime) {
        try {
            $params = @{
                VMName      = $VMName
                Credential  = $Credential
                ScriptBlock = {
                    $task = Get-ScheduledTask -TaskName 'ImageCustomizationScheduledTask'
                    $task.State -eq 'Disabled'
                }
                ErrorAction = [Management.Automation.ActionPreference]::Stop
            }
            if ((Invoke-Command @params)) {
                'The ImageCustomizationScheduledTask task has been completed.' | Write-ScriptLog
                return
            }
        }
        catch {
            '{0} (ExceptionMessage: {1} | Exception: {2} | FullyQualifiedErrorId: {3} | CategoryInfo: {4} | ErrorDetailsMessage: {5})' -f @(
                'Checking the ImageCustomizationScheduledTask task completion...',
                $_.Exception.Message,
                $_.Exception.GetType().FullName,
                $_.FullyQualifiedErrorId,
                $_.CategoryInfo.ToString(),
                $_.ErrorDetails.Message
            ) | Write-ScriptLog -Level Warning
        }

        Start-Sleep -Seconds $RetryIntervalSeconds
        $elapsedSeconds = [int] ((Get-Date) - $startTime).TotalSeconds
        if (($elapsedSeconds % $LoggingIntervalSeconds) -eq 0) {
            Write-Host ('{0} seconds elapsed.' -f $elapsedSeconds)
        }
    }

    throw 'The ImageCustomizationScheduledTask task did not complete in {0} seconds.' -f $RetryTimeoutSeconds
}

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

    # Retrieve the admin password from the Key Vault.
    $adminPassword = Get-Secret -KeyVaultName $labConfig.keyVault.name -SecretName $labConfig.keyVault.secretName.adminPassword

    # Hyper-V VM configuration.
    $labNodeConfig = $labConfig.hciNode
    $vmConfig = [PSCustomObject] @{
        VMName         = Format-HciNodeName -Format $labNodeConfig.vmName -Offset $labNodeConfig.vmNameOffset -Index $jobParams.NodeIndex
        ProcessorCount = Get-HciNodeProcessorCount -NodeCount $labNodeConfig.nodeCount
        RamBytes       = Get-HciNodeRamSize -NodeCount $labNodeConfig.nodeCount -AddsDcVMRamBytes $labConfig.addsDC.maximumRamBytes -WacVMRamBytes $labConfig.wac.maximumRamBytes
        ParentVhdPath  = $jobParams.BaseVhdFilePath
        DataDisk       = [PSCustomObject] @{
            Count     = 8
            SizeBytes = $labNodeConfig.dataDiskSizeBytes
        }
        OS = [PSCustomObject] @{
            Sku        = $labNodeConfig.operatingSystem.sku
            ImageIndex = $labNodeConfig.operatingSystem.imageIndex
            Language   = $labConfig.guestOS.culture
            TimeZone   = $labConfig.guestOS.timeZone
        }
        NetAdapters = [PSCustomObject] @{
            Management = [PSCustomObject] @{
                Name               = $labNodeConfig.netAdapters.management.name
                VSwitchName        = $labConfig.labHost.vSwitch.nat.name
                IPAddress          = $labNodeConfig.netAdapters.management.ipAddress -f ($labNodeConfig.ipAddressOffset + $jobParams.NodeIndex)
                PrefixLength       = $labNodeConfig.netAdapters.management.prefixLength
                DefaultGateway     = $labNodeConfig.netAdapters.management.defaultGateway
                DnsServerAddresses = $labNodeConfig.netAdapters.management.dnsServerAddresses
            }
            Compute = [PSCustomObject] @{
                Name         = $labNodeConfig.netAdapters.compute.name
                VSwitchName  = $labConfig.labHost.vSwitch.nat.name
                IPAddress    = $labNodeConfig.netAdapters.compute.ipAddress -f ($labNodeConfig.ipAddressOffset + $jobParams.NodeIndex)
                PrefixLength = $labNodeConfig.netAdapters.compute.prefixLength
            }
            Storage1 = [PSCustomObject] @{
                Name         = $labNodeConfig.netAdapters.storage1.name
                VSwitchName  = $labConfig.labHost.vSwitch.nat.name
                IPAddress    = $labNodeConfig.netAdapters.storage1.ipAddress -f ($labNodeConfig.ipAddressOffset + $jobParams.NodeIndex)
                PrefixLength = $labNodeConfig.netAdapters.storage1.prefixLength
                VlanId       = $labNodeConfig.netAdapters.storage1.vlanId
            }
            Storage2 = [PSCustomObject] @{
                Name         = $labNodeConfig.netAdapters.storage2.name
                VSwitchName  = $labConfig.labHost.vSwitch.nat.name
                IPAddress    = $labNodeConfig.netAdapters.storage2.ipAddress -f ($labNodeConfig.ipAddressOffset + $jobParams.NodeIndex)
                PrefixLength = $labNodeConfig.netAdapters.storage2.prefixLength
                VlanId       = $labNodeConfig.netAdapters.storage2.vlanId
            }
        }
    }
    'Hyper-V VM config: {0}' -f ($vmConfig | ConvertTo-Json -Depth 16) | Write-ScriptLog

    #
    # Hyper-V VM creation
    #

    # Create a new Hyper-V VM.
    $hvVMInfo = New-HypervVM -VMConfig $vmConfig -VMFolderPath $labConfig.labHost.folderPath.vm

    'Generate the unattend answer XML.'| Write-ScriptLog
    $params = @{
        ComputerName = $vmConfig.VMName
        Password     = $adminPassword
        Culture      = $vmConfig.OS.Language
        TimeZone     = $vmConfig.OS.TimeZone
    }
    $unattendAnswerFileContent = New-UnattendAnswerFileContent @params
    'Generate the unattend answer XML has been completed.'| Write-ScriptLog

    'Inject the unattend answer file to the VHD.' | Write-ScriptLog
    $params = @{
        VhdPath                   = $hvVMInfo.OSDiskVhdFilePath
        UnattendAnswerFileContent = $unattendAnswerFileContent
        LogFolder                 = $labConfig.labHost.folderPath.log
    }
    Set-UnattendAnswerFileToVhd @params
    'Inject the unattend answer file to the VHD has been completed.' | Write-ScriptLog

    'Install the roles and features to the VHD.' | Write-ScriptLog
    $params = @{
        VhdPath     = $hvVMInfo.OSDiskVhdFilePath
        FeatureName = Get-WindowsFeatureToInstall -HciNodeOperatingSystemSku $vmConfig.OS.Sku
        LogFolder   = $labConfig.labHost.folderPath.log
    }
    Install-WindowsFeatureToVhd @params
    'Install the roles and features to the VHD has been completed.' | Write-ScriptLog

    Start-VMSurely -VMName $vmConfig.VMName

    # Credentials
    $localAdminCredential = New-LogonCredential -DomainFqdn '.' -Password $adminPassword
    $domainAdminCredential = New-LogonCredential -DomainFqdn $labConfig.addsDomain.fqdn -Password $adminPassword

    # NOTE: The VM automatically restarts at some point between after the VM started and before PowerShell Direct is ready.
    'Wait for PowerShell Direct to be ready.' | Write-ScriptLog
    Wait-PowerShellDirectReady -VMName $vmConfig.VMName -Credential $localAdminCredential
    'PowerShell Direct is ready.' | Write-ScriptLog

    if ($labNodeConfig.isAzureLocalDeployment) {
        'Wait for the Bootstrap services to be available.' | Write-ScriptLog
        Wait-BootstrapServices -VMName $vmConfig.VMName -Credential $localAdminCredential
        'The Bootstrap services are available.' | Write-ScriptLog

        # NOTE: The VM automatically restarts at some point after the Bootstrap services are available.
        'A buffer time to wait for the VM to start restarting.' | Write-ScriptLog
        Start-Sleep -Seconds 60

        'Wait for PowerShell Direct to be ready.' | Write-ScriptLog
        Wait-PowerShellDirectReady -VMName $vmConfig.VMName -Credential $localAdminCredential
        'PowerShell Direct is ready.' | Write-ScriptLog
    }

    #
    # Guest OS configuration
    #

    'Copy the module files into the VM.' | Write-ScriptLog
    $params = @{
        VMName              = $vmConfig.VMName
        Credential          = $localAdminCredential
        SourceFilePath      = (Get-Module -Name 'common').Path
        DestinationPathInVM = 'C:\Windows\Temp'
    }
    $moduleFilePathsWithinVM = Copy-FileIntoVM @params
    'Copy the module files into the VM has been completed.' | Write-ScriptLog

    # The common parameters for Invoke-CommandWithinVM.
    $invokeWithinVMParams = @{
        VMName           = $vmConfig.VMName
        Credential       = $localAdminCredential
        ImportModuleInVM = $moduleFilePathsWithinVM
    }

    # If the HCI node OS is Windows Server with Desktop Experience.
    $wsOS = @(
        [HciLab.OSSku]::WindowsServer2022,
        [HciLab.OSSku]::WindowsServer2025
    )
    if (($vmConfig.OS.ImageIndex -eq [HciLab.OSImageIndex]::WSDatacenterDesktopExperience) -and ($vmConfig.OS.Sku -in $wsOS)) {
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

            'Hide the first run experience of Microsoft Edge.' | Write-ScriptLog
            New-RegistryKey -ParentPath 'HKLM:\SOFTWARE\Policies\Microsoft' -KeyName 'Edge'
            Set-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' -Name 'HideFirstRunExperience' -Value 1
            'Hide the first run experience of Microsoft Edge has been completed.' | Write-ScriptLog
        }
        'Configure registry values within the VM has been completed.' | Write-ScriptLog
    }

    'Rename the network adapters.' | Write-ScriptLog
    Invoke-CommandWithinVM @invokeWithinVMParams -WithRetry -ScriptBlock {
        Get-NetAdapterAdvancedProperty -RegistryKeyword 'HyperVNetworkAdapterName' | ForEach-Object -Process {
            Rename-NetAdapter -Name $_.Name -NewName $_.DisplayValue
        }
    }
    'Rename the network adapters has been completed.' | Write-ScriptLog

    # Management
    $netAdapterConfig = $vmConfig.NetAdapters.Management
    'Configure the IP & DNS on the "{0}" network adapter.' -f $netAdapterConfig.Name | Write-ScriptLog
    Invoke-CommandWithinVM @invokeWithinVMParams -WithRetry -ScriptBlockParamList $netAdapterConfig -ScriptBlock {
        param (
            [Parameter(Mandatory = $true)]
            [PSCustomObject] $NetAdapterConfig
        )

        # Remove default route.
        Get-NetAdapter -Name $NetAdapterConfig.Name |
        Get-NetIPInterface -AddressFamily 'IPv4' |
        Remove-NetRoute -DestinationPrefix '0.0.0.0/0' -Confirm:$false -ErrorAction SilentlyContinue

        # Remove existing NetIPAddresses.
        Get-NetAdapter -Name $NetAdapterConfig.Name |
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
            IPAddress      = $NetAdapterConfig.IPAddress
            PrefixLength   = $NetAdapterConfig.PrefixLength
            DefaultGateway = $NetAdapterConfig.DefaultGateway
        }
        $paramsForSetDnsClientServerAddress = @{
            ServerAddresses = $NetAdapterConfig.DnsServerAddresses
        }
        Get-NetAdapter -Name $NetAdapterConfig.Name |
        Set-NetIPInterface @paramsForSetNetIPInterface |
        New-NetIPAddress @paramsForNewIPAddress |
        Set-DnsClientServerAddress @paramsForSetDnsClientServerAddress |
        Out-Null
    }
    'Configure the IP & DNS on the "{0}" network adapter has been completed.' -f $netAdapterConfig.Name | Write-ScriptLog

    # Compute
    $netAdapterConfig = $vmConfig.NetAdapters.Compute
    'Configure the IP & DNS on the "{0}" network adapter.' -f $netAdapterConfig.Name | Write-ScriptLog
    Invoke-CommandWithinVM @invokeWithinVMParams -WithRetry -ScriptBlockParamList $netAdapterConfig -ScriptBlock {
        param (
            [Parameter(Mandatory = $true)]
            [PSCustomObject] $NetAdapterConfig
        )

        # Remove existing NetIPAddresses.
        Get-NetAdapter -Name $NetAdapterConfig.Name |
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
            IPAddress      = $NetAdapterConfig.IPAddress
            PrefixLength   = $NetAdapterConfig.PrefixLength
        }
        Get-NetAdapter -Name $NetAdapterConfig.Name |
        Set-NetIPInterface @paramsForSetNetIPInterface |
        New-NetIPAddress @paramsForNewIPAddress |
        Out-Null
    }
    'Configure the IP & DNS on the "{0}" network adapter has been completed.' -f $netAdapterConfig.Name | Write-ScriptLog

    if ($labNodeConfig.isAzureLocalDeployment) {
        # NOTE: The storage network configuration is not needed for Azure Local deployment. It will configure during the Azure Local deployment process.
        'Skip the storage network configuration because the deployment is Azure Local deployment.' | Write-ScriptLog
    }
    else {
        # Storage 1
        $netAdapterConfig = $vmConfig.NetAdapters.Storage1
        'Configure the IP & DNS on the "{0}" network adapter.' -f $netAdapterConfig.Name | Write-ScriptLog
        Invoke-CommandWithinVM @invokeWithinVMParams -WithRetry -ScriptBlockParamList $netAdapterConfig -ScriptBlock {
            param (
                [Parameter(Mandatory = $true)]
                [PSCustomObject] $NetAdapterConfig
            )

            # Remove existing NetIPAddresses.
            Get-NetAdapter -Name $NetAdapterConfig.Name |
            Get-NetIPInterface -AddressFamily 'IPv4' |
            Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue

            # Configure the IP, DNS and VLAN on the network adapter.
            $paramsForSetNetAdapter = @{
                VlanID   = $NetAdapterConfig.VlanId
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
                IPAddress     = $NetAdapterConfig.IPAddress
                PrefixLength  = $NetAdapterConfig.PrefixLength
            }
            Get-NetAdapter -Name $NetAdapterConfig.Name |
            Set-NetAdapter @paramsForSetNetAdapter |
            Set-NetIPInterface @paramsForSetNetIPInterface |
            New-NetIPAddress @paramsForNewIPAddress |
            Out-Null
        }
        'Configure the IP & DNS on the "{0}" network adapter has been completed.' -f $netAdapterConfig.Name | Write-ScriptLog

        # Storage 2
        $netAdapterConfig = $vmConfig.NetAdapters.Storage2
        'Configure the IP & DNS on the "{0}" network adapter.' -f $netAdapterConfig.Name | Write-ScriptLog
        Invoke-CommandWithinVM @invokeWithinVMParams -WithRetry -ScriptBlockParamList $netAdapterConfig -ScriptBlock {
            param (
                [Parameter(Mandatory = $true)]
                [PSCustomObject] $NetAdapterConfig
            )

            # Remove existing NetIPAddresses.
            Get-NetAdapter -Name $NetAdapterConfig.Name |
            Get-NetIPInterface -AddressFamily 'IPv4' |
            Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue

            # Configure the IP, DNS and VLAN on the network adapter.
            $paramsForSetNetAdapter = @{
                VlanID   = $NetAdapterConfig.VlanId
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
                IPAddress     = $NetAdapterConfig.IPAddress
                PrefixLength  = $NetAdapterConfig.PrefixLength
            }
            Get-NetAdapter -Name $NetAdapterConfig.Name |
            Set-NetAdapter @paramsForSetNetAdapter |
            Set-NetIPInterface @paramsForSetNetIPInterface |
            New-NetIPAddress @paramsForNewIPAddress |
            Out-Null
        }
        'Configure the IP & DNS on the "{0}" network adapter has been completed.' -f $netAdapterConfig.Name | Write-ScriptLog
    }

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

    # We need to wait for the domain controller VM deployment completion before update the NuGet package provider and the PowerShellGet module.
    'Wait for the domain controller VM deployment completion.' | Write-ScriptLog
    Wait-AddsDcDeploymentCompletion
    'The domain controller VM deployment has been completed.' | Write-ScriptLog

    'Wait for the domain controller with DNS capability to be ready.' | Write-ScriptLog
    $params = @{
        AddsDcVMName       = $labConfig.addsDC.vmName
        AddsDcComputerName = $labConfig.addsDC.vmName  # The DC's computer name is the same as the VM name. It's specified in the unattend.xml.
        Credential         = $domainAdminCredential
    }
    Wait-DomainControllerServiceReady @params
    'The domain controller with DNS capability is ready.' | Write-ScriptLog

    # NOTE: The package provider installation needs internet connection and name resolution.
    'Install the NuGet package provider within the VM.' | Write-ScriptLog
    Invoke-CommandWithinVM @invokeWithinVMParams -WithRetry -ScriptBlock {
        Install-PackageProvider -Name 'NuGet' -Scope 'AllUsers' -Force -Verbose | Out-String -Width 200 | Write-ScriptLog
        Get-PackageProvider -Name 'NuGet' -ListAvailable -Force | Out-String -Width 200 | Write-ScriptLog
    }
    'Install the NuGet package provider within the VM has been completed.' | Write-ScriptLog

    # NOTE: The PowerShellGet module installation needs internet connection and name resolution.
    'Install the PowerShellGet module within the VM.' | Write-ScriptLog
    Invoke-CommandWithinVM @invokeWithinVMParams -WithRetry -ScriptBlock {
        Install-Module -Name 'PowerShellGet' -Scope 'AllUsers' -Force -Verbose
        Get-Module -Name 'PowerShellGet' -ListAvailable | Out-String -Width 200 | Write-ScriptLog
    }
    'Install the PowerShellGet module within the VM has been completed.' | Write-ScriptLog

    # The following Azure Local versions have the ImageCustomizationScheduledTask task.
    $osVersionsShouldInvokeScheduledTask = @(
        [HciLab.OSSku]::AzureLocal24H2_2509,
        [HciLab.OSSku]::AzureLocal24H2_2508,
        [HciLab.OSSku]::AzureLocal24H2_2507,
        [HciLab.OSSku]::AzureLocal24H2_2506,
        [HciLab.OSSku]::AzureLocal24H2_2505,
        [HciLab.OSSku]::AzureLocal24H2_2504
    )
    if ($labNodeConfig.isAzureLocalDeployment -and $vmConfig.OS.Sku -in $osVersionsShouldInvokeScheduledTask) {
        'Invoke the Azure Local scheduled task.' | Write-ScriptLog
        Invoke-AzureLocalScheduledTask -VMName $vmConfig.VMName -Credential $invokeWithinVMParams.Credential

        'Wait for the Azure Local scheduled task to be completed.' | Write-ScriptLog
        Wait-AzureLocalScheduledTaskCompletion -VMName $vmConfig.VMName -Credential $invokeWithinVMParams.Credential
        'The Azure Local scheduled task is has been completed.' | Write-ScriptLog
    }
    else {
        'Skip the Azure Local scheduled task invocation because {0} does not have the scheduled task.' -f $vmConfig.OS.Sku | Write-ScriptLog
    }

    'Delete the module files within the VM.' | Write-ScriptLog
    $params = @{
        VMName               = $invokeWithinVMParams.VMName
        Credential           = $invokeWithinVMParams.Credential
        FilePathToRemoveInVM = $invokeWithinVMParams.ImportModuleInVM
        ImportModuleInVM     = $invokeWithinVMParams.ImportModuleInVM
    }
    Remove-FileWithinVM @params
    'Delete the module files within the VM has been completed.' | Write-ScriptLog

    # Disable the Time synchronization in the Integration Services.
    # - Use AD DC as the NTP server for member servers are a common practice.
    # - The Azure Local instance deployment validator will check the NTP settings and connectivity to the NTP server.
    #   The check will fail if the source is "VM IC Time Synchronization Provider".
    if ($labNodeConfig.shouldJoinToAddsDomain -or $labNodeConfig.isAzureLocalDeployment) {
        Disable-VMIntegrationService -VMName $vmConfig.VMName -Name 'Time Synchronization' -Passthru | Out-String | Write-ScriptLog
    }

    if ($labNodeConfig.shouldJoinToAddsDomain) {
        'Join the VM to the AD domain.'  | Write-ScriptLog
        $params = @{
            VMName                = $vmConfig.VMName
            LocalAdminCredential  = $localAdminCredential
            DomainFqdn            = $labConfig.addsDomain.fqdn
            DomainAdminCredential = $domainAdminCredential
        }
        Add-VMToADDomain @params
        'Join the VM to the AD domain has been completed.'  | Write-ScriptLog
    }

    # Restart the VM.
    Stop-VMSurely -VMName $vmConfig.VMName
    Start-VMSurely -VMName $vmConfig.VMName

    'Wait for the VM to be ready.' | Write-ScriptLog
    $params = @{
        VMName     = $vmConfig.VMName
        Credential = if ($labNodeConfig.shouldJoinToAddsDomain) { $domainAdminCredential } else { $localAdminCredential }
    }
    Wait-PowerShellDirectReady @params
    'The VM is ready.' | Write-ScriptLog

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
