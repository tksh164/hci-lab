[CmdletBinding()]
param ()

$ErrorActionPreference = [Management.Automation.ActionPreference]::Stop
$WarningPreference = [Management.Automation.ActionPreference]::Continue
$VerbosePreference = [Management.Automation.ActionPreference]::Continue
$ProgressPreference = [Management.Automation.ActionPreference]::SilentlyContinue

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
        [int] $ImageIndex,

        [Parameter(Mandatory = $true)]
        [string] $Language
    )

    $vhdFileName = '{0}_{1}_{2}.vhdx' -f $Sku, $ImageIndex, $Language
    return [System.IO.Path]::Combine($VhdFolderPath, $vhdFileName)
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
            Sku        = [HciLab.OSSku]::WindowsServer2025
            ImageIndex = [int]([HciLab.OSImageIndex]::WSDatacenterServerCore)
            Language   = $labConfig.guestOS.culture
        },
        # For workbox
        [PSCustomObject] @{
            Sku        = [HciLab.OSSku]::WindowsServer2025
            ImageIndex = [int]([HciLab.OSImageIndex]::WSDatacenterDesktopExperience)
            Language   = $labConfig.guestOS.culture
        },
        # For HCI nodes
        [PSCustomObject] @{
            Sku        = $labConfig.hciNode.operatingSystem.sku
            ImageIndex = $labConfig.hciNode.operatingSystem.imageIndex
            Language   = $labConfig.guestOS.culture
        }
    )

    # The base VHD specs to be created. Select unique specs because sometimes the VMs in the lab use the same OS spec.
    $vhdSpecs = $vhdSpecsForVms | Select-UniquePSObject -KeyPropertyName @('Sku', 'ImageIndex', 'Language') | ForEach-Object -Process {
        [PSCustomObject] @{
            Sku         = $_.Sku
            ImageIndex  = $_.ImageIndex
            Language    = $_.Language
            VhdFilePath = New-BaseVhdFilePath -VhdFolderPath $labConfig.labHost.folderPath.vhd -Sku $_.Sku -ImageIndex $_.ImageIndex -Language $_.Language
        }
    }
    'The base VHD specs: {0}' -f ($vhdSpecs | Format-List -Property '*' | Out-String -Width 200) | Write-ScriptLog

    # The ISO file specs to be mounted to create the base VHDs.
    $isoSpecs = $vhdSpecs | Select-UniquePSObject -KeyPropertyName @('Sku', 'Language') | ForEach-Object -Process {
        [PSCustomObject] @{
            IsoFilePath = $materialInventory.$($_.Sku).$($_.Language).isoFilePath
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
        $jobName = '{0}_{1}_{2}' -f $spec.Sku, $spec.ImageIndex, $spec.Language
        $jobLogFileName = [System.IO.Path]::GetFileNameWithoutExtension($jobScriptFilePath) + '_' + $jobName

        [PSCustomObject]@{
            JobName           = $jobName
            JobScriptFilePath = $jobScriptFilePath
            ImportModulePaths = $importModulePaths
            LogFileName       = $jobLogFileName
            LogContext        = $jobName
            JobParamsJson     = (@{
                WimFilePath             = $wimFilePathLookupHash.$(Get-WimFilePathLookupKey -Sku $spec.Sku -Language $spec.Language)
                ImageIndex              = $spec.ImageIndex
                UpdatePackageFolderPath = if ($materialInventory.$($spec.Sku).updatesFolderPath) { $materialInventory.$($spec.Sku).updatesFolderPath } else { '' }
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
    foreach ($spec in $vhdSpecs) {
        $materialInventory.$($spec.Sku).$($spec.Language).vhdFilePath = $spec.VhdFilePath
    }
    $materialInventory | ConvertTo-Json -Depth 5 | Out-FileUtf8NoBom -FilePath $inventoryFilePath
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
