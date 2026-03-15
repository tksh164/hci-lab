[CmdletBinding()]
param ()

$ErrorActionPreference = [Management.Automation.ActionPreference]::Stop
$WarningPreference = [Management.Automation.ActionPreference]::Continue
$VerbosePreference = [Management.Automation.ActionPreference]::Continue
$ProgressPreference = [Management.Automation.ActionPreference]::SilentlyContinue

function Deploy-FastDownloadTool
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateScript({ Test-Path -PathType Container -LiteralPath $_ })]
        [string] $DownloadFolderPath
    )

    # Download the zip file of the tool.
    $params = @{
        SourceUri      = 'https://github.com/aria2/aria2/releases/download/release-1.37.0/aria2-1.37.0-win-64bit-build1.zip'
        DownloadFolder = $DownloadFolderPath
        FileNameToSave = 'aria2.zip'
    }
    $zipFile = Invoke-FileDownload @params

    # Extract the tool from the zip file.
    $folderPathToExpand = $zipFile.FullName.Replace('.zip', '')
    Expand-Archive -Path $zipFile.FullName -DestinationPath $folderPathToExpand -Force

    $relativeExeFilePath = Get-ChildItem -Recurse -File -Name 'aria2c.exe' -LiteralPath $folderPathToExpand
    if ($relativeExeFilePath -eq $null) {
        throw 'aria2c.exe does not found in the expanded folder "{0}".' -f $folderPathToExpand
    }

    # Return the full path of the tool's executable file.
    return Join-Path -Path $folderPathToExpand -ChildPath $relativeExeFilePath
}

function Invoke-FastFileDownload
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string] $ToolFilePath,

        [Parameter(Mandatory = $true)]
        [string] $SourceUri,

        [Parameter(Mandatory = $true)]
        [ValidateScript({ Test-Path -PathType Container -LiteralPath $_ })]
        [string] $DownloadFolder,
    
        [Parameter(Mandatory = $true)]
        [string] $FileNameToSave,

        [Parameter(Mandatory = $false)]
        [ValidateRange(0, 1000)]
        [int] $MaxRetryCount = 5,

        [Parameter(Mandatory = $false)]
        [ValidateRange(0, 3600)]
        [int] $RetryIntervalSeconds = 10
    )

    $params = @{
        FilePath     = $ToolFilePath
        ArgumentList = '--max-connection-per-server=5 --split=5 --max-tries={0} --retry-wait={1} --timeout=60 --user-agent=Wget --file-allocation=none --log="" --dir={2} --out={3} {4}' -f $MaxRetryCount, $RetryIntervalSeconds, $DownloadFolder, $FileNameToSave, $SourceUri
        PassThru     = $true
        Wait         = $true
        NoNewWindow  = $true
    }
    $proc = Start-Process @params

    if ($proc.ExitCode -ne 0) {
        throw 'The "{0}" failed with exit code {1} when downloading the file from {2}.' -f $ToolFilePath, $proc.ExitCode, $SourceUri
    }

    $destinationFilePath = Join-Path -Path $DownloadFolder -ChildPath $FileNameToSave
    return Get-Item -LiteralPath $destinationFilePath
}

function Invoke-IsoFileDownload
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string] $ToolFilePath,

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
        ToolFilePath   = $ToolFilePath
        SourceUri      = $AssetUrls[$OperatingSystem]['iso'][$Culture]
        DownloadFolder = $DownloadFolderPath
        FileNameToSave = (Format-IsoFileName -OperatingSystem $OperatingSystem -Culture $Culture)
    }
    return Invoke-FastFileDownload @params
}

function Invoke-UpdateFileDonwload
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string] $ToolFilePath,

        [Parameter(Mandatory = $true)]
        [string] $OperatingSystem,

        [Parameter(Mandatory = $true)]
        [ValidateScript({ Test-Path -PathType Container -LiteralPath $_ })]
        [string] $DownloadFolderBasePath,

        [Parameter(Mandatory = $true)]
        [HashTable] $AssetUrls
    )

    $downloadFolderPath = [IO.Path]::Combine($DownloadFolderBasePath, $OperatingSystem)
    New-Item -ItemType Directory -Path $downloadFolderPath -Force | Out-String -Width 1000 | Write-ScriptLog

    'Download {0} updates for {1}.' -f $AssetUrls[$OperatingSystem]['updates'].Length, $OperatingSystem | Write-ScriptLog
    $AssetUrls[$OperatingSystem]['updates'] | Out-String -Width 1000 | Write-ScriptLog

    $downloadedFileInfos = for ($i = 0; $i -lt $AssetUrls[$OperatingSystem]['updates'].Length; $i++) {
        # Prepend the index due to order for applying.
        $fileNameToSave = '{0}_{1}' -f $i, [IO.Path]::GetFileName($AssetUrls[$OperatingSystem]['updates'][$i])

        $params = @{
            ToolFilePath   = $ToolFilePath
            SourceUri      = $AssetUrls[$OperatingSystem]['updates'][$i]
            DownloadFolder = $downloadFolderPath
            FileNameToSave = $fileNameToSave
        }
        Invoke-FastFileDownload @params
    }
    return $downloadedFileInfos
}

