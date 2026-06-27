#Requires -Version 7

$bicepFilePaths = @(
    './labenv/bastion.bicep',
    './labenv/cloudwitness.bicep',
    './labenv/customscript.bicep',
    './labenv/dsc.bicep',
    './labenv/hci-lab.bicep',
    './labenv/hostvm.bicep',
    './labenv/keyvault-rbac.bicep',
    './labenv/keyvault.bicep',
    './labenv/vnet.bicep'
)
$outputBaseFolderPath = '../templates'

# Check the az command.
$azCommand = Get-Command -Name 'az'
Write-Host 'az: ' -NoNewline -ForegroundColor Cyan
Write-Host ('"{0}"' -f $azCommand.Path)

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

    & $azCommand.Path @('bicep', 'build', '--outdir', $outputFolderFullPath, '--file', $bicepFileFullPath)
}
