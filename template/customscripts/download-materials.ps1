[CmdletBinding()]
param ()

$ErrorActionPreference = [Management.Automation.ActionPreference]::Stop
$WarningPreference = [Management.Automation.ActionPreference]::Continue
$VerbosePreference = [Management.Automation.ActionPreference]::Continue
$ProgressPreference = [Management.Automation.ActionPreference]::SilentlyContinue

function Out-FileUtf8NoBom {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [string] $Content,

        [Parameter(Mandatory = $true)]
        [string] $FilePath
    )

    $utf8Encoding = [System.Text.UTF8Encoding]::new($false, $true)  # No BOM, throw on invalid bytes.
    [System.IO.File]::WriteAllText($FilePath, $Content, $utf8Encoding)
}

function Deploy-Aria2 {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string] $SourceUrl,

        [Parameter(Mandatory = $true)]
        [ValidateScript({ Test-Path -PathType Container -LiteralPath $_ })]
        [string] $DestinationFolderPath,

        [Parameter(Mandatory = $true)]
        [string] $DestinationFileName
    )

    # Download the zip file of the tool.
    $params = @{
        SourceUri      = $SourceUrl
        DownloadFolder = $DestinationFolderPath
        FileNameToSave = $DestinationFileName
    }
    $zipFile = Invoke-FileDownload @params

    # Extract the tool from the zip file.
    $expandDestinationFolderPath = Join-Path -Path $DestinationFolderPath -ChildPath ([System.IO.Path]::GetFileNameWithoutExtension($zipFile.FullName))
    Expand-Archive -Path $zipFile.FullName -DestinationPath $expandDestinationFolderPath -Force

    # Return the full path of the tool's executable file.
    $relativeExeFilePath = Get-ChildItem -Recurse -File -Name 'aria2c.exe' -LiteralPath $expandDestinationFolderPath
    if ($relativeExeFilePath -eq $null) {
        throw 'aria2c.exe does not found in the expanded folder "{0}".' -f $expandDestinationFolderPath
    }
    return Join-Path -Path $expandDestinationFolderPath -ChildPath $relativeExeFilePath
}

function New-Aria2InputFileContent {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [PSCustomObject[]] $DownloadMaterialSpec
    )

    $builder = [System.Text.StringBuilder]::new()

    foreach ($spec in $DownloadMaterialSpec) {
        [void] $builder.AppendLine($spec.Url)
        [void] $builder.AppendLine('  dir={0}' -f $spec.OutputFolderPath)
        if ($spec.FileName -ne $null) {
            [void] $builder.AppendLine('  out={0}' -f $spec.FileName)
        }
    }

    return $builder.ToString()
}

function Invoke-Aria2Download {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateScript({ Test-Path -PathType Leaf -LiteralPath $_ })]
        [string] $CommandFilePath,

        [Parameter(Mandatory = $true)]
        [ValidateScript({ Test-Path -PathType Leaf -LiteralPath $_ })]
        [string] $InputFilePath,

        [Parameter(Mandatory = $false)]
        [ValidateRange(0, 1000)]
        [int] $MaxRetryCount = 5,

        [Parameter(Mandatory = $false)]
        [ValidateRange(0, 3600)]
        [int] $RetryIntervalSeconds = 5
    )

    $commandArgs = @(
        '--file-allocation=none',
        '--continue',
        '--always-resume=true',
        '--max-concurrent-downloads=10',
        '--max-connection-per-server=5',
        '--split=5',
        '--min-split-size=150M',
        # '--lowest-speed-limit=15M',
        '--lowest-speed-limit=5M',
        ('--max-tries={0}' -f $MaxRetryCount),
        ('--retry-wait={0}' -f $RetryIntervalSeconds),
        '--timeout=60',
        '--disk-cache=10240M',
        '--user-agent=Wget',
        '--summary-interval=0',
        '--show-console-readout=false',
        '--console-log-level=error',
        # '--console-log-level=notice',
        '--enable-color=false',
        '--log=""',
        ('--input-file="{0}"' -f $InputFilePath)
    ) -join ' '

    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $CommandFilePath
    $startInfo.Arguments = $commandArgs
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true

    $isCompleted = $false
    $maxAttempts = 30
    for ($attempt = 0; $attempt -lt $maxAttempts; $attempt++) {
        'Attempt {0} of {1}...' -f ($attempt + 1), $maxAttempts | Write-ScriptLog

        $process = [System.Diagnostics.Process]::new()
        $process.StartInfo = $startInfo
        $process.Start() | Out-Null

        $stderrTask = $process.StandardError.ReadToEndAsync()
        $stdout = $process.StandardOutput.ReadToEnd()
        $process.WaitForExit()
        $stderr = $stderrTask.Result

        $stdout | Write-ScriptLog
        $stderr | Write-ScriptLog

        if ($process.ExitCode -eq 0) {
            $isCompleted = $true
            break
        }

        Start-Sleep -Seconds 5
    }

    if (-not $isCompleted) {
        throw 'Download failed after maximum attempts.'
    }
}

