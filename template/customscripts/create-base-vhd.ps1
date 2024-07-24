[CmdletBinding()]
param ()

$ErrorActionPreference = [Management.Automation.ActionPreference]::Stop
$WarningPreference = [Management.Automation.ActionPreference]::Continue
$VerbosePreference = [Management.Automation.ActionPreference]::Continue
$ProgressPreference = [Management.Automation.ActionPreference]::SilentlyContinue

function Select-UniqueBaseVhdSpec
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [PSCustomObject[]] $BaseVhdSpec
    )

    $workingHash = @{}
    foreach ($spec in $BaseVhdSpec) {
        $key = '{0}_{1}_{2}' -f $spec.OperatingSystem, $spec.ImageIndex, $spec.Culture
        if (-not $workingHash.ContainsKey($key)) {
            $workingHash[$key] = $spec
        }
    }
    return $workingHash.Values
}

function New-VhdSpecToWimInfoDictionaryKey
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string] $OperatingSystem,

        [Parameter(Mandatory = $true)]
        [string] $Culture
    )
    return '{0}_{1}' -f $OperatingSystem, $Culture
}

function New-VhdSpecToWimInfoDictionary
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [PSCustomObject[]] $BaseVhdSpec,

        [Parameter(Mandatory = $true)]
        [string] $VhdFolderPath
    )

    $dict = @{}
    foreach ($spec in $BaseVhdSpec) {
        $key = New-VhdSpecToWimInfoDictionaryKey -OperatingSystem $spec.OperatingSystem -Culture $spec.Culture
        if (-not $dict.ContainsKey($key)) {
            $params = @{
                OperatingSystem = $spec.OperatingSystem
                Culture         = $spec.Culture
            }
            $isoFilePath = [IO.Path]::Combine($VhdFolderPath, (Format-IsoFileName @params))
            $dict[$key] = [PSCustomObject]@{
                IsoFilePath = $isoFilePath
                WimFilePath = ''
            }
        }
    }
    return $dict
}

function Mount-IsoFile
{
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

function Dismount-IsoFile
{
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

function Resolve-WindowsImageFilePath
{
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

function Get-UpdatePackagePath
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string] $UpdatesFolderPath,

        [Parameter(Mandatory = $true)]
        [string] $OperatingSystem
    )

    $updatePackagePaths = @()
    $osSpecificUpdatesFolderPath = [IO.Path]::Combine($UpdatesFolderPath, $OperatingSystem)
    if (Test-Path -PathType Container -LiteralPath $osSpecificUpdatesFolderPath) {
        $updatePackagePaths += Get-ChildItem -LiteralPath $osSpecificUpdatesFolderPath | Select-Object -ExpandProperty 'FullName' | Sort-Object
    }
    return $updatePackagePaths
}

function Resolve-BaseVhdFilePath
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string] $VhdFolderPath,

        [Parameter(Mandatory = $true)]
        [string] $OperatingSystem,

        [Parameter(Mandatory = $true)]
        [int] $ImageIndex,

        [Parameter(Mandatory = $true)]
        [string] $Culture
    )

    $vhdFileName = Format-BaseVhdFileName -OperatingSystem $OperatingSystem -ImageIndex $ImageIndex -Culture $Culture
    return [IO.Path]::Combine($VhdFolderPath, $vhdFileName)
}

