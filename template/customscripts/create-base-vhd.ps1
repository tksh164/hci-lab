[CmdletBinding()]
param ()

$ErrorActionPreference = [Management.Automation.ActionPreference]::Stop
$WarningPreference = [Management.Automation.ActionPreference]::Continue
$VerbosePreference = [Management.Automation.ActionPreference]::Continue
$ProgressPreference = [Management.Automation.ActionPreference]::SilentlyContinue

function Test-UseNonbootex {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string] $Sku
    )

    if ($Sku -eq [HciLab.OSSku]::WindowsServer2022) {
        return $true
    }
    return $false
}

function Mount-IsoFile {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string] $IsoFilePath
    )

    if (-not (Test-Path -PathType Leaf -LiteralPath $IsoFilePath)) {
        throw 'Cannot find the specified ISO file "{0}".' -f $IsoFilePath
    }
    $isoVolume = Mount-DiskImage -StorageType ISO -Access ReadOnly -ImagePath $IsoFilePath -PassThru | Get-Volume
    'Mounted "{0}". DriveLetter: {1}, FileSystemLabel: {2}, Size: {3}' -f $IsoFilePath, $isoVolume.DriveLetter, $isoVolume.FileSystemLabel, $isoVolume.Size | Write-ScriptLog
    return $isoVolume.DriveLetter
}

function Dismount-IsoFile {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string] $IsoFilePath
    )

    if (-not (Test-Path -PathType Leaf -LiteralPath $IsoFilePath)) {
        throw 'Cannot find the specified ISO file "{0}".' -f $IsoFilePath
    }
    Dismount-DiskImage -StorageType ISO -ImagePath $IsoFilePath | Out-Null
}

function Get-WimFilePathLookupKey {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string] $Sku,

        [Parameter(Mandatory = $true)]
        [string] $Language
    )

    return '{0}|{1}' -f $Sku, $Language
}

function Resolve-WindowsImageFilePath {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string] $DriveLetter
    )

    $wimFilePath = '{0}:\sources\install.wim' -f $DriveLetter
    if (-not (Test-Path -PathType Leaf -LiteralPath $wimFilePath)) {
        throw 'The specified ISO volume does not have "{0}".' -f $wimFilePath
    }
    return $wimFilePath
}

function New-BaseVhdFilePath {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string] $VhdFolderPath,

        [Parameter(Mandatory = $true)]
        [string] $Sku,

        [Parameter(Mandatory = $true)]
        [string] $Language,

        [Parameter(Mandatory = $true)]
        [int] $ImageIndex
   )

    $vhdFileName = '{0}_{1}_{2}.vhdx' -f $Sku, $Language, $ImageIndex
    return [System.IO.Path]::Combine($VhdFolderPath, $vhdFileName)
}

function New-InventoryJsonWithVhd {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [PSCustomObject] $ExistingMaterialInventory,

        [Parameter(Mandatory = $true)]
        [PSCustomObject[]] $VhdSpecs
    )

    # Convert PSCustomObject to hashtable, only top-level properties.
    # ConvertTo-Json can be convert hashtable and PSCustomObject even it's mixed.
    $newMaterialInventory = @{}
    foreach ($prop in $ExistingMaterialInventory.PSObject.Properties) {
        $newMaterialInventory.($prop.Name) = $prop.Value
    }

    foreach ($spec in $VhdSpecs) {
        $newMaterialInventory | Add-NestedHashtableValue -KeySequence @('Vhd', $spec.Sku, $spec.Language, ([string] $spec.ImageIndex), 'Path') -LeafValue $spec.VhdFilePath
    }
    return ([PSCustomObject] $newMaterialInventory) | ConvertTo-Json -Depth 10
}

