#Requires -Version 7

$bicepFilePaths = @(
    './hci-lab/hci-lab.bicep'
)
$outputBaseFolderPath = '../templates'

# Check the bicep command.
$bicepCommand = Get-Command -Name 'bicep'
Write-Host 'Bicep: ' -NoNewline -ForegroundColor Cyan
Write-Host ('"{0}"' -f $bicepCommand.Path)

# Build the bicep file to ARM template file.
foreach ($bicepFilePath in $bicepFilePaths) {
    $bicepFileFullPath = (Resolve-Path -LiteralPath $bicepFilePath -RelativeBasePath $PSScriptRoot).Path

    $replacePart = [IO.Path]::GetDirectoryName([IO.Path]::GetDirectoryName($bicepFileFullPath))
    $outputBaseFolderFullPath = (Resolve-Path -LiteralPath $outputBaseFolderPath -RelativeBasePath $PSScriptRoot).Path
    $outputFolderFullPath = [IO.Path]::GetDirectoryName($bicepFileFullPath.Replace($replacePart, $outputBaseFolderFullPath))

    Write-Host 'Build: ' -NoNewline -ForegroundColor Cyan
    Write-Host ('"{0}"' -f $bicepFileFullPath) -NoNewline
    Write-Host ' -> ' -NoNewline -ForegroundColor Cyan
    Write-Host ('"{0}"' -f $outputFolderFullPath)

    & $bicepCommand.Path @('build', '--outdir', $outputFolderFullPath, $bicepFileFullPath)
}
