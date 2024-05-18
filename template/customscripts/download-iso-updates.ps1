[CmdletBinding()]
param ()

$ErrorActionPreference = [Management.Automation.ActionPreference]::Stop
$WarningPreference = [Management.Automation.ActionPreference]::Continue
$VerbosePreference = [Management.Automation.ActionPreference]::Continue
$ProgressPreference = [Management.Automation.ActionPreference]::SilentlyContinue

Import-Module -Name ([IO.Path]::Combine($PSScriptRoot, 'common.psm1')) -Force

$labConfig = Get-LabDeploymentConfig
Start-ScriptLogging -OutputDirectory $labConfig.labHost.folderPath.log
'Lab deployment config:' | Write-ScriptLog
$labConfig | ConvertTo-Json -Depth 16 | Write-Host

function Invoke-IsoFileDownload
{
    [CmdletBinding()]
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
        FileNameToSave = (Format-IsoFileName -OperatingSystem $OperatingSystem -Culture $Culture)
    }
    return Invoke-FileDownload @params
}

function Invoke-UpdateFileDonwload
{
    [CmdletBinding()]
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

    'Download {0} updates for {1}.' -f $AssetUrls[$OperatingSystem]['updates'].Length, $OperatingSystem | Write-ScriptLog
    $AssetUrls[$OperatingSystem]['updates'] | Out-String -Width 1000 | Write-ScriptLog

    $downloadedFileInfos = for ($i = 0; $i -lt $AssetUrls[$OperatingSystem]['updates'].Length; $i++) {
        # Prepend the index due to order for applying.
        $fileNameToSave = '{0}_{1}' -f $i, [IO.Path]::GetFileName($AssetUrls[$OperatingSystem]['updates'][$i])

        $params = @{
            SourceUri      = $AssetUrls[$OperatingSystem]['updates'][$i]
            DownloadFolder = $downloadFolderPath
            FileNameToSave = $fileNameToSave
        }
        Invoke-FileDownload @params
    }
    return $downloadedFileInfos
}

'Import the material URL data file.' | Write-ScriptLog
$assetUrls = Import-PowerShellDataFile -LiteralPath ([IO.Path]::Combine($PSScriptRoot, 'download-iso-updates-asset-urls.psd1'))
'Import the material URL data file completed.' | Write-ScriptLog

# ISO

'Create the download folder if it does not exist.' | Write-ScriptLog
New-Item -ItemType Directory -Path $labConfig.labHost.folderPath.temp -Force
'Create the download folder completed.' | Write-ScriptLog

'Download the ISO file for HCI nodes.' | Write-ScriptLog
$params = @{
    OperatingSystem    = $labConfig.hciNode.operatingSystem.sku
    Culture            = $labConfig.guestOS.culture
    DownloadFolderPath = $labConfig.labHost.folderPath.temp
    AssetUrls          = $assetUrls
}
Invoke-IsoFileDownload @params
'Download the ISO file for HCI nodes completed.' | Write-ScriptLog

# The Windows Server 2022 ISO is always needed for the domain controller VM.
if ($labConfig.hciNode.operatingSystem.sku -ne [HciLab.OSSku]::WindowsServer2022) {
    'Donwload the Windows Server ISO file.' | Write-ScriptLog
    $params = @{
        OperatingSystem    = [HciLab.OSSku]::WindowsServer2022
        Culture            = $labConfig.guestOS.culture
        DownloadFolderPath = $labConfig.labHost.folderPath.temp
        AssetUrls          = $assetUrls
    }
    Invoke-IsoFileDownload @params
    'Donwload the Windows Server ISO file completed.' | Write-ScriptLog
}

# Updates

# Download the updates if the flag is set.
if ($labConfig.guestOS.shouldInstallUpdates) {
    'Create the updates folder if it does not exist.' | Write-ScriptLog
    New-Item -ItemType Directory -Path $labConfig.labHost.folderPath.updates -Force
    'Create the updates folder completed.' | Write-ScriptLog
    
    'Download updates for HCI nodes.' | Write-ScriptLog
    $params = @{
        OperatingSystem        = $labConfig.hciNode.operatingSystem.sku
        DownloadFolderBasePath = $labConfig.labHost.folderPath.updates
        AssetUrls              = $assetUrls
    }
    Invoke-UpdateFileDonwload @params
    'Download updates. for HCI nodes completed.' | Write-ScriptLog
    
    if ($labConfig.hciNode.operatingSystem.sku -ne [HciLab.OSSku]::WindowsServer2022) {
        'Download the Windows Server updates.' | Write-ScriptLog
        $params = @{
            OperatingSystem        = [HciLab.OSSku]::WindowsServer2022
            DownloadFolderBasePath = $labConfig.labHost.folderPath.updates
            AssetUrls              = $assetUrls
        }
        Invoke-UpdateFileDonwload @params
        'Download the Windows Server updates completed.' | Write-ScriptLog
    }
}
else {
    'Skip the download of updates due to shouldInstallUpdates not set.' | Write-ScriptLog
}

'The material download has been completed.' | Write-ScriptLog
Stop-ScriptLogging