try {
    Import-Module -Name ([IO.Path]::Combine($PSScriptRoot, 'common.psm1')) -Force

    $labConfig = Get-LabDeploymentConfig
    Start-ScriptLogging -OutputDirectory $labConfig.labHost.folderPath.log
    'Lab deployment config:' | Write-ScriptLog
    $labConfig | ConvertTo-Json -Depth 16 | Write-Host

    'Import the material URL data file.' | Write-ScriptLog
    $assetUrls = Import-PowerShellDataFile -LiteralPath ([IO.Path]::Combine($PSScriptRoot, 'download-iso-updates-asset-urls.psd1'))
    'Import the material URL data file completed.' | Write-ScriptLog

    # Download the download tool for fast download.
    'Download the fast donwload tool.' | Write-ScriptLog
    $downloadToolFilePath = Deploy-FastDownloadTool -DownloadFolderPath $labConfig.labHost.folderPath.temp
    'Donwload tool: {0}' -f $downloadToolFilePath | Write-ScriptLog
    'Download the fast donwload tool completed.' | Write-ScriptLog

    # ISO

    'Create the download folder if it does not exist.' | Write-ScriptLog
    New-Item -ItemType Directory -Path $labConfig.labHost.folderPath.temp -Force | Out-String -Width 1000 | Write-ScriptLog
    'Create the download folder completed.' | Write-ScriptLog

    'Download the ISO file for HCI nodes.' | Write-ScriptLog
    $params = @{
        ToolFilePath       = $downloadToolFilePath
        OperatingSystem    = $labConfig.hciNode.operatingSystem.sku
        Culture            = $labConfig.guestOS.culture
        DownloadFolderPath = $labConfig.labHost.folderPath.temp
        AssetUrls          = $assetUrls
    }
    Invoke-IsoFileDownload @params | Out-String -Width 1000 | Write-ScriptLog
    'Download the ISO file for HCI nodes completed.' | Write-ScriptLog

    # The Windows Server ISO is always needed for the domain controller VM and the management server.
    if ($labConfig.hciNode.operatingSystem.sku -ne [HciLab.OSSku]::WindowsServer2025) {
        'Download the Windows Server ISO file.' | Write-ScriptLog
        $params = @{
            ToolFilePath       = $downloadToolFilePath
            OperatingSystem    = [HciLab.OSSku]::WindowsServer2025
            Culture            = $labConfig.guestOS.culture
            DownloadFolderPath = $labConfig.labHost.folderPath.temp
            AssetUrls          = $assetUrls
        }
        Invoke-IsoFileDownload @params | Out-String -Width 1000 | Write-ScriptLog
        'Download the Windows Server ISO file completed.' | Write-ScriptLog
    }

    # Updates

    # Download the updates if the flag is set.
    if ($labConfig.guestOS.shouldInstallUpdates) {
        'Create the updates folder if it does not exist.' | Write-ScriptLog
        New-Item -ItemType Directory -Path $labConfig.labHost.folderPath.updates -Force | Out-String -Width 1000 | Write-ScriptLog
        'Create the updates folder completed.' | Write-ScriptLog
        
        'Download updates for HCI nodes.' | Write-ScriptLog
        $params = @{
            ToolFilePath           = $downloadToolFilePath
            OperatingSystem        = $labConfig.hciNode.operatingSystem.sku
            DownloadFolderBasePath = $labConfig.labHost.folderPath.updates
            AssetUrls              = $assetUrls
        }
        Invoke-UpdateFileDonwload @params | Out-String -Width 1000 | Write-ScriptLog
        'Download updates for HCI nodes completed.' | Write-ScriptLog
        
        if ($labConfig.hciNode.operatingSystem.sku -ne [HciLab.OSSku]::WindowsServer2025) {
            'Download the Windows Server updates.' | Write-ScriptLog
            $params = @{
                ToolFilePath           = $downloadToolFilePath
                OperatingSystem        = [HciLab.OSSku]::WindowsServer2025
                DownloadFolderBasePath = $labConfig.labHost.folderPath.updates
                AssetUrls              = $assetUrls
            }
            Invoke-UpdateFileDonwload @params | Out-String -Width 1000 | Write-ScriptLog
            'Download the Windows Server updates completed.' | Write-ScriptLog
        }
    }
    else {
        'Skip the download of updates due to shouldInstallUpdates not set.' | Write-ScriptLog
    }

    'The material download has been successfully completed.' | Write-ScriptLog
}
catch {
    $exceptionMessage = New-ExceptionMessage -ErrorRecord $_
    $exceptionMessage | Write-ScriptLog -Level Error
    throw $exceptionMessage
}
finally {
    'The material download has been finished.' | Write-ScriptLog
    Stop-ScriptLogging
}
