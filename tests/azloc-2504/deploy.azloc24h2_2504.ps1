[CmdletBinding()]
param (
    [string] $ResourceGroupName = 'hcilab-azloc24h2-2504-{0}' -f [datetime]::Now.TOstring('yyMMddHHmmss'),
    [string] $ResourceGroupLocation = 'japaneast',
    [string] $TemplateFile = '../../template/template.json',
    [string] $TemplateParametersFile = './parameters.azloc24h2_2504.json',
    [HashTable] $ResourceGroupTag = @{ 'usage' = 'experimental' },
    [switch] $WhatIf,
    [switch] $ValidateOnly
)

$ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop
Set-StrictMode -Version 3

$templateFilePath = [IO.Path]::GetFullPath([IO.Path]::Combine($PSScriptRoot, $TemplateFile))
$templateParametersFilePath = [IO.Path]::GetFullPath([IO.Path]::Combine($PSScriptRoot, $TemplateParametersFile))

$azContext = Get-AzContext
Write-Host ''
Write-Host 'Subscription Name : ' -NoNewline -ForegroundColor Green
Write-Host $azContext.Subscription.Name -ForegroundColor Cyan
Write-Host 'Subscription ID   : ' -NoNewline -ForegroundColor Green
Write-Host $azContext.Subscription.Id -ForegroundColor White
Write-Host 'Tenant ID         : ' -NoNewline -ForegroundColor Green
Write-Host $azContext.Tenant.Id -ForegroundColor White
Write-Host 'Account ID        : ' -NoNewline -ForegroundColor Green
Write-Host $azContext.Account.Id -ForegroundColor White
Write-Host ''

$response = Read-Host -Prompt 'Press Y to continue or other to cancel' -ErrorAction SilentlyContinue
if ($response -ne 'Y') {
    Write-Host 'Deployment canceled.'
    return
}

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
    try {
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

        $params = @{
            ResourceGroupName       = $ResourceGroupName
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
    finally {
        $stopWatch.Stop()
        Write-Host ('Elapsed Time: {0}' -f $stopWatch.Elapsed.toString('hh\:mm\:ss'))
    }
}
