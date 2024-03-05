[CmdletBinding()]
param (
    [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
    [string[]] $PSModuleNameToImport,

    [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
    [string] $OperatingSystem,

    [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
    [ValidateRange(1, 4)]
    [int] $ImageIndex,

    [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
    [string] $Culture,

    [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
    [string] $IsoFileNameSuffix,

    [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
    [string] $LogFileName
)

$ErrorActionPreference = [Management.Automation.ActionPreference]::Stop
$WarningPreference = [Management.Automation.ActionPreference]::Continue
$VerbosePreference = [Management.Automation.ActionPreference]::Continue
$ProgressPreference = [Management.Automation.ActionPreference]::SilentlyContinue

Import-Module -Name $PSModuleNameToImport -Force

$labConfig = Get-LabDeploymentConfig
Start-ScriptLogging -OutputDirectory $labConfig.labHost.folderPath.log -FileName $LogFileName
'Lab deployment config:' | Write-ScriptLog
$labConfig | ConvertTo-Json -Depth 16 | Write-Host

$params = @{
    OperatingSystem = $OperatingSystem
    Culture         = $Culture
}
$isoFilePath = [IO.Path]::Combine($labConfig.labHost.folderPath.temp, (Format-IsoFileName @params))

if ($PSBoundParameters.Keys.Contains('IsoFileNameSuffix')) {
    # NOTE: Only one VHD file can be created from a single ISO file at the same time.
    # The second VHD creation will fail if create multiple VHDs from a single ISO file
    # because the ISO file will unmount when finish first one.
    # NOTE: There are possibilities to create multiple Windows Server VHDs depending
    # on the lab configuration. (e.g. ADDS DC and WAC)
    $params = @{
        OperatingSystem = $OperatingSystem
        Culture         = $Culture
        Suffix          = $IsoFileNameSuffix
    }
    $copiedIsoFilePath = [IO.Path]::Combine($labConfig.labHost.folderPath.temp, (Format-IsoFileName @params))
    'Copy an ISO file for concurrency to "{0}" from "{1}".' -f $copiedIsoFilePath, $isoFilePath | Write-ScriptLog
    Copy-Item -LiteralPath $isoFilePath -Destination $copiedIsoFilePath -Force -PassThru | Format-List -Property '*' | Out-String | Write-ScriptLog
    $isoFilePath = $copiedIsoFilePath
    'Copy an ISO file for concurrency completed.' | Write-ScriptLog
}

'Convert the ISO file to a VHD file.' | Write-ScriptLog

$params = @{
    OperatingSystem = $OperatingSystem
    ImageIndex      = $ImageIndex
    Culture         = $Culture
}
$vhdFilePath = [IO.Path]::Combine($labConfig.labHost.folderPath.vhd, (Format-BaseVhdFileName @params))

$updatePackage = @()
$updatesFolderPath = [IO.Path]::Combine($labConfig.labHost.folderPath.updates, $OperatingSystem)
if (Test-Path -PathType Container -LiteralPath $updatesFolderPath) {
    $updatePackage += Get-ChildItem -LiteralPath $updatesFolderPath | Select-Object -ExpandProperty 'FullName' | Sort-Object
}

$params = @{
    SourcePath    = $isoFilePath
    Edition       = $ImageIndex
    VHDPath       = $vhdFilePath
    VHDFormat     = 'VHDX'
    DiskLayout    = 'UEFI'
    SizeBytes     = 500GB
    TempDirectory = $labConfig.labHost.folderPath.temp
    Verbose       = $true
}
# Add update package paths if the update packages exist.
if ($updatePackage.Count -ne 0) {
    $params.Package = $updatePackage
}
Convert-WindowsImage @params

'Convert the ISO file to a VHD file completed.' | Write-ScriptLog

if (-not (Test-Path -PathType Leaf -LiteralPath $vhdFilePath)) {
    $logMessage = 'The converted VHD file "{0}" does not exist.' -f $vhdFilePath
    $logMessage | Write-ScriptLog -Level Error
    throw $logMessage
}

if ($PSBoundParameters.Keys.Contains('IsoFileNameSuffix')) {
    'Remove the copied ISO file.' | Write-ScriptLog
    Remove-Item -LiteralPath $isoFilePath -Force
    'Remove the copied ISO file completed.' | Write-ScriptLog
}

'The base VHD creation job has been completed.' | Write-ScriptLog
Stop-ScriptLogging
