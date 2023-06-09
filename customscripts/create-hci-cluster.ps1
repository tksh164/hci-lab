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

'Create a PowerShell Direct sessions...' | Write-ScriptLog -Context $env:ComputerName
$domainAdminCredPSSessions = @()
foreach ($nodeName in $nodeNames) {
    $domainAdminCredPSSessions = New-PSSession -VMName $nodeName -Credential $domainCredential
    $domainAdminCredPSSessions += New-PSSession -VMName $nodeName -Credential $domainCredential
}

'Copying the shared module file into the VMs...' | Write-ScriptLog -Context $env:ComputerName
$sharedModuleFilePath = (Get-Module -Name 'shared').Path
$sharedModuleFilePathInVM = [IO.Path]::Combine('C:\Windows\Temp', [IO.Path]::GetFileName($sharedModuleFilePath))
foreach ($domainAdminCredPSSession in $domainAdminCredPSSessions) {
    Copy-Item -ToSession $domainAdminCredPSSession -Path $sharedModuleFilePath -Destination $sharedModuleFilePathInVM
}

'Setup the PowerShell Direct sessions...' | Write-ScriptLog -Context $env:ComputerName
$params = @{
    InputObject = [PSCustomObject] @{
        SharedModuleFilePath = $sharedModuleFilePathInVM
    }
}
Invoke-Command @params -Session $domainAdminCredPSSessions -ScriptBlock {
    param (
        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [string] $SharedModuleFilePath
    )

    $ErrorActionPreference = [Management.Automation.ActionPreference]::Stop
    $WarningPreference = [Management.Automation.ActionPreference]::Continue
    $VerbosePreference = [Management.Automation.ActionPreference]::Continue
    $ProgressPreference = [Management.Automation.ActionPreference]::SilentlyContinue
    Import-Module -Name $SharedModuleFilePath -Force
} #| Out-String | Write-ScriptLog -Context $vmName

'Creating virtual switches within each HCI node...' | Write-ScriptLog -Context $env:ComputerName -UseInScriptBlock
$params = @{
    InputObject = [PSCustomObject] @{
        NetAdapterName = [PSCustomObject] @{
            Management = $labConfig.hciNode.netAdapter.management.name
            Compute    = $labConfig.hciNode.netAdapter.compute.name
        }
    }
}
Invoke-Command @params -Session $domainAdminCredPSSessions -ScriptBlock {
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

'Preparing HCI node drives...' | Write-ScriptLog -Context $env:ComputerName
Invoke-Command -Session $domainAdminCredPSSessions -ScriptBlock {
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

'Getting the node''s UI culture...' | Write-ScriptLog -Context $env:ComputerName
$langTag = Invoke-Command -Session $domainAdminCredPSSessions[0] -ScriptBlock {
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
Invoke-Command @params -Session $domainAdminCredPSSessions[0] -ScriptBlock {
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
Invoke-Command @params -Session $domainAdminCredPSSessions[0] -ScriptBlock {
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
Invoke-Command @params -Session $domainAdminCredPSSessions[0] -ScriptBlock {
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
Invoke-Command @params -Session $domainAdminCredPSSessions[0] -ScriptBlock {
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
        StoragePoolName = 'hcilab-s2d-storage-pool'
    }
}
Invoke-Command @params -Session $domainAdminCredPSSessions[0] -ScriptBlock {
    param (
        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [string] $StoragePoolName
    )

    $params = @{
        PoolFriendlyName = $StoragePoolName
        Confirm          = $false
        Verbose          = $true
        ErrorAction      = [Management.Automation.ActionPreference]::Stop
    }
    Enable-ClusterStorageSpacesDirect @params
} | Out-String | Write-ScriptLog -Context $env:ComputerName

'Creating a volume on S2D...' | Write-ScriptLog -Context $env:ComputerName
$params = @{
    InputObject = [PSCustomObject] @{
        VolumeName      = 'HciVol'
        StoragePoolName = 'hcilab-s2d-storage-pool'
    }
}
Invoke-Command @params -Session $domainAdminCredPSSessions[0] -ScriptBlock {
    param (
        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [string] $VolumeName,

        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [string] $StoragePoolName
    )

    $params = @{
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
} | Out-String | Write-ScriptLog -Context $env:ComputerName

'Cleaning up the PowerShell Direct session...' | Write-ScriptLog -Context $env:ComputerName
$params = @{
    InputObject = [PSCustomObject] @{
        SharedModuleFilePath = $sharedModuleFilePathInVM
    }
}
Invoke-Command @params -Session $domainAdminCredPSSessions -ScriptBlock {
    param (
        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [string] $SharedModuleFilePath
    )

    'Deleting the shared module file "{0}" within the VM...' -f $SharedModuleFilePath | Write-ScriptLog -Context $env:ComputerName -UseInScriptBlock
    Remove-Item -LiteralPath $SharedModuleFilePath -Force
} | Out-String | Write-ScriptLog -Context $env:ComputerName

$domainAdminCredPSSessions | Remove-PSSession

'The HCI cluster creation has been completed.' | Write-ScriptLog -Context $env:ComputerName

Stop-ScriptLogging