try {
    Import-Module -Name ([IO.Path]::Combine($PSScriptRoot, 'common.psm1')) -Force

    $labConfig = Get-LabDeploymentConfig
    Start-ScriptLogging -OutputDirectory $labConfig.labHost.folderPath.log

    'Lab deployment config:' | Write-ScriptLog
    $labConfig | ConvertTo-Json -Depth 16 | Write-Host

    'Create the temp folder if it does not exist.' | Write-ScriptLog
    New-Item -ItemType Directory -Path $labConfig.labHost.folderPath.temp -Force
    'Create the temp folder completed.' | Write-ScriptLog

    'Create the VHD folder if it does not exist.' | Write-ScriptLog
    New-Item -ItemType Directory -Path $labConfig.labHost.folderPath.vhd -Force
    'Create the VHD folder completed.' | Write-ScriptLog

    # Base VHD specs to need.
    $baseVhdSpecsToNeed = @(
        # For AD DS DC
        [PSCustomObject] @{
            OperatingSystem = [HciLab.OSSku]::WindowsServer2022
            ImageIndex      = [int]([HciLab.OSImageIndex]::WSDatacenterServerCore)
            Culture         = $labConfig.guestOS.culture
        },
        # For management server (WAC)
        [PSCustomObject] @{
            OperatingSystem = [HciLab.OSSku]::WindowsServer2022
            ImageIndex      = [int]([HciLab.OSImageIndex]::WSDatacenterDesktopExperience)
            Culture         = $labConfig.guestOS.culture
        },
        # For HCI node
        [PSCustomObject] @{
            OperatingSystem = $labConfig.hciNode.operatingSystem.sku
            ImageIndex      = $labConfig.hciNode.operatingSystem.imageIndex
            Culture         = $labConfig.guestOS.culture
        }
    )

    'Filter unique base VHD specifications.' | Write-ScriptLog
    $baseVhdSpecs = Select-UniqueBaseVhdSpec -BaseVhdSpec $baseVhdSpecsToNeed
    'Filter unique base VHD specifications completed.' | Write-ScriptLog

    'The base VHD specifications:' | Write-ScriptLog
    $baseVhdSpecs | Format-Table -Property 'OperatingSystem', 'ImageIndex', 'Culture' | Out-String | Write-ScriptLog

    'Create the VHD spec to WIM info dictionary.' | Write-ScriptLog
    $VhdSpecToWimInfoDict = New-VhdSpecToWimInfoDictionary -BaseVhdSpec $baseVhdSpecs -VhdFolderPath $labConfig.labHost.folderPath.temp

    'Mount ISO files.' | Write-ScriptLog
    foreach ($wimInfo in $VhdSpecToWimInfoDict.Values) {
        $mountedDriveLetter = Mount-IsoFile -IsoFilePath $wimInfo.IsoFilePath
        $wimInfo.WimFilePath = Resolve-WindowsImageFilePath -DriveLetter $mountedDriveLetter
    }
    'Mount ISO files completed.' | Write-ScriptLog

    'The VHD spec to WIM info dictionary:' | Write-ScriptLog
    $VhdSpecToWimInfoDict | Format-Table -Property 'Key', 'Value' | Out-String | Write-ScriptLog

    'Create the base VHD creation jobs.' | Write-ScriptLog
    $jobScriptFilePath = [IO.Path]::Combine($PSScriptRoot, 'create-base-vhd-job.ps1')
    $modulePathsForJob = @(
        (Get-Module -Name 'common').Path
    )
    $jobs = @()
    foreach ($spec in $baseVhdSpecs) {
        $jobName = '{0}_{1}_{2}' -f $spec.OperatingSystem, $spec.ImageIndex, $spec.Culture
        $logFileName = [IO.Path]::GetFileNameWithoutExtension($jobScriptFilePath) + '_' + $jobName
        $logContext = '{0}_{1}_{2}' -f $spec.OperatingSystem, $spec.ImageIndex, $spec.Culture
        $VhdSpecToWimInfoDictKey = New-VhdSpecToWimInfoDictionaryKey -OperatingSystem $spec.OperatingSystem -Culture $spec.Culture
        $updatePackagePaths = Get-UpdatePackagePath -UpdatesFolderPath $labConfig.labHost.folderPath.updates -OperatingSystem $spec.OperatingSystem
        $params = @{
            VhdFolderPath   = $labConfig.labHost.folderPath.vhd
            OperatingSystem = $spec.OperatingSystem
            ImageIndex      = $spec.ImageIndex
            Culture         = $spec.Culture
        }
        $vhdFilePath = Resolve-BaseVhdFilePath @params

        'Start a base VHD creation job "{0}".' -f $jobName | Write-ScriptLog
        $jobParams = @{
            PSModulePathToImport = $modulePathsForJob
            LogFileName          = $logFileName
            LogContext           = $logContext
            WimFilePath          = $VhdSpecToWimInfoDict[$VhdSpecToWimInfoDictKey].WimFilePath
            ImageIndex           = $spec.ImageIndex
            VhdFilePath          = $vhdFilePath
        }
        if ($updatePackagePaths.Length -gt 0) {
            $jobParams.UpdatePackagePath = $updatePackagePaths
        }
        $jobs += Start-Job -Name $jobName -LiteralPath $jobScriptFilePath -InputObject ([PSCustomObject] $jobParams)
        'The job "{0}" started.' -f $jobName | Write-ScriptLog
    }

    'The base VHD creation job status:' | Write-ScriptLog
    $jobs | Format-Table -Property Id, Name, State, HasMoreData, PSBeginTime, PSEndTime | Out-String -Width 200 | Write-ScriptLog

    'Start waiting for all base VHD creation jobs completion.' | Write-ScriptLog
    $jobs | Receive-Job -Wait
    'All base VHD creation jobs completed.' | Write-ScriptLog

    'The base VHDs creation has been successfully completed.' | Write-ScriptLog
}
catch {
    $exceptionMessage = New-ExceptionMessage -ErrorRecord $_
    $exceptionMessage | Write-ScriptLog -Level Error
    throw $exceptionMessage
}
finally {
    'The base VHD creation job final status:' | Write-ScriptLog
    $jobs | Format-Table -Property Id, Name, State, HasMoreData, PSBeginTime, PSEndTime, @{ Label = 'ElapsedTime'; Expression = { $_.PSEndTime - $_.PSBeginTime } } | Out-String -Width 200 | Write-ScriptLog

    foreach ($wimInfo in $VhdSpecToWimInfoDict.Values) {
        'Dismount the ISO file "{0}".' -f $wimInfo.IsoFilePath | Write-ScriptLog
        Dismount-IsoFile -IsoFilePath $wimInfo.IsoFilePath
    }

    'The base VHDs creation has been finished.' | Write-ScriptLog
    Stop-ScriptLogging
}
