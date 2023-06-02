[CmdletBinding()]
param (
    [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
    [string[]] $PSModuleNameToImport,

    [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
    [string] $OperatingSystem,

    [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
    [ValidateRange(1, 4)]
    [uint32] $ImageIndex,

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
$labConfig | ConvertTo-Json -Depth 16 | Write-Host

$params = @{
    OperatingSystem = $OperatingSystem
    Culture         = $labConfig.guestOS.culture
}
if ($PSBoundParameters.Keys.Contains('IsoFileNameSuffix')) {
    $params.Suffix = $IsoFileNameSuffix
}
$isoFilePath = [IO.Path]::Combine($labConfig.labHost.folderPath.temp, (New-IsoFileName @params))

$params = @{
    OperatingSystem = $OperatingSystem
    ImageIndex      = $ImageIndex
    Culture         = $labConfig.guestOS.culture
}
$vhdFilePath = [IO.Path]::Combine($labConfig.labHost.folderPath.vhd, (GetBaseVhdFileName @params))

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
    SizeBytes     = 40GB
    TempDirectory = $labConfig.labHost.folderPath.temp
    Verbose       = $true
}
# Add update package paths if the update packages exist.
if ($updatePackage.Count -ne 0) {
    $params.Package = $updatePackage
}
Convert-WindowsImage @params

if (-not (Test-Path -PathType Leaf -LiteralPath $vhdFilePath)) {
    throw 'The created VHD "{0}" does not exist.' -f $vhdFilePath
}

Stop-ScriptLogging
