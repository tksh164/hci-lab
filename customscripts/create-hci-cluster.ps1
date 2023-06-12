[CmdletBinding()]
param ()

$ErrorActionPreference = [Management.Automation.ActionPreference]::Stop
$WarningPreference = [Management.Automation.ActionPreference]::Continue
$VerbosePreference = [Management.Automation.ActionPreference]::Continue
$ProgressPreference = [Management.Automation.ActionPreference]::SilentlyContinue

Import-Module -Name ([IO.Path]::Combine($PSScriptRoot, 'shared.psm1')) -Force

$labConfig = Get-LabDeploymentConfig
Start-ScriptLogging -OutputDirectory $labConfig.labHost.folderPath.log
$labConfig | ConvertTo-Json -Depth 16 | Write-Host

$nodeNames = @()
$nodeNames += for ($nodeIndex = 0; $nodeIndex -lt $labConfig.hciNode.nodeCount; $nodeIndex++) {
    Format-HciNodeName -Format $labConfig.hciNode.vmName -Offset $labConfig.hciNode.vmNameOffset -Index $nodeIndex
}

$adminPassword = Get-Secret -KeyVaultName $labConfig.keyVault.name -SecretName $labConfig.keyVault.secretName.adminPassword
$domainCredential = New-LogonCredential -DomainFqdn $labConfig.addsDomain.fqdn -Password $adminPassword

'Create PowerShell Direct session for the HCI nodes...' | Write-ScriptLog -Context $env:ComputerName
$hciNodeDomainAdminCredPSSessions = @()
foreach ($nodeName in $nodeNames) {
    $hciNodeDomainAdminCredPSSessions += New-PSSession -VMName $nodeName -Credential $domainCredential
}
$hciNodeDomainAdminCredPSSessions |
    Format-Table -Property 'Id', 'Name', 'ComputerName', 'ComputerType', 'State', 'Availability' |
    Out-String |
    Write-ScriptLog -Context $env:ComputerName

'Copying the shared module file into the HCI nodes...' | Write-ScriptLog -Context $env:ComputerName
foreach ($domainAdminCredPSSession in $hciNodeDomainAdminCredPSSessions) {
    $sharedModuleFilePathInVM = Copy-PSModuleIntoVM -Session $domainAdminCredPSSession -ModuleFilePathToCopy (Get-Module -Name 'shared').Path
}

'Setup the PowerShell Direct session for the HCI nodes...' | Write-ScriptLog -Context $env:ComputerName
Invoke-PSDirectSessionSetup -Session $hciNodeDomainAdminCredPSSessions -SharedModuleFilePathInVM $sharedModuleFilePathInVM

