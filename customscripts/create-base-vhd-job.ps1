[CmdletBinding()]
param (
    [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
    [string[]] $PSModuleNameToImport,

    [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
    [ValidateScript({ Test-Path -PathType Container -LiteralPath $_ })]
    [string] $IsoFolder,

    [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
    [string] $OperatingSystem,

    [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
    [ValidateRange(1, 4)]
    [int] $ImageIndex,

    [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
    [string] $IsoFileNameSuffix,

    [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
    [string] $Culture,

    [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
    [ValidateScript({ Test-Path -PathType Container -LiteralPath $_ })]
    [string] $VhdFolder,

    [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
    [ValidateScript({ Test-Path -PathType Container -LiteralPath $_ })]
    [string] $UpdatesFolder,

    [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
    [ValidateScript({ Test-Path -PathType Container -LiteralPath $_ })]
    [string] $WorkFolder,

    [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
    [ValidateScript({ Test-Path -PathType Container -LiteralPath $_ })]
    [string] $LogFolder,

    [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
    [string] $LogFileName
)

$ErrorActionPreference = [Management.Automation.ActionPreference]::Stop
$WarningPreference = [Management.Automation.ActionPreference]::Continue
$VerbosePreference = [Management.Automation.ActionPreference]::Continue
$ProgressPreference = [Management.Automation.ActionPreference]::SilentlyContinue

Import-Module -Name $PSModuleNameToImport -Force

Start-ScriptLogging -OutputDirectory $LogFolder -FileName $LogFileName

$sourcePath = if ($PSBoundParameters.Keys.Contains('IsoFileNameSuffix')) {
    [IO.Path]::Combine($IsoFolder, (GetIsoFileName -OperatingSystem $OperatingSystem -Culture $Culture -Suffix $IsoFileNameSuffix))
}
else {
    [IO.Path]::Combine($IsoFolder, (GetIsoFileName -OperatingSystem $OperatingSystem -Culture $Culture))
}

$vhdPath = [IO.Path]::Combine($VhdFolder, (GetBaseVhdFileName -OperatingSystem $OperatingSystem -ImageIndex $ImageIndex -Culture $Culture))

$updatePackage = @()
$updatesFolderPath = [IO.Path]::Combine($UpdatesFolder, $OperatingSystem)
if (Test-Path -PathType Container -LiteralPath $updatesFolderPath) {
    $updatePackage += Get-ChildItem -LiteralPath $updatesFolderPath | Select-Object -ExpandProperty 'FullName' | Sort-Object
}

$params = @{
    SourcePath    = $sourcePath
    Edition       = $ImageIndex
    VHDPath       = $vhdPath
    VHDFormat     = 'VHDX'
    DiskLayout    = 'UEFI'
    SizeBytes     = 40GB
    TempDirectory = $WorkFolder
    Verbose       = $true
}
# Add update package paths if the update packages exist.
if ($updatePackage.Count -ne 0) {
    $params.Package = $updatePackage
}
Convert-WindowsImage @params

if (-not (Test-Path -PathType Leaf -LiteralPath $vhdPath)) {
    throw ('The created VHD "{0}" does not exist.' -f $vhdPath)
}

Stop-ScriptLogging
