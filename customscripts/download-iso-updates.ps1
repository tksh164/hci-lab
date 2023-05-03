[CmdletBinding()]
param ()

$ErrorActionPreference = [Management.Automation.ActionPreference]::Stop
$WarningPreference = [Management.Automation.ActionPreference]::Continue
$VerbosePreference = [Management.Automation.ActionPreference]::Continue
$ProgressPreference = [Management.Automation.ActionPreference]::SilentlyContinue

Import-Module -Name ([IO.Path]::Combine($PSScriptRoot, 'shared.psm1')) -Force

$labConfig = Get-LabDeploymentConfig
Start-ScriptLogging -OutputDirectory $labConfig.labHost.folderPath.log -ScriptName $MyInvocation.MyCommand.Name
$labConfig | ConvertTo-Json -Depth 16

function DownloadIso
{
    param (
        [Parameter(Mandatory = $true)]
        [string] $OperatingSystem,

        [Parameter(Mandatory = $true)]
        [string] $Culture,

        [Parameter(Mandatory = $true)]
        [ValidateScript({ Test-Path -PathType Container -LiteralPath $_ })]
        [string] $DownloadFolderPath,

        [Parameter(Mandatory = $true)]
        [HashTable] $AssetUrls
    )

    $params = @{
        SourceUri      = $AssetUrls[$OperatingSystem]['iso'][$Culture]
        DownloadFolder = $DownloadFolderPath
        FileNameToSave = (GetIsoFileName -OperatingSystem $OperatingSystem -Culture $Culture)
    }
    DownloadFile @params
}

function DownloadUpdates
{
    param (
        [Parameter(Mandatory = $true)]
        [string] $OperatingSystem,

        [Parameter(Mandatory = $true)]
        [ValidateScript({ Test-Path -PathType Container -LiteralPath $_ })]
        [string] $DownloadFolderBasePath,

        [Parameter(Mandatory = $true)]
        [HashTable] $AssetUrls
    )

    $downloadFolderPath = [IO.Path]::Combine($DownloadFolderBasePath, $OperatingSystem)
    New-Item -ItemType Directory -Path $downloadFolderPath -Force

    for ($i = 0; $i -lt $AssetUrls[$OperatingSystem]['updates'].Length; $i++) {
        # Prepend the index due to order for applying.
        $fileNameToSave = '{0}_{1}' -f $i, [IO.Path]::GetFileName($AssetUrls[$OperatingSystem]['updates'][$i])

        $params = @{
            SourceUri      = $AssetUrls[$OperatingSystem]['updates'][$i]
            DownloadFolder = $downloadFolderPath
            FileNameToSave = $fileNameToSave
        }
        DownloadFile @params
    }
}

'Reading the asset URL data file...' | Write-ScriptLog -Context $env:ComputerName
$assetUrls = Import-PowerShellDataFile -LiteralPath ([IO.Path]::Combine($PSScriptRoot, 'asset-urls.psd1'))

# ISO

'Creating the download folder if it does not exist...' | Write-ScriptLog -Context $env:ComputerName
New-Item -ItemType Directory -Path $labConfig.labHost.folderPath.temp -Force

'Downloading the ISO file for HCI nodes...' | Write-ScriptLog -Context $env:ComputerName
$params = @{
    OperatingSystem    = $labConfig.hciNode.operatingSystem.sku
    Culture            = $labConfig.guestOS.culture
    DownloadFolderPath = $labConfig.labHost.folderPath.temp
    AssetUrls          = $assetUrls
}
DownloadIso @params

# The Windows Server 2022 ISO is always needed for the domain controller VM.
if ($labConfig.hciNode.operatingSystem.sku -ne 'ws2022') {
    'Downloading the Windows Server ISO file...' | Write-ScriptLog -Context $env:ComputerName
    $params = @{
        OperatingSystem    = 'ws2022'
        Culture            = $labConfig.guestOS.culture
        DownloadFolderPath = $labConfig.labHost.folderPath.temp
        AssetUrls          = $assetUrls
    }
    DownloadIso @params
}

'The ISO files download has been completed.' | Write-ScriptLog -Context $env:ComputerName

# Updates

# Download the updates if the flag was true only.
if ($labConfig.guestOS.applyUpdates) {
    'Creating the updates folder if it does not exist...' | Write-ScriptLog -Context $env:ComputerName
    New-Item -ItemType Directory -Path $labConfig.labHost.folderPath.updates -Force
    
    'Downloading updates...' | Write-ScriptLog -Context $env:ComputerName
    $params = @{
        OperatingSystem        = $labConfig.hciNode.operatingSystem.sku
        DownloadFolderBasePath = $labConfig.labHost.folderPath.updates
        AssetUrls              = $assetUrls
    }
    DownloadUpdates @params
    
    if ($labConfig.hciNode.operatingSystem.sku -ne 'ws2022') {
        'Downloading the Windows Server updates...' | Write-ScriptLog -Context $env:ComputerName
        $params = @{
            OperatingSystem        = 'ws2022'
            DownloadFolderBasePath = $labConfig.labHost.folderPath.updates
            AssetUrls              = $assetUrls
        }
        DownloadUpdates @params
    }

    'The update files download has been completed.' | Write-ScriptLog -Context $env:ComputerName
}
else {
    'Skipped download of updates due to applyUpdates not set.' | Write-ScriptLog -Context $env:ComputerName
}

Stop-ScriptLogging
