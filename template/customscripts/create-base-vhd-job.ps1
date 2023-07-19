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
    'Copying an ISO file for concurrency from "{0}" to "{1}"...' -f $isoFilePath, $copiedIsoFilePath | Write-ScriptLog -Context $env:ComputerName
    Copy-Item -LiteralPath $isoFilePath -Destination $copiedIsoFilePath -Force -PassThru | Format-List -Property '*' | Out-String | Write-ScriptLog -Context $env:ComputerName
    $isoFilePath = $copiedIsoFilePath
}

'Converting the ISO file to a VHD file...' | Write-ScriptLog -Context $env:ComputerName

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

if ($PSBoundParameters.Keys.Contains('IsoFileNameSuffix')) {
    # Remove the copied ISO file.
    Remove-Item -LiteralPath $isoFilePath -Force
}

Stop-ScriptLogging
