[CmdletBinding()]
param ()

$ErrorActionPreference = [Management.Automation.ActionPreference]::Stop
$WarningPreference = [Management.Automation.ActionPreference]::Continue
$VerbosePreference = [Management.Automation.ActionPreference]::Continue
$ProgressPreference = [Management.Automation.ActionPreference]::SilentlyContinue

try {
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

    'Create PowerShell Direct session for the HCI nodes.' | Write-ScriptLog
    $hciNodeDomainAdminCredPSSessions = @()
    foreach ($nodeName in $nodeNames) {
        $hciNodeDomainAdminCredPSSessions += New-PSSession -VMName $nodeName -Credential $domainCredential
    }
    $hciNodeDomainAdminCredPSSessions | Format-Table -Property 'Id', 'Name', 'ComputerName', 'ComputerType', 'State', 'Availability' | Out-String | Write-ScriptLog
    'Create PowerShell Direct session for the HCI nodes completed.' | Write-ScriptLog

    'Copy the common module file into the HCI nodes.' | Write-ScriptLog
    foreach ($domainAdminCredPSSession in $hciNodeDomainAdminCredPSSessions) {
        $commonModuleFilePathInVM = Copy-PSModuleIntoVM -Session $domainAdminCredPSSession -ModuleFilePathToCopy (Get-Module -Name 'common').Path
    }
    'Copy the common module file into the HCI nodes completed.' | Write-ScriptLog

    'Setup the PowerShell Direct session for the HCI nodes.' | Write-ScriptLog
    Invoke-PSDirectSessionSetup -Session $hciNodeDomainAdminCredPSSessions -CommonModuleFilePathInVM $commonModuleFilePathInVM
    'Setup the PowerShell Direct session for the HCI nodes completed.' | Write-ScriptLog

    'Create virtual switches on each HCI node.' | Write-ScriptLog
    $params = @{
        InputObject = [PSCustomObject] @{
            NetAdapterName = [PSCustomObject] @{
                Management = $labConfig.hciNode.netAdapters.management.name
                Compute    = $labConfig.hciNode.netAdapters.compute.name
            }
        }
    }
    Invoke-Command @params -Session $hciNodeDomainAdminCredPSSessions -ScriptBlock {
        param (
            [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
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
    'Create virtual switches on each HCI node completed.' | Write-ScriptLog

    'Prepare HCI node''s drives.' | Write-ScriptLog
    Invoke-Command -Session $hciNodeDomainAdminCredPSSessions -ScriptBlock {
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
    'Prepare HCI node''s drives completed.' | Write-ScriptLog

    'Clean up the PowerShell Direct session for the HCI nodes.' | Write-ScriptLog
    Invoke-PSDirectSessionCleanup -Session $hciNodeDomainAdminCredPSSessions -CommonModuleFilePathInVM $commonModuleFilePathInVM
    'Clean up the PowerShell Direct session for the HCI nodes completed.' | Write-ScriptLog

    'Create PowerShell Direct sessions for the management server.' | Write-ScriptLog
    $wacDomainAdminCredPSSession = New-PSSession -VMName $labConfig.wac.vmName -Credential $domainCredential
    $wacDomainAdminCredPSSession |
        Format-Table -Property 'Id', 'Name', 'ComputerName', 'ComputerType', 'State', 'Availability' | Out-String | Write-ScriptLog
    'Create PowerShell Direct sessions for the management server completed.' | Write-ScriptLog

    'Copy the common module file into the management server.' | Write-ScriptLog
    $commonModuleFilePathInVM = Copy-PSModuleIntoVM -Session $wacDomainAdminCredPSSession -ModuleFilePathToCopy (Get-Module -Name 'common').Path
    'Copy the common module file into the management server completed.' | Write-ScriptLog

    'Setup the PowerShell Direct session for the management server.' | Write-ScriptLog
    Invoke-PSDirectSessionSetup -Session $wacDomainAdminCredPSSession -CommonModuleFilePathInVM $commonModuleFilePathInVM
    'Setup the PowerShell Direct session for the management server completed.' | Write-ScriptLog

    'Get the node''s UI culture.' | Write-ScriptLog
    $langTag = Invoke-Command -Session $wacDomainAdminCredPSSession -ScriptBlock {
        (Get-UICulture).IetfLanguageTag
    }
    'The node''s UI culture is "{0}".' -f $langTag | Write-ScriptLog

    $localizedDataFileName = ('create-hci-cluster-test-cat-{0}.psd1' -f $langTag).ToLower()
    'Localized data file name: {0}' -f $localizedDataFileName | Write-ScriptLog
    Import-LocalizedData -FileName $localizedDataFileName -BindingVariable 'clusterTestCategories'
    'Import the localized data completed.' | Write-ScriptLog

    'Test the HCI cluster nodes.' | Write-ScriptLog
    $params = @{
        InputObject = [PSCustomObject] @{
            Node         = $nodeNames
            TestCategory = ([array] $clusterTestCategories.Values)
        }
    }
    Invoke-Command @params -Session $wacDomainAdminCredPSSession -ScriptBlock {
        param (
            [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
            [string[]] $Node,

            [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
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
    $params = @{
        InputObject = [PSCustomObject] @{
            ClusterName      = $labConfig.hciCluster.name
            ClusterIpAddress = $labConfig.hciCluster.ipAddress
            Node             = $nodeNames
        }
    }
    Invoke-Command @params -Session $wacDomainAdminCredPSSession -ScriptBlock {
        param (
            [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
            [string] $ClusterName,

            [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
            [string] $ClusterIpAddress,

            [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
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
    $params = @{
        InputObject = [PSCustomObject] @{
            ClusterName = $labConfig.hciCluster.name
        }
    }
    Invoke-Command @params -Session $wacDomainAdminCredPSSession -ScriptBlock {
        param (
            [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
            [string] $ClusterName,

            [Parameter(Mandatory = $false)]
            [ValidateRange(0, 3600)]
            [int] $RetryIntervalSeconds = 15,

            [Parameter(Mandatory = $false)]
            [TimeSpan] $RetyTimeout = (New-TimeSpan -Minutes 10)
        )

        $startTime = Get-Date
        while ((Get-Date) -lt ($startTime + $RetyTimeout)) {
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

        $logMessage = 'The cluster was not ready in the acceptable time ({0}).' -f $RetyTimeout.ToString()
        $logMessage | Write-ScriptLog -Level Error
        throw $logMessage
    } | Out-String | Write-ScriptLog
    'The HCI cluster is ready.' | Write-ScriptLog

    'Configure the cluster quorum.' | Write-ScriptLog
    $params = @{
        InputObject = [PSCustomObject] @{
            ClusterName             = $labConfig.hciCluster.name
            StorageAccountName      = Get-Secret -KeyVaultName $labConfig.keyVault.name -SecretName $labConfig.keyVault.secretName.cloudWitnessStorageAccountName -AsPlainText
            StorageAccountAccessKey = Get-Secret -KeyVaultName $labConfig.keyVault.name -SecretName $labConfig.keyVault.secretName.cloudWitnessStorageAccountKey -AsPlainText
        }
    }
    Invoke-Command @params -Session $wacDomainAdminCredPSSession -ScriptBlock {
        param (
            [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
            [string] $ClusterName,

            [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
            [string] $StorageAccountName,

            [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
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
    $params = @{
        InputObject = [PSCustomObject] @{
            ClusterName     = $labConfig.hciCluster.name
            HciNodeNetworks = @(
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
        }
    }
    Invoke-Command @params -Session $wacDomainAdminCredPSSession -ScriptBlock {
        param (
            [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
            [string] $ClusterName,
            
            [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
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
    $params = @{
        InputObject = [PSCustomObject] @{
            ClusterName           = $labConfig.hciCluster.name
            MigrationNetworkOrder = @(
                $labConfig.hciNode.netAdapters.storage1.name,
                $labConfig.hciNode.netAdapters.storage2.name,
                $labConfig.hciNode.netAdapters.management.name
            )
        }
    }
    Invoke-Command @params -Session $wacDomainAdminCredPSSession -ScriptBlock {
        param (
            [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
            [string] $ClusterName,
            
            [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
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
    $params = @{
        InputObject = [PSCustomObject] @{
            HciNodeName     = $nodeNames[0]
            StoragePoolName = $storagePoolName
        }
    }
    Invoke-Command @params -Session $wacDomainAdminCredPSSession -ScriptBlock {
        param (
            [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
            [string] $HciNodeName,

            [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
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
    $params = @{
        InputObject = [PSCustomObject] @{
            HciNodeName     = $nodeNames[0]
            VolumeName      = $volumeName
            StoragePoolName = $storagePoolName
        }
    }
    Invoke-Command @params -Session $wacDomainAdminCredPSSession -ScriptBlock {
        param (
            [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
            [string] $HciNodeName,

            [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
            [string] $VolumeName,

            [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
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

    'Clean up the PowerShell Direct session for the management server.' | Write-ScriptLog
    Invoke-PSDirectSessionCleanup -Session $wacDomainAdminCredPSSession -CommonModuleFilePathInVM $commonModuleFilePathInVM
    'Clean up the PowerShell Direct session for the management server completed.' | Write-ScriptLog

    'The HCI cluster creation has been successfully completed.' | Write-ScriptLog
}
catch {
    $exceptionMessage = New-ExceptionMessage -ErrorRecord $_
    $exceptionMessage | Write-ScriptLog -Level Error
    throw $exceptionMessage
}
finally {
    'The HCI cluster creation has been finished.' | Write-ScriptLog
    Stop-ScriptLogging
}
