[CmdletBinding()]
param (
    [string] $ResourceGroupName = 'hcilab1',
    [string] $ResourceGroupLocation = 'japaneast',
    [string] $TemplateFile = './template.json',
    [string] $TemplateParametersFile = './parameters.json',
    [HashTable] $ResourceGroupTag = @{ 'usage' = 'experimental' },
    [switch] $WhatIf,
    [switch] $ValidateOnly
)

$ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop
Set-StrictMode -Version 3

$templateFilePath = [IO.Path]::GetFullPath([IO.Path]::Combine($PSScriptRoot, $TemplateFile))
$templateParametersFilePath = [IO.Path]::GetFullPath([IO.Path]::Combine($PSScriptRoot, $TemplateParametersFile))

Get-AzContext

New-AzResourceGroup -Name $ResourceGroupName -Location $ResourceGroupLocation -Tag $ResourceGroupTag -Verbose -Force

if ($ValidateOnly) {
    $params = @{
        ResourceGroupName = $ResourceGroupName
        TemplateFile      = $templateFilePath
    }

    if (Test-Path -LiteralPath $templateParametersFilePath -PathType Leaf) {
        $params.TemplateParameterFile = $templateParametersFilePath
    }

    $result = Test-AzResourceGroupDeployment @params
    if ($result.Count -eq 0) {
        ''
        'Template is valid.' | Write-Host -ForegroundColor Cyan
    }
    else {
        $result
        $details = $result.Details
        while ($details -ne $null) {
            $details
            $details = $details.Details
        }
    }
}
else {
    $params = @{
        ResourceGroupName = $ResourceGroupName
        Name                    = ('{0}-{1}'-f (Get-Item -LiteralPath $templateFilePath).BaseName, (Get-Date).ToUniversalTime().ToString('yyyyMMdd-HHmm'))
        TemplateFile            = $templateFilePath
        DeploymentDebugLogLevel = 'All'
        WhatIf                  = $WhatIf
        Force                   = $true
        Verbose                 = $true
    }

    if (Test-Path -LiteralPath $templateParametersFilePath -PathType Leaf) {
        $params.TemplateParameterFile = $templateParametersFilePath
    }

    'Deployment name: ' | Write-Host -ForegroundColor Green -NoNewline
    $params.Name | Write-Host

    try {
        New-AzResourceGroupDeployment @params
    }
    catch {
        $error[0]
        Get-AzResourceGroupDeploymentOperation -DeploymentName $params.Name -ResourceGroupName $params.ResourceGroupName -ErrorAction Continue
        'If get error before deployment starts, run this deployment script with -ValidateOnly parameter to get error details.' | Write-Host -ForegroundColor Cyan
    }
}