try {
    # Mandatory pre-processing.
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    Import-Module -Name ([System.IO.Path]::Combine($PSScriptRoot, 'common.psm1')) -Force
    $labConfig = Get-LabDeploymentConfig
    Start-ScriptLogging -OutputDirectory $labConfig.labHost.folderPath.log
    'Script path: "{0}"' -f $PSCommandPath | Write-ScriptLog
    'Lab deployment config: {0}' -f ($labConfig | ConvertTo-Json -Depth 16) | Write-ScriptLog

    'Read the inventory file.' | Write-ScriptLog
    $inventoryFilePath = Get-MaterialInventoryFilePath -LabConfig $labConfig
    $materialInventory = ConvertFrom-Jsonc -FilePath $inventoryFilePath
    'Read the inventory file has been completed.' | Write-ScriptLog

    'Create the VHD folder if it does not exist.' | Write-ScriptLog
    New-Item -ItemType Directory -Path $labConfig.labHost.folderPath.vhd -Force | Out-String -Width 200 | Write-ScriptLog
    'Create the VHD folder completed.' | Write-ScriptLog

    # The base VHD specs for all Hyper-V VMs in the lab.
    $vhdSpecsForVms = @(
        # For AD DS DC
        [PSCustomObject] @{
            Sku          = [HciLab.OSSku]::WindowsServer2025
            Language     = $labConfig.guestOS.culture
            ImageIndex   = [int]([HciLab.OSImageIndex]::WSDatacenterServerCore)
            UseNonbootex = Test-UseNonbootex -Sku [HciLab.OSSku]::WindowsServer2025
        },
        # For workbox
        [PSCustomObject] @{
            Sku          = [HciLab.OSSku]::WindowsServer2025
            Language     = $labConfig.guestOS.culture
            ImageIndex   = [int]([HciLab.OSImageIndex]::WSDatacenterDesktopExperience)
            UseNonbootex = Test-UseNonbootex -Sku [HciLab.OSSku]::WindowsServer2025
        },
        # For HCI nodes
        [PSCustomObject] @{
            Sku          = $labConfig.hciNode.operatingSystem.sku
            Language     = $labConfig.guestOS.culture
            ImageIndex   = $labConfig.hciNode.operatingSystem.imageIndex
            UseNonbootex = Test-UseNonbootex -Sku $labConfig.hciNode.operatingSystem.sku
        }
    )

    # The base VHD specs to be created. Select unique specs because sometimes the VMs in the lab use the same OS spec.
    $vhdSpecs = $vhdSpecsForVms | Select-UniquePSObject -KeyPropertyName @('Sku', 'ImageIndex', 'Language') | ForEach-Object -Process {
        [PSCustomObject] @{
            Sku          = $_.Sku
            Language     = $_.Language
            ImageIndex   = $_.ImageIndex
            UseNonbootex = $_.UseNonbootex
            VhdFilePath  = New-BaseVhdFilePath -VhdFolderPath $labConfig.labHost.folderPath.vhd -Sku $_.Sku -Language $_.Language -ImageIndex $_.ImageIndex
        }
    }
    'The base VHD specs: {0}' -f ($vhdSpecs | Format-List -Property '*' | Out-String -Width 200) | Write-ScriptLog

    # The ISO file specs to be mounted to create the base VHDs.
    $isoSpecs = $vhdSpecs | Select-UniquePSObject -KeyPropertyName @('Sku', 'Language') | ForEach-Object -Process {
        [PSCustomObject] @{
            IsoFilePath = $materialInventory.Iso.($_.Sku).($_.Language).Path
            Sku         = $_.Sku
            Language    = $_.Language
        }
    }
    'The ISO specs: {0}' -f ($isoSpecs | Format-List -Property '*' | Out-String -Width 200) | Write-ScriptLog

    'Mount all ISOs.' | Write-ScriptLog
    $wimFilePathLookupHash = @{}
    foreach ($spec in $isoSpecs) {
        $mountedDriveLetter = Mount-IsoFile -IsoFilePath $spec.IsoFilePath
        $key = Get-WimFilePathLookupKey -Sku $spec.Sku -Language $spec.Language
        $wimFilePathLookupHash.$key = Resolve-WindowsImageFilePath -DriveLetter $mountedDriveLetter
    }
    'Mount all ISOs has been completed.' | Write-ScriptLog

    'Prepare the job specs.' | Write-ScriptLog
    $jobScriptFilePath = [System.IO.Path]::Combine($PSScriptRoot, 'create-base-vhd-job.ps1')
    $importModulePaths = @( (Get-Module -Name 'common').Path )
    $jobSpecs = @()
    $jobSpecs += foreach ($spec in $vhdSpecs) {
        $jobName = '{0}_{1}_{2}' -f $spec.Sku, $spec.Language, $spec.ImageIndex
        [PSCustomObject] @{
            JobName           = $jobName
            JobScriptFilePath = $jobScriptFilePath
            ImportModulePaths = $importModulePaths
            LogFileName       = [System.IO.Path]::GetFileNameWithoutExtension($jobScriptFilePath) + '_' + $jobName
            LogContext        = $jobName
            JobParamsJson     = (@{
                WimFilePath             = $wimFilePathLookupHash.(Get-WimFilePathLookupKey -Sku $spec.Sku -Language $spec.Language)
                ImageIndex              = $spec.ImageIndex
                UseNonbootex            = $spec.UseNonbootex
                UpdatePackageFolderPath = if ($materialInventory.Update.($spec.Sku).Path) { $materialInventory.Update.($spec.Sku).Path } else { '' }
                VhdFilePath             = $spec.VhdFilePath                
            } | ConvertTo-Json -Compress -Depth 5)
        }
    }
    'The job specs: {0}' -f ($jobSpecs | Format-List -Property '*' | Out-String -Width 200) | Write-ScriptLog
    'Prepare the job specs has been completed.' | Write-ScriptLog

    'Create the base VHD creation jobs.' | Write-ScriptLog
    $jobs = @()
    $jobs += foreach ($spec in $jobSpecs) {
        $jobParams = @{
            ImportModulePath = $spec.ImportModulePaths
            LogFileName      = $spec.LogFileName
            LogContext       = $spec.LogContext
            JobParamsJson    = $spec.JobParamsJson
        }
        Start-Job -Name $spec.JobName -LiteralPath $spec.JobScriptFilePath -InputObject ([PSCustomObject] $jobParams)
        'The job "{0}" has started.' -f $spec.JobName | Write-ScriptLog
    }
    $jobStatus = $jobs | Format-Table -Property 'Id', 'Name', 'State', 'HasMoreData', 'PSBeginTime', 'PSEndTime' | Out-String -Width 200
    'The base VHD creation job status: {0}' -f $jobStatus | Write-ScriptLog
    'Create the base VHD creation jobs has been completed.' | Write-ScriptLog

    'Waiting for completion of the all base VHD creation jobs.' | Write-ScriptLog
    $jobs | Receive-Job -Wait

    'Update the VHD file paths in the inventory file.' | Write-ScriptLog
    New-InventoryJsonWithVhd -ExistingMaterialInventory $materialInventory -VhdSpecs $vhdSpecs | Out-FileUtf8NoBom -FilePath $inventoryFilePath
    'Update the VHD file paths in the inventory file has been completed.' | Write-ScriptLog

    'This script has been completed all tasks.' | Write-ScriptLog
}
catch {
    $exceptionMessage = New-ExceptionMessage -ErrorRecord $_
    $exceptionMessage | Write-ScriptLog -Level Error
    throw $exceptionMessage
}
finally {
    $finalStatus = $jobs | Format-Table -Property 'Id', 'Name', 'State', 'HasMoreData', 'PSBeginTime', 'PSEndTime', @{ Label = 'ElapsedTime'; Expression = { $_.PSEndTime - $_.PSBeginTime } } | Out-String -Width 200
    'The final status of the base VHD creation jobs: {0}' -f $finalStatus | Write-ScriptLog

    foreach ($spec in $isoSpecs) {
        'Dismount the ISO file "{0}".' -f $spec.IsoFilePath | Write-ScriptLog
        Dismount-IsoFile -IsoFilePath $spec.IsoFilePath
    }

    # Mandatory post-processing.
    $stopWatch.Stop()
    'Script duration: {0}' -f $stopWatch.Elapsed.toString('hh\:mm\:ss') | Write-ScriptLog
    Stop-ScriptLogging
}