'Creating virtual switches on each HCI node...' | Write-ScriptLog -Context $env:ComputerName -UseInScriptBlock
$params = @{
    InputObject = [PSCustomObject] @{
        NetAdapterName = [PSCustomObject] @{
            Management = $labConfig.hciNode.netAdapter.management.name
            Compute    = $labConfig.hciNode.netAdapter.compute.name
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
    }
    New-VMSwitch @params

    # External vSwitch for the compute network.
    $params = @{
        Name                  = '{0}Switch' -f $NetAdapterName.Compute
        NetAdapterName        = $NetAdapterName.Compute
        AllowManagementOS     = $false
        EnableEmbeddedTeaming = $true
    }
    New-VMSwitch @params
} |
    Sort-Object -Property 'PSComputerName' |
    Format-Table -Property 'PSComputerName', 'Name', 'SwitchType', 'AllowManagementOS', 'EmbeddedTeamingEnabled' |
    Out-String |
    Write-ScriptLog -Context $env:ComputerName

'Preparing HCI node''s drives...' | Write-ScriptLog -Context $env:ComputerName
Invoke-Command -Session $hciNodeDomainAdminCredPSSessions -ScriptBlock {
    # Updates the cache of the service for a particular provider and associated child objects.
    Update-StorageProviderCache

    # Disable read-only state of storage pools except the Primordial pool.
    Get-StoragePool | Where-Object -Property 'IsPrimordial' -EQ -Value $false | Set-StoragePool -IsReadOnly:$false

    # Delete virtual disks in storage pools except the Primordial pool.
    Get-StoragePool | Where-Object -Property 'IsPrimordial' -EQ -Value $false | Get-VirtualDisk | Remove-VirtualDisk -Confirm:$false -ErrorAction Continue

    # Delete storage pools except the Primordial pool.
    Get-StoragePool | Where-Object -Property 'IsPrimordial' -EQ -Value $false | Remove-StoragePool -Confirm:$false

    # Reset the status of a physical disks. (Delete the storage pool's metadata from physical disks)
    Get-PhysicalDisk | Reset-PhysicalDisk

    # Cleans disks by removing all partition information and un-initializing it, erasing all data on the disks.
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
    Write-ScriptLog -Context $env:ComputerName

'Cleaning up the PowerShell Direct session for the HCI nodes...' | Write-ScriptLog -Context $env:ComputerName
Invoke-PSDirectSessionCleanup -Session $hciNodeDomainAdminCredPSSessions -SharedModuleFilePathInVM $sharedModuleFilePathInVM

'Create PowerShell Direct sessions for the management machine...' | Write-ScriptLog -Context $env:ComputerName
$wacDomainAdminCredPSSession = New-PSSession -VMName $labConfig.wac.vmName -Credential $domainCredential
$wacDomainAdminCredPSSession |
    Format-Table -Property 'Id', 'Name', 'ComputerName', 'ComputerType', 'State', 'Availability' |
    Out-String |
    Write-ScriptLog -Context $env:ComputerName

'Copying the shared module file into the management machine...' | Write-ScriptLog -Context $env:ComputerName
$sharedModuleFilePathInVM = Copy-PSModuleIntoVM -Session $wacDomainAdminCredPSSession -ModuleFilePathToCopy (Get-Module -Name 'shared').Path

'Setup the PowerShell Direct session for the management machine...' | Write-ScriptLog -Context $env:ComputerName
Invoke-PSDirectSessionSetup -Session $wacDomainAdminCredPSSession -SharedModuleFilePathInVM $sharedModuleFilePathInVM

'Getting the node''s UI culture...' | Write-ScriptLog -Context $env:ComputerName
$langTag = Invoke-Command -Session $wacDomainAdminCredPSSession -ScriptBlock {
    (Get-UICulture).IetfLanguageTag
}
'The node''s UI culture is "{0}".' -f $langTag | Write-ScriptLog -Context $env:ComputerName

$localizedDataFileName = ('create-hci-cluster-test-cat-{0}.psd1' -f $langTag).ToLower()
'Localized data file name: {0}' -f $localizedDataFileName | Write-ScriptLog -Context $env:ComputerName
Import-LocalizedData -FileName $localizedDataFileName -BindingVariable 'clusterTestCategories'

'Testing the HCI cluster nodes...' | Write-ScriptLog -Context $env:ComputerName
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
} | Out-String | Write-ScriptLog -Context $env:ComputerName

'Creating an HCI cluster...' | Write-ScriptLog -Context $env:ComputerName
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
} | Out-String | Write-ScriptLog -Context $env:ComputerName

'Waiting for the cluster to be ready...' | Write-ScriptLog -Context $env:ComputerName
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
            (
                'Probing the cluster ready state... ' +
                '(ExceptionMessage: {0} | Exception: {1} | FullyQualifiedErrorId: {2} | CategoryInfo: {3} | ErrorDetailsMessage: {4})'
            ) -f @(
                $_.Exception.Message, $_.Exception.GetType().FullName, $_.FullyQualifiedErrorId, $_.CategoryInfo.ToString(), $_.ErrorDetails.Message
            ) | Write-Host
        }
        Start-Sleep -Seconds $RetryIntervalSeconds
    }
    throw 'The cluster was not ready in the acceptable time ({0}).' -f $RetyTimeout.ToString()
} | Out-String | Write-ScriptLog -Context $env:ComputerName

'Configuring the cluster quorum...' | Write-ScriptLog -Context $env:ComputerName
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
} | Out-String | Write-ScriptLog -Context $env:ComputerName

'Enabling Storage Space Direct (S2D)...' | Write-ScriptLog -Context $env:ComputerName
$params = @{
    InputObject = [PSCustomObject] @{
        HciNodeName     = $nodeNames[0]
        StoragePoolName = 'hcilab-s2d-storage-pool'
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

    Get-CimSession | Remove-CimSession
} | Out-String | Write-ScriptLog -Context $env:ComputerName

'Creating a volume on S2D...' | Write-ScriptLog -Context $env:ComputerName
$params = @{
    InputObject = [PSCustomObject] @{
        HciNodeName     = $nodeNames[0]
        VolumeName      = 'HciVol'
        StoragePoolName = 'hcilab-s2d-storage-pool'
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

    Get-CimSession | Remove-CimSession
} | Out-String | Write-ScriptLog -Context $env:ComputerName

'Cleaning up the PowerShell Direct session for the management machine...' | Write-ScriptLog -Context $env:ComputerName
Invoke-PSDirectSessionCleanup -Session $wacDomainAdminCredPSSession -SharedModuleFilePathInVM $sharedModuleFilePathInVM

'The HCI cluster creation has been completed.' | Write-ScriptLog -Context $env:ComputerName

Stop-ScriptLogging
