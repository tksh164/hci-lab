[CmdletBinding()]
param ()

$ErrorActionPreference = [Management.Automation.ActionPreference]::Stop
$WarningPreference = [Management.Automation.ActionPreference]::Continue
$VerbosePreference = [Management.Automation.ActionPreference]::Continue
$ProgressPreference = [Management.Automation.ActionPreference]::SilentlyContinue

try {
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    Import-Module -Name ([IO.Path]::Combine($PSScriptRoot, 'common.psm1')) -Force

    $labConfig = Get-LabDeploymentConfig
    Start-ScriptLogging -OutputDirectory $labConfig.labHost.folderPath.log
    'Lab deployment config:' | Write-ScriptLog
    $labConfig | ConvertTo-Json -Depth 16 | Write-Host

    $nodeNames = @()
    $nodeNames += for ($nodeIndex = 0; $nodeIndex -lt $labConfig.hciNode.nodeCount; $nodeIndex++) {
        Format-HciNodeName -Format $labConfig.hciNode.vmName -Offset $labConfig.hciNode.vmNameOffset -Index $nodeIndex
    }

    $adminPassword = Get-Secret -KeyVaultName $labConfig.keyVault.name -SecretName $labConfig.keyVault.secretName.adminPassword
    $domainCredential = New-LogonCredential -DomainFqdn $labConfig.addsDomain.fqdn -Password $adminPassword

    #
    # Doing on the HCI nodes
    #

    $invokeWithinVMParamsArray = @()
    $invokeWithinVMParamsArray += foreach ($nodeName in $nodeNames) {
        'Copy the module files into the HCI node "{0}".' -f $nodeName | Write-ScriptLog
        $params = @{
            VMName              = $nodeName
            Credential          = $domainCredential
            SourceFilePath      = (Get-Module -Name 'common').Path
            DestinationPathInVM = 'C:\Windows\Temp'
        }
        $moduleFilePathsWithinVM = Copy-FileIntoVM @params
        'Copy the module files into the HCI node "{0}" completed.' -f $nodeName | Write-ScriptLog

        # The common parameters for Invoke-CommandWithinVM.
        @{
            VMName           = $nodeName
            Credential       = $domainCredential
            ImportModuleInVM = $moduleFilePathsWithinVM
        }
    }

    # Create virtual switches on each HCI node.
    foreach ($invokeWithinVMParams in  $invokeWithinVMParamsArray) {
        'Create virtual switches on the HCI node "{0}".' -f $invokeWithinVMParams.VMName | Write-ScriptLog
        $netAdapterName = [PSCustomObject] @{
            Management = $labConfig.hciNode.netAdapters.management.name
            Compute    = $labConfig.hciNode.netAdapters.compute.name
        }
        Invoke-CommandWithinVM @invokeWithinVMParams -ScriptBlockParamList $netAdapterName -ScriptBlock {
            param (
                [Parameter(Mandatory = $true)]
                [PSCustomObject] $NetAdapterName
            )
    
            # External vSwitch for the management network.
            $params = @{
                Name                  = '{0}Switch' -f $NetAdapterName.Management
                NetAdapterName        = $NetAdapterName.Management
                AllowManagementOS     = $true
                EnableEmbeddedTeaming = $true
                MinimumBandwidthMode  = 'Weight'
            }
            New-VMSwitch @params
    
            # External vSwitch for the compute network.
            $params = @{
                Name                  = '{0}Switch' -f $NetAdapterName.Compute
                NetAdapterName        = $NetAdapterName.Compute
                AllowManagementOS     = $false
                EnableEmbeddedTeaming = $true
                MinimumBandwidthMode  = 'Weight'
            }
            New-VMSwitch @params
        } |
            Sort-Object -Property 'PSComputerName' |
            Format-Table -Property 'PSComputerName', 'Name', 'SwitchType', 'AllowManagementOS', 'EmbeddedTeamingEnabled' |
            Out-String |
            Write-ScriptLog

        'Create virtual switches on the HCI node "{0}" completed.' -f $invokeWithinVMParams.VMName | Write-ScriptLog
    }

    # Prepare drives on HCI nodes.
    foreach ($invokeWithinVMParams in  $invokeWithinVMParamsArray) {
        'Prepare drives on the HCI node "{0}".' -f $invokeWithinVMParams.VMName | Write-ScriptLog
        Invoke-CommandWithinVM @invokeWithinVMParams -ScriptBlock {
            # Updates the cache of the service for a particular provider and associated child objects.
            'Update the storage provider cache.' | Write-ScriptLog
            Update-StorageProviderCache
            'Update the storage provider cache completed.' | Write-ScriptLog
    
            # Disable read-only state of storage pools except the Primordial pool.
            'Disable read-only state of the storage pool.' | Write-ScriptLog
            Get-StoragePool | Where-Object -Property 'IsPrimordial' -EQ -Value $false | Set-StoragePool -IsReadOnly:$false
            'Disable read-only state of the storage pool completed.' | Write-ScriptLog
    
            # Delete virtual disks in storage pools except the Primordial pool.
            'Delete virtual disks in the storage pool.' | Write-ScriptLog
            Get-StoragePool | Where-Object -Property 'IsPrimordial' -EQ -Value $false | Get-VirtualDisk | Remove-VirtualDisk -Confirm:$false -ErrorAction Continue
            'Delete virtual disks in the storage pool completed.' | Write-ScriptLog
    
            # Delete storage pools except the Primordial pool.
            'Delete the storage pool.' | Write-ScriptLog
            Get-StoragePool | Where-Object -Property 'IsPrimordial' -EQ -Value $false | Remove-StoragePool -Confirm:$false
            'Delete the storage pool completed.' | Write-ScriptLog
    
            # Reset the status of physical disks. (Delete the storage pool's metadata from physical disks)
            'Delete the storage pool''s metadata from physical disks.' | Write-ScriptLog
            Get-PhysicalDisk | Reset-PhysicalDisk
            'Delete the storage pool''s metadata from physical disks completed.' | Write-ScriptLog
    
            # Cleans disks by removing all partition information and un-initializing it, erasing all data on the disks.
            'Erase all data on the disks.' | Write-ScriptLog
            Get-Disk |
                Where-Object -Property 'Number' -NE $null |
                Where-Object -Property 'IsBoot' -NE $true |
                Where-Object -Property 'IsSystem' -NE $true |
                Where-Object -Property 'PartitionStyle' -NE 'RAW' |
                ForEach-Object -Process {
                    $_ | Set-Disk -IsOffline:$false
                    $_ | Set-Disk -IsReadOnly:$false
                    $_ | Clear-Disk -RemoveData -RemoveOEM -Confirm:$false
                    $_ | Set-Disk -IsReadOnly:$true
                    $_ | Set-Disk -IsOffline:$true
                }
            'Erase all data on the disks completed.' | Write-ScriptLog
    
            Get-Disk |
                Where-Object -Property 'Number' -NE $null |
                Where-Object -Property 'IsBoot' -NE $true |
                Where-Object -Property 'IsSystem' -NE $true |
                Where-Object -Property 'PartitionStyle' -EQ 'RAW' |
                Group-Object -NoElement -Property 'FriendlyName' |
                Sort-Object -Property 'PSComputerName'
        } |
            Sort-Object -Property 'PSComputerName' |
            Format-Table -Property 'PSComputerName', 'Count', 'Name' |
            Out-String |
            Write-ScriptLog
        'Prepare drives on the HCI node "{0}" completed.' -f $invokeWithinVMParams.VMName | Write-ScriptLog
    }

    foreach ($invokeWithinVMParams in  $invokeWithinVMParamsArray) {
        'Delete the module files within the VM "{0}".' -f $invokeWithinVMParams.VMName | Write-ScriptLog
        $params = @{
            VMName               = $invokeWithinVMParams.VMName
            Credential           = $invokeWithinVMParams.Credential
            FilePathToRemoveInVM = $invokeWithinVMParams.ImportModuleInVM
            ImportModuleInVM     = $invokeWithinVMParams.ImportModuleInVM
        }
        Remove-FileWithinVM @params
        'Delete the module files within the VM "{0}" completed.' -f $invokeWithinVMParams.VMName | Write-ScriptLog
    }

    #
    # Doing on the management server
    #

    'Copy the module files into the VM.' | Write-ScriptLog
    $params = @{
        VMName              = $labConfig.wac.vmName
        Credential          = $domainCredential
        SourceFilePath      = (Get-Module -Name 'common').Path
        DestinationPathInVM = 'C:\Windows\Temp'
    }
    $moduleFilePathsWithinVM = Copy-FileIntoVM @params
    'Copy the module files into the VM completed.' | Write-ScriptLog

    # The common parameters for Invoke-CommandWithinVM.
    $invokeParamsMgmt = @{
        VMName           = $labConfig.wac.vmName
        Credential       = $domainCredential
        ImportModuleInVM = $moduleFilePathsWithinVM
    }

    'Get the node''s UI culture.' | Write-ScriptLog
    $langTag = Invoke-CommandWithinVM @invokeParamsMgmt -ScriptBlock {
        (Get-UICulture).IetfLanguageTag
    }
    'The node''s UI culture is "{0}".' -f $langTag | Write-ScriptLog

    $localizedDataFileName = ('create-hci-cluster-test-cat-{0}.psd1' -f $langTag).ToLower()
    'Localized data file name: {0}' -f $localizedDataFileName | Write-ScriptLog
    Import-LocalizedData -FileName $localizedDataFileName -BindingVariable 'clusterTestCategories'
    'Import the localized data completed.' | Write-ScriptLog

    'Test the HCI cluster nodes.' | Write-ScriptLog
    $scriptBlockParamList = @(
        $nodeNames,
        ([array] $clusterTestCategories.Values)
    )
    Invoke-CommandWithinVM @invokeParamsMgmt -ScriptBlockParamList $scriptBlockParamList -ScriptBlock {
        param (
            [Parameter(Mandatory = $true)]
            [string[]] $Node,

            [Parameter(Mandatory = $true)]
            [string[]] $TestCategory
        )

        $params = @{
            Node        = $Node
            Include     = $TestCategory
            Verbose     = $true
            ErrorAction = [Management.Automation.ActionPreference]::Stop
        }
        Test-Cluster @params
    } | Out-String | Write-ScriptLog
    'Test the HCI cluster nodes completed.' | Write-ScriptLog

    'Create an HCI cluster.' | Write-ScriptLog
    $scriptBlockParamList = @(
        $labConfig.hciCluster.name,
        $labConfig.hciCluster.ipAddress,
        $nodeNames
    )
    Invoke-CommandWithinVM @invokeParamsMgmt -ScriptBlockParamList $scriptBlockParamList -ScriptBlock {
        param (
            [Parameter(Mandatory = $true)]
            [string] $ClusterName,

            [Parameter(Mandatory = $true)]
            [string] $ClusterIpAddress,

            [Parameter(Mandatory = $true)]
            [string[]] $Node
        )

        $params = @{
            Name          = $ClusterName
            StaticAddress = $ClusterIpAddress
            Node          = $Node
            NoStorage     = $true
            Verbose       = $true
            ErrorAction   = [Management.Automation.ActionPreference]::Stop
        }
        New-Cluster @params
    } | Out-String | Write-ScriptLog
    'Create an HCI cluster completed.' | Write-ScriptLog

    'Wait for the HCI cluster to be ready.' | Write-ScriptLog
    Invoke-CommandWithinVM @invokeParamsMgmt -ScriptBlockParamList $labConfig.hciCluster.name -ScriptBlock {
        param (
            [Parameter(Mandatory = $true)]
            [string] $ClusterName,

            [Parameter(Mandatory = $false)]
            [ValidateRange(0, 3600)]
            [int] $RetryIntervalSeconds = 15,

            [Parameter(Mandatory = $false)]
            [TimeSpan] $RetryTimeout = (New-TimeSpan -Minutes 10)
        )

        $startTime = Get-Date
        while ((Get-Date) -lt ($startTime + $RetryTimeout)) {
            try {
                Get-Cluster -Name $ClusterName -ErrorAction Stop
                return
            }
            catch {
                '{0} (ExceptionMessage: {1} | Exception: {2} | FullyQualifiedErrorId: {3} | CategoryInfo: {4} | ErrorDetailsMessage: {5})' -f @(
                    'Probing the cluster ready state...',
                    $_.Exception.Message,
                    $_.Exception.GetType().FullName,
                    $_.FullyQualifiedErrorId,
                    $_.CategoryInfo.ToString(),
                    $_.ErrorDetails.Message
                ) | Write-ScriptLog -Level Warning
            }
            Start-Sleep -Seconds $RetryIntervalSeconds
        }

        throw 'The cluster was not ready in the acceptable time ({0}).' -f $RetryTimeout.ToString()
    } | Out-String | Write-ScriptLog
    'The HCI cluster is ready.' | Write-ScriptLog

    'Configure the cluster quorum.' | Write-ScriptLog
    $scriptBlockParamList = @(
        $labConfig.hciCluster.name,
        (Get-Secret -KeyVaultName $labConfig.keyVault.name -SecretName $labConfig.keyVault.secretName.cloudWitnessStorageAccountName -AsPlainText),
        (Get-Secret -KeyVaultName $labConfig.keyVault.name -SecretName $labConfig.keyVault.secretName.cloudWitnessStorageAccountKey -AsPlainText)
    )
    Invoke-CommandWithinVM @invokeParamsMgmt -ScriptBlockParamList $scriptBlockParamList -ScriptBlock {
        param (
            [Parameter(Mandatory = $true)]
            [string] $ClusterName,

            [Parameter(Mandatory = $true)]
            [string] $StorageAccountName,

            [Parameter(Mandatory = $true)]
            [string] $StorageAccountAccessKey
        )

        $params = @{
            Cluster      = $ClusterName
            CloudWitness = $true
            AccountName  = $StorageAccountName
            AccessKey    = $StorageAccountAccessKey
            Verbose      = $true
            ErrorAction  = [Management.Automation.ActionPreference]::Stop
        }
        Set-ClusterQuorum @params
    } | Out-String | Write-ScriptLog
    'Configure the cluster quorum completed.' | Write-ScriptLog

    'Rename the cluster network names.' | Write-ScriptLog
    $scriptBlockParamList = @(
        $labConfig.hciCluster.name,
        @(
            [PSCustomObject] @{
                Name         = $labConfig.hciNode.netAdapters.management.name
                IPAddress    = $labConfig.hciNode.netAdapters.management.ipAddress -f '0'
                PrefixLength = $labConfig.hciNode.netAdapters.management.prefixLength
            },
            [PSCustomObject] @{
                Name         = $labConfig.hciNode.netAdapters.compute.name
                IPAddress    = $labConfig.hciNode.netAdapters.compute.ipAddress -f '0'
                PrefixLength = $labConfig.hciNode.netAdapters.compute.prefixLength
            },
            [PSCustomObject] @{
                Name         = $labConfig.hciNode.netAdapters.storage1.name
                IPAddress    = $labConfig.hciNode.netAdapters.storage1.ipAddress -f '0'
                PrefixLength = $labConfig.hciNode.netAdapters.storage1.prefixLength
            },
            [PSCustomObject] @{
                Name         = $labConfig.hciNode.netAdapters.storage2.name
                IPAddress    = $labConfig.hciNode.netAdapters.storage2.ipAddress -f '0'
                PrefixLength = $labConfig.hciNode.netAdapters.storage2.prefixLength
            }
        )
    )
    Invoke-CommandWithinVM @invokeParamsMgmt -ScriptBlockParamList $scriptBlockParamList -ScriptBlock {
        param (
            [Parameter(Mandatory = $true)]
            [string] $ClusterName,
            
            [Parameter(Mandatory = $true)]
            [PSCustomObject[]] $HciNodeNetworks
        )

        $clusterNetworks = Get-ClusterNetwork -Cluster $ClusterName
        foreach ($clusterNetwork in $clusterNetworks) {
            foreach ($hciNodeNetwork in $HciNodeNetworks) {
                if (($clusterNetwork.Ipv4Addresses[0] -eq $hciNodeNetwork.IPAddress) -and ($clusterNetwork.Ipv4PrefixLengths[0] -eq $hciNodeNetwork.PrefixLength)) {
                    'Rename the cluster network to "{0}" from "{1}".' -f $hciNodeNetwork.Name, $clusterNetwork.Name | Write-ScriptLog
                    $clusterNetwork.Name = $hciNodeNetwork.Name
                    break
                }
            }
        }
    } | Out-String | Write-ScriptLog
    'Rename the cluster network names completed.' | Write-ScriptLog

    'Change the cluster network order for live migration.' | Write-ScriptLog
    $scriptBlockParamList = @(
        $labConfig.hciCluster.name,
        @(
            $labConfig.hciNode.netAdapters.storage1.name,
            $labConfig.hciNode.netAdapters.storage2.name,
            $labConfig.hciNode.netAdapters.management.name
        )
    )
    Invoke-CommandWithinVM @invokeParamsMgmt -ScriptBlockParamList $scriptBlockParamList -ScriptBlock {
        param (
            [Parameter(Mandatory = $true)]
            [string] $ClusterName,
            
            [Parameter(Mandatory = $true)]
            [string[]] $MigrationNetworkOrder
        )

        $migrationNetworkOrderValue = @()
        for ($i = 0; $i -lt $MigrationNetworkOrder.Length; $i++) {
            $migrationNetworkOrderValue += (Get-ClusterNetwork -Cluster $ClusterName -Name $MigrationNetworkOrder[$i]).Id
        }
        'Cluster network order for live migration: {0}' -f ($migrationNetworkOrderValue -join '; ') | Write-ScriptLog
        Get-ClusterResourceType -Cluster $ClusterName -Name 'Virtual Machine' |
            Set-ClusterParameter -Name 'MigrationNetworkOrder' -Value ($migrationNetworkOrderValue -join ';')
    } | Out-String | Write-ScriptLog
    'Change the cluster network order for live migration completed.' | Write-ScriptLog

    'Enable Storage Space Direct (S2D).' | Write-ScriptLog
    $storagePoolName = 'hcilab-s2d-storage-pool'
    $scriptBlockParamList = @(
        $nodeNames[0],
        $storagePoolName
    )
    Invoke-CommandWithinVM @invokeParamsMgmt -ScriptBlockParamList $scriptBlockParamList -ScriptBlock {
        param (
            [Parameter(Mandatory = $true)]
            [string] $HciNodeName,

            [Parameter(Mandatory = $true)]
            [string] $StoragePoolName
        )

        $params = @{
            CimSession       = New-CimSession -ComputerName $HciNodeName
            PoolFriendlyName = $StoragePoolName
            Confirm          = $false
            Verbose          = $true
            ErrorAction      = [Management.Automation.ActionPreference]::Stop
        }
        Enable-ClusterStorageSpacesDirect @params

        'Clean up CIM sessions.' | Write-ScriptLog
        Get-CimSession | Remove-CimSession
        'Clean up CIM sessions completed.' | Write-ScriptLog
    } | Out-String | Write-ScriptLog
    'Enable Storage Space Direct (S2D) completed.' | Write-ScriptLog

    'Create a volume on S2D.' | Write-ScriptLog
    $volumeName = 'HciVol'
    $scriptBlockParamList = @(
        $nodeNames[0],
        $volumeName,
        $storagePoolName
    )
    Invoke-CommandWithinVM @invokeParamsMgmt -ScriptBlockParamList $scriptBlockParamList -ScriptBlock {
        param (
            [Parameter(Mandatory = $true)]
            [string] $HciNodeName,

            [Parameter(Mandatory = $true)]
            [string] $VolumeName,

            [Parameter(Mandatory = $true)]
            [string] $StoragePoolName
        )

        $params = @{
            CimSession              = New-CimSession -ComputerName $HciNodeName
            FriendlyName            = $VolumeName
            StoragePoolFriendlyName = $StoragePoolName
            FileSystem              = 'CSVFS_ReFS'
            UseMaximumSize          = $true
            ProvisioningType        = 'Fixed'
            ResiliencySettingName   = 'Mirror'
            Verbose                 = $true
            ErrorAction             = [Management.Automation.ActionPreference]::Stop
        }
        New-Volume @params

        'Clean up CIM sessions.' | Write-ScriptLog
        Get-CimSession | Remove-CimSession
        'Clean up CIM sessions completed.' | Write-ScriptLog
    } | Out-String | Write-ScriptLog
    'Create a volume on S2D completed.' | Write-ScriptLog

    # Temporary comment out the WAC related code because of the WAC installation issue.
    <#
    'Import a WAC connection for the HCI cluster.' | Write-ScriptLog
    $params = @{
        InputObject = [PSCustomObject] @{
            ClusterFqdn = '{0}.{1}' -f $LabConfig.hciCluster.name, $LabConfig.addsDomain.fqdn
        }
    }
    Invoke-Command @params -Session $wacDomainAdminCredPSSession -ScriptBlock {
        param (
            [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
            [string] $ClusterFqdn
        )

        'Import the WAC connection tools PowerShell module.' | Write-ScriptLog
        $wacConnectionToolsPSModulePath = [IO.Path]::Combine($env:ProgramFiles, 'Windows Admin Center\PowerShell\Modules\ConnectionTools\ConnectionTools.psm1')
        Import-Module -Name $wacConnectionToolsPSModulePath -Force
        'Import the WAC connection tools PowerShell module completed.' | Write-ScriptLog

        'Create a connection list file to import to Windows Admin Center.' | Write-ScriptLog
        $connectionEntries = @(
            (New-WacConnectionFileEntry -Name $ClusterFqdn -Type 'msft.sme.connection-type.cluster' -Tag $ClusterFqdn)
        )
        $wacConnectionFilePathInVM = [IO.Path]::Combine('C:\Windows\Temp', 'wac-connections.txt')
        New-WacConnectionFileContent -ConnectionEntry $connectionEntries | Set-Content -LiteralPath $wacConnectionFilePathInVM -Force
        'Create a connection list file to import to Windows Admin Center completed.' | Write-ScriptLog

        'Import the HCI cluster connection to Windows Admin Center.' | Write-ScriptLog
        [Uri] $gatewayEndpointUri = 'https://{0}' -f $env:ComputerName
        Import-Connection -GatewayEndpoint $gatewayEndpointUri -FileName $wacConnectionFilePathInVM
        'Import the HCI cluster connection to Windows Admin Center completed.' | Write-ScriptLog

        'Delete the connection list file.' | Write-ScriptLog
        Remove-Item -LiteralPath $wacConnectionFilePathInVM -Force
        'Delete the connection list file completed.' | Write-ScriptLog
    } | Out-String | Write-ScriptLog
    'Import a WAC connection for the HCI cluster completed.' | Write-ScriptLog
    #>

    'Delete the module files within the VM.' | Write-ScriptLog
    $params = @{
        VMName               = $invokeParamsMgmt.VMName
        Credential           = $invokeParamsMgmt.Credential
        FilePathToRemoveInVM = $invokeParamsMgmt.ImportModuleInVM
        ImportModuleInVM     = $invokeParamsMgmt.ImportModuleInVM
    }
    Remove-FileWithinVM @params
    'Delete the module files within the VM completed.' | Write-ScriptLog

    'The HCI cluster creation has been successfully completed.' | Write-ScriptLog
}
catch {
    $exceptionMessage = New-ExceptionMessage -ErrorRecord $_
    $exceptionMessage | Write-ScriptLog -Level Error
    throw $exceptionMessage
}
finally {
    'The HCI cluster creation has been finished.' | Write-ScriptLog
    $stopWatch.Stop()
    'Duration of this script ran: {0}' -f $stopWatch.Elapsed.toString('hh\:mm\:ss') | Write-ScriptLog
    Stop-ScriptLogging
}