function New-DownloadMaterialSpecList {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [PSCustomObject] $LabConfig,

        [Parameter(Mandatory = $true)]
        [PSCustomObject] $MaterialMetadata,

        [Parameter(Mandatory = $true)]
        [PSCustomObject[]] $OSSpec
    )

    # Identify the OS ISO kinds to download.
    $uniqueOSSpecs = $OSSpec | Select-UniquePSObject -KeyPropertyName @('Sku', 'Language')
    'Download OS specs:' | Write-ScriptLog
    $uniqueOSSpecs | Format-Table -Property '*' | Out-String -Width 200 | Write-ScriptLog

    # Make the list of materials to download.
    $materialInfoList = @()
    foreach ($osSpec in $uniqueOSSpecs) {
        $sku = $osSpec.Sku
        $language = $osSpec.Language

        # OS ISO
        $materialInfoList += [PSCustomObject] @{
            # Common properties
            Type             = 'iso'
            Url              = $MaterialMetadata.os.$sku.iso.$language.url
            OutputFolderPath = $LabConfig.labHost.folderPath.temp
            FileName         = $MaterialMetadata.os.$sku.iso.$language.fileName
            # Additional properties
            Sku              = $sku
            Language         = $language
        }

        # Updates
        if ($LabConfig.guestOS.shouldInstallUpdates) {
            foreach ($url in $MaterialMetadata.os.$sku.updates) {
                $materialInfoList += [PSCustomObject] @{
                    # Common properties
                    Type             = 'update'
                    Url              = $url
                    OutputFolderPath = Join-Path -Path $LabConfig.labHost.folderPath.temp -ChildPath (Join-Path -Path 'updates' -ChildPath $sku)
                    FileName         = $null
                    # Additional properties
                    Sku              = $sku
                    Language         = $language
                }
            }
        }
    }

    # Visual Studio Code
    $toolsToInstall = $LabConfig.labHost.toolsToInstall -split ';'
    if ($toolsToInstall -contains 'vscode') {
        $materialInfoList += [PSCustomObject] @{
            # Common properties
            Type             = 'file'
            Url              = $MaterialMetadata.vsCode.url
            OutputFolderPath = $LabConfig.labHost.folderPath.temp
            FileName         = $MaterialMetadata.vsCode.fileName
            # Additional properties
            InventoryKey     = 'vsCode'
        }
    }

    # Configurator App for Azure Local
    if ($LabConfig.wac.shouldInstallConfigAppForAzureLocal) {
        $materialInfoList += [PSCustomObject] @{
            # Common properties
            Type             = 'file'
            Url              = $MaterialMetadata.AzureLocalConfiguratorApp.url
            OutputFolderPath = $LabConfig.labHost.folderPath.temp
            FileName         = $MaterialMetadata.AzureLocalConfiguratorApp.fileName
            # Additional properties
            InventoryKey     = 'AzureLocalConfiguratorApp'
        }
    }

    return $materialInfoList
}

function New-InventoryFileContent {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [PSCustomObject[]] $DownloadMaterialSpec
    )

    $inventory = @{}

    foreach ($spec in $DownloadMaterialSpec) {
        # Append OS related entries.
        if ($spec.Type -eq 'iso') {
            $isoFilePath = Join-Path -Path $spec.OutputFolderPath -ChildPath $spec.FileName
            if (-not (Test-Path -PathType Leaf -LiteralPath $isoFilePath)) {
                throw 'The ISO file path "{0}" does not exist.' -f $isoFilePath
            }

            if ($inventory.Keys -notcontains $spec.Sku) { $inventory.$($spec.Sku) = @{} }
            if ($inventory.$($spec.Sku).Keys -notcontains $spec.Language) { $inventory.$($spec.Sku).$($spec.Language) = @{} }

            $inventory.$($spec.Sku).$($spec.Language).isoFilePath = $isoFilePath
        }

        # Append OS updates entries.
        if ($spec.Type -eq 'update') {
            if (-not (Test-Path -PathType Container -LiteralPath $spec.OutputFolderPath)) {
                throw 'The folder path "{0}" does not exist.' -f $spec.OutputFolderPath
            }

            if ($inventory.Keys -notcontains $spec.Sku) { $inventory.$($spec.Sku) = @{} }

            $inventory.$($spec.Sku).updatesFolderPath = $spec.OutputFolderPath
        }

        # Append individual file entries.
        elseif ($spec.Type -eq 'file') {
            $filePath = Join-Path -Path $spec.OutputFolderPath -ChildPath $spec.FileName
            if (-not (Test-Path -PathType Leaf -LiteralPath $filePath)) {
                throw 'The file path "{0}" does not exist.' -f $filePath
            }

            if ($inventory.Keys -notcontains $spec.InventoryKey) { $inventory.$($spec.InventoryKey) = @{} }

            $inventory.$($spec.InventoryKey).filePath = $filePath
        }
    }

    return $inventory | ConvertTo-Json -Depth 5
}

