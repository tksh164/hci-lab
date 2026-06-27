#Requires -Version 7

$outputFolderBasePath = '../templates'
$buildConfig = @(
    @{ BicepFilePath = './labenv/labenv.bicep';        OutputFolderBasePath = $outputFolderBasePath; JsonFileName = 'template.json' },
    @{ BicepFilePath = './labenv/bastion.bicep';       OutputFolderBasePath = $outputFolderBasePath; JsonFileName = $null },
    @{ BicepFilePath = './labenv/cloudwitness.bicep';  OutputFolderBasePath = $outputFolderBasePath; JsonFileName = $null },
    @{ BicepFilePath = './labenv/customscript.bicep';  OutputFolderBasePath = $outputFolderBasePath; JsonFileName = $null },
    @{ BicepFilePath = './labenv/dsc.bicep';           OutputFolderBasePath = $outputFolderBasePath; JsonFileName = $null },
    @{ BicepFilePath = './labenv/hostvm.bicep';        OutputFolderBasePath = $outputFolderBasePath; JsonFileName = $null },
    @{ BicepFilePath = './labenv/keyvault-rbac.bicep'; OutputFolderBasePath = $outputFolderBasePath; JsonFileName = $null },
    @{ BicepFilePath = './labenv/keyvault.bicep';      OutputFolderBasePath = $outputFolderBasePath; JsonFileName = $null },
    @{ BicepFilePath = './labenv/vnet.bicep';          OutputFolderBasePath = $outputFolderBasePath; JsonFileName = $null }
)

# Check the az command.
$azCommand = Get-Command -Name 'az'
Write-Host 'az: ' -NoNewline -ForegroundColor Cyan
Write-Host ('"{0}"' -f $azCommand.Path)

# Build the bicep file to ARM template file.
foreach ($config in $buildConfig) {
    $bicepFileFullPath = (Resolve-Path -LiteralPath $config.BicepFilePath -RelativeBasePath $PSScriptRoot).Path
    $jsonFileRelativePath = if ($config.JsonFileName -ne $null) {
        [IO.Path]::Combine([IO.Path]::GetDirectoryName($config.BicepFilePath), $config.JsonFileName)
    }
    else {
        $config.BicepFilePath.Replace('.bicep', '.json')
    }
    $jsonFileFullPath = [IO.Path]::GetFullPath([IO.Path]::Combine($PSScriptRoot, $config.OutputFolderBasePath, $jsonFileRelativePath))

    Write-Host 'Build: ' -NoNewline -ForegroundColor Cyan
    Write-Host ('"{0}"' -f $bicepFileFullPath) -NoNewline
    Write-Host ' -> ' -NoNewline -ForegroundColor Cyan
    Write-Host ('"{0}"' -f $jsonFileFullPath)

    & $azCommand.Path @('bicep', 'build', '--outfile', $jsonFileFullPath, '--file', $bicepFileFullPath)
}
