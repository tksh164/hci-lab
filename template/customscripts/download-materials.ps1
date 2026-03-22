[CmdletBinding()]
param ()

$ErrorActionPreference = [Management.Automation.ActionPreference]::Stop
$WarningPreference = [Management.Automation.ActionPreference]::Continue
$VerbosePreference = [Management.Automation.ActionPreference]::Continue
$ProgressPreference = [Management.Automation.ActionPreference]::SilentlyContinue

function ConvertFrom-Jsonc {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateScript({ Test-Path -PathType Leaf -LiteralPath $_ })]
        [string] $FilePath
    )

    # Remove single-line and multi-line comments before ConvertFrom-Json.
    return (Get-Content -LiteralPath $FilePath -Raw) -replace '(?m)(?<=^([^"]|"[^"]*")*)//.*','' -replace '(?ms)/\*.*?\*/','' | ConvertFrom-Json
}

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

    $builder = New-Object -TypeName 'System.Text.StringBuilder'

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
        '--max-connection-per-server=2',
        '--split=5',
        '--min-split-size=150M',
        '--lowest-speed-limit=15M',
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

    $startInfo = New-Object -TypeName 'System.Diagnostics.ProcessStartInfo'
    $startInfo.FileName = $CommandFilePath
    $startInfo.Arguments = $commandArgs
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true

    $isCompleted = $false
    $maxAttempts = 10
    for ($attempt = 0; $attempt -lt $maxAttempts; $attempt++) {
        'Attempt {0} of {1}...' -f ($attempt + 1), $maxAttempts | Write-ScriptLog

        $process = New-Object -TypeName 'System.Diagnostics.Process'
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

        Start-Sleep -Seconds 10
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
    $delimiter = '!'
    $uniqueOSSpecs = @()
    $uniqueOSSpecs += $OSSpec | ForEach-Object {
        $_.sku + $delimiter + $_.culture
    } | Select-Object -Unique
    'Download OS kinds: {0}' -f ($uniqueOSSpecs -join ', ') | Write-ScriptLog

    if (-not $LabConfig.guestOS.shouldInstallUpdates) {
        'Skip the OS updates download due to shouldInstallUpdates not set.' | Write-ScriptLog
    }

    # Make the list of materials to download.
    $materialInfoList = @()
    foreach ($osSpec in $uniqueOSSpecs) {
        ($sku, $culture) = $osSpec -split $delimiter

        # OS ISO
        $materialInfoList += [PSCustomObject] @{
            # Common
            Type             = 'iso'
            Url              = $MaterialMetadata.os.$sku.iso.$culture.url
            OutputFolderPath = $LabConfig.labHost.folderPath.temp
            FileName         = $MaterialMetadata.os.$sku.iso.$culture.fileName
            # Additional
            Sku              = $sku
            Culture          = $culture
        }

        # Updates
        if ($LabConfig.guestOS.shouldInstallUpdates) {
            foreach ($url in $MaterialMetadata.os.$sku.updates) {
                $materialInfoList += [PSCustomObject] @{
                    # Common
                    Type             = 'update'
                    Url              = $url
                    OutputFolderPath = Join-Path -Path $LabConfig.labHost.folderPath.temp -ChildPath (Join-Path -Path 'updates' -ChildPath $sku)
                    FileName         = $null
                    # Additional
                    Sku              = $sku
                    Culture          = $culture
                }
            }
        }
    }

    # Visual Studio Code
    $toolsToInstall = $LabConfig.labHost.toolsToInstall -split ';'
    if ($toolsToInstall -contains 'vscode') {
        $materialInfoList += [PSCustomObject] @{
            # Common
            Type             = 'file'
            Url              = $MaterialMetadata.vsCode.url
            OutputFolderPath = $LabConfig.labHost.folderPath.temp
            FileName         = $MaterialMetadata.vsCode.fileName
            # Additional
            InventoryKey     = 'vsCode'
        }
    }

    # Configurator App for Azure Local
    if ($LabConfig.wac.shouldInstallConfigAppForAzureLocal) {
        $materialInfoList += [PSCustomObject] @{
            # Common
            Type             = 'file'
            Url              = $MaterialMetadata.AzureLocalConfiguratorApp.url
            OutputFolderPath = $LabConfig.labHost.folderPath.temp
            FileName         = $MaterialMetadata.AzureLocalConfiguratorApp.fileName
            # Additional
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
        if ($spec.Type -eq 'iso') {
            $isoFilePath = Join-Path -Path $spec.OutputFolderPath -ChildPath $spec.FileName
            if (-not (Test-Path -PathType Leaf -LiteralPath $isoFilePath)) {
                throw 'The ISO file path "{0}" does not exist.' -f $isoFilePath
            }
            $inventory.$($spec.Sku) = @{
                $spec.Culture = $isoFilePath
            }
        }
        elseif ($spec.Type -eq 'file') {
            $filePath = Join-Path -Path $spec.OutputFolderPath -ChildPath $spec.FileName
            if (-not (Test-Path -PathType Leaf -LiteralPath $filePath)) {
                throw 'The file path "{0}" does not exist.' -f $filePath
            }
            $inventory.$($spec.InventoryKey) = $filePath
        }
    }

    foreach ($spec in $DownloadMaterialSpec) {
        if ($spec.Type -eq 'update') {
            if (-not (Test-Path -PathType Container -LiteralPath $spec.OutputFolderPath)) {
                throw 'The folder path "{0}" does not exist.' -f $spec.OutputFolderPath
            }
            $inventory.$($spec.Sku).updates = $spec.OutputFolderPath
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
    'Retrieve the material metadata completed.' | Write-ScriptLog

    'Deploy the fast donwload tool.' | Write-ScriptLog
    $params = @{
        SourceUrl             = $materialMetadata.aria2.url
        DestinationFolderPath = $labConfig.labHost.folderPath.temp
        DestinationFileName   = $materialMetadata.aria2.fileName
    }
    $toolExeFilePath = Deploy-Aria2 @params
    'Tool file path: "{0}"' -f $toolExeFilePath | Write-ScriptLog
    'Deploy the fast donwload tool completed.' | Write-ScriptLog

    'Make and save the fast download tool''s input file.' | Write-ScriptLog
    $params = @{
        LabConfig        = $labConfig
        MaterialMetadata = $materialMetadata
        OSSpec           = @(
            @{
                sku     = $labConfig.hciNode.operatingSystem.sku
                culture = $labConfig.guestOS.culture
            },
            @{
                sku     = [HciLab.OSSku]::WindowsServer2025  # For AD DC, workbox.
                culture = $labConfig.guestOS.culture
            }
        ) 
    }
    $downloadMaterialSpec = New-DownloadMaterialSpecList @params

    'Download materials:' | Write-ScriptLog
    $downloadMaterialSpec | Format-List -Property * | Out-String -Width 300 | Write-ScriptLog

    'Create the download folders if it does not exist.' | Write-ScriptLog
    New-Item -ItemType Directory -Path $downloadMaterialSpec.OutputFolderPath -Force | Out-String -Width 200 | Write-ScriptLog
    'Create the download folders completed.' | Write-ScriptLog

    # NOTE: In PowerShell 5.1, Out-File & Set-Content does not support UTF-8 encoding without BOM.
    # Set the encoding to UTF8 will add BOM to the beginning of the file.
    # Area2 will does not work correctly if the input file beginning with BOM.
    $inputFilePath = Join-Path -Path $labConfig.labHost.folderPath.temp -ChildPath 'aria2-input.txt'
    New-Aria2InputFileContent -DownloadMaterialSpec $downloadMaterialSpec | Out-FileUtf8NoBom -FilePath $inputFilePath
    'Input file path: "{0}"' -f $inputFilePath | Write-ScriptLog
    'Make and save the fast download tool''s input file completed.' | Write-ScriptLog

    'Download materials.' | Write-ScriptLog
    Invoke-Aria2Download -CommandFilePath $toolExeFilePath -InputFilePath $inputFilePath
    'Download materials completed.' | Write-ScriptLog

    'Make the inventory file.' | Write-ScriptLog
    $inventoryFilePath = Join-Path -Path $labConfig.labHost.folderPath.temp -ChildPath 'inventory.json'
    New-InventoryFileContent -DownloadMaterialSpec $downloadMaterialSpec | Out-FileUtf8NoBom -FilePath $inventoryFilePath
    'Inventory file path: "{0}"' -f $inventoryFilePath | Write-ScriptLog
    'Make the inventory file completed.' | Write-ScriptLog

    'This script has been successfully completed.' | Write-ScriptLog
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