try {
    # Start the stopwatch to record the total time spent on this script.
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    # Import the common module.
    Import-Module -Name ([IO.Path]::Combine($PSScriptRoot, 'common.psm1')) -Force

    # Retrieve the lab deployment configuration.
    $labConfig = Get-LabDeploymentConfig

    # Start logging.
    Start-ScriptLogging -OutputDirectory $labConfig.labHost.folderPath.log

    # Log the script file path.
    'Script path: "{0}"' -f $PSCommandPath | Write-ScriptLog

    # Log the lab deployment configuration.
    'Lab deployment config:' | Write-ScriptLog
    $labConfig | ConvertTo-Json -Depth 16 | Out-String -Width 200 | Write-ScriptLog

    'Retrieve the material metadata.' | Write-ScriptLog
    $materialMetadata = ConvertFrom-Jsonc -FilePath (Join-Path -Path $PSScriptRoot -ChildPath 'materials.json')
    'Retrieve the material metadata has been completed.' | Write-ScriptLog

    'Deploy the fast download tool.' | Write-ScriptLog
    $params = @{
        SourceUrl             = $materialMetadata.aria2.url
        DestinationFolderPath = $labConfig.labHost.folderPath.temp
        DestinationFileName   = $materialMetadata.aria2.fileName
    }
    $toolExeFilePath = Deploy-Aria2 @params
    'Tool file path: "{0}"' -f $toolExeFilePath | Write-ScriptLog
    'Deploy the fast download tool has been completed.' | Write-ScriptLog

    'Identify the materials that need to be downloaded.' | Write-ScriptLog
    if (-not $labConfig.guestOS.shouldInstallUpdates) {
        'Skip the OS updates download due to shouldInstallUpdates not set.' | Write-ScriptLog
    }
    $params = @{
        LabConfig        = $labConfig
        MaterialMetadata = $materialMetadata
        OSSpec           = @(
            # Cluster node machine's OS spec.
            [PSCustomObject] @{
                Sku      = $labConfig.hciNode.operatingSystem.sku
                Language = $labConfig.guestOS.culture
            },
            # AD DC, workbox machine's OS spec.
            [PSCustomObject] @{
                Sku      = [HciLab.OSSku]::WindowsServer2025
                Language = $labConfig.guestOS.culture
            }
        ) 
    }
    $downloadMaterialSpec = New-DownloadMaterialSpecList @params
    'Download materials:' | Write-ScriptLog
    $downloadMaterialSpec | Format-List -Property * | Out-String -Width 300 | Write-ScriptLog
    'Identify the materials that need to be download has been completed.' | Write-ScriptLog

    'Create the download folders if it does not exist.' | Write-ScriptLog
    New-Item -ItemType Directory -Path $downloadMaterialSpec.OutputFolderPath -Force | Out-String -Width 200 | Write-ScriptLog
    'Create the download folders has been completed.' | Write-ScriptLog

    # NOTE: In PowerShell 5.1, Out-File & Set-Content does not support UTF-8 encoding without BOM.
    # Set the encoding to UTF8 will add BOM to the beginning of the file.
    # Area2 will does not work correctly if the input file beginning with BOM.
    'Create the fast download tool''s input file.' | Write-ScriptLog
    $inputFilePath = Join-Path -Path $labConfig.labHost.folderPath.temp -ChildPath 'aria2-input.txt'
    New-Aria2InputFileContent -DownloadMaterialSpec $downloadMaterialSpec | Out-FileUtf8NoBom -FilePath $inputFilePath
    'Input file path: "{0}"' -f $inputFilePath | Write-ScriptLog
    'Create the fast download tool''s input file has been completed.' | Write-ScriptLog

    'Download the materials.' | Write-ScriptLog
    Invoke-Aria2Download -CommandFilePath $toolExeFilePath -InputFilePath $inputFilePath
    'Download the materials has been completed.' | Write-ScriptLog

    'Create the inventory file.' | Write-ScriptLog
    $inventoryFilePath = Get-MaterialInventoryFilePath -LabConfig $labConfig
    New-InventoryFileContent -DownloadMaterialSpec $downloadMaterialSpec | Out-FileUtf8NoBom -FilePath $inventoryFilePath
    'Inventory file path: "{0}"' -f $inventoryFilePath | Write-ScriptLog
    'Create the inventory file has been completed.' | Write-ScriptLog

    'This script has been completed all tasks.' | Write-ScriptLog
}
catch {
    $exceptionMessage = New-ExceptionMessage -ErrorRecord $_
    $exceptionMessage | Write-ScriptLog -Level Error
    throw $exceptionMessage
}
finally {
    # Stop the stopwatch and log the duration.
    $stopWatch.Stop()
    'Script duration: {0}' -f $stopWatch.Elapsed.toString('hh\:mm\:ss') | Write-ScriptLog

    # Stop logging.
    Stop-ScriptLogging
}
