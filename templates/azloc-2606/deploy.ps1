#Requires -Version 7

[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)]
    [string] $ResourceGroupName,

    [Parameter(Mandatory = $false)]
    [string] $ResourceGroupLocation = 'japaneast',

    [Parameter(Mandatory = $false)]
    [string] $TemplateFile = './template.json',

    [Parameter(Mandatory = $false)]
    [string] $TemplateParametersFile = './parameters.json',

    [Parameter(Mandatory = $false)]
    [HashTable] $ResourceGroupTag = @{ 'usage' = 'experimental' },

    [switch] $WhatIf,

    [switch] $ValidateOnly
)

Set-StrictMode -Version 3
$ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop

function Write-ContextInfoToHost {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [bool] $ValidateOnlyValue
    )

    $azContext = Get-AzContext
    '' | Write-Host
    'Subscription Name : ' | Write-Host -NoNewline -ForegroundColor Green
    $azContext.Subscription.Name | Write-Host -ForegroundColor Cyan
    'Subscription ID   : ' | Write-Host -NoNewline -ForegroundColor Green
    $azContext.Subscription.Id | Write-Host -ForegroundColor White
    'Tenant ID         : ' | Write-Host -NoNewline -ForegroundColor Green
    $azContext.Tenant.Id | Write-Host -ForegroundColor White
    'Account ID        : ' | Write-Host -NoNewline -ForegroundColor Green
    $azContext.Account.Id | Write-Host -ForegroundColor White
    'ValidateOnly      : ' | Write-Host -NoNewline -ForegroundColor Green
    $ValidateOnlyValue | Write-Host -ForegroundColor White
    '' | Write-Host
}

function Invoke-TemplateValidation {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string] $ResourceGroupName,

        [Parameter(Mandatory = $true)]
        [string] $TemplateFilePath,

        [Parameter(Mandatory = $true)]
        [string] $TemplateParametersFilePath
    )

    $params = @{
        ResourceGroupName     = $ResourceGroupName
        TemplateFile          = $TemplateFilePath
        TemplateParameterFile = $TemplateParametersFilePath
    }
    $result = Test-AzResourceGroupDeployment @params
    if ($result.Count -eq 0) {
        '' | Write-Host
        '✅ Template is valid.' | Write-Host -ForegroundColor Cyan
        '' | Write-Host
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

function Invoke-TemplateDeployment {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string] $ResourceGroupName,

        [Parameter(Mandatory = $true)]
        [string] $TemplateFilePath,

        [Parameter(Mandatory = $true)]
        [string] $TemplateParametersFilePath
    )

    $params = @{
        ResourceGroupName       = $ResourceGroupName
        Name                    = '{0}-{1}'-f [IO.Path]::GetFileNameWithoutExtension($TemplateFilePath), (Get-Date).ToUniversalTime().ToString('yyyyMMdd-HHmm')
        TemplateFile            = $TemplateFilePath
        TemplateParameterFile   = $TemplateParametersFilePath
        DeploymentDebugLogLevel = 'All'
        WhatIf                  = $WhatIf
        Force                   = $true
        Verbose                 = $true
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

$templateFilePath = Resolve-Path -LiteralPath $TemplateFile
if (-not (Test-Path -LiteralPath $templateFilePath -PathType Leaf)) {
    throw '{0} is not a file.' -f $templateFilePath
}

$templateParametersFilePath = Resolve-Path $TemplateParametersFile
if (-not (Test-Path -LiteralPath $templateParametersFilePath -PathType Leaf)) {
    throw '{0} is not a file.' -f $templateParametersFilePath
}

Write-ContextInfoToHost -ValidateOnlyValue $ValidateOnly
$response = Read-Host -Prompt 'Press Y to continue or other to cancel' -ErrorAction SilentlyContinue
if ($response -ne 'Y') {
    Write-Host 'Deployment canceled.'
    return
}

Get-AzResourceGroup -Name $ResourceGroupName -Verbose

if ($ValidateOnly) {
    Invoke-TemplateValidation -ResourceGroupName $ResourceGroupName -TemplateFilePath $templateFilePath -TemplateParametersFilePath $templateParametersFilePath
}
else {
    Invoke-TemplateDeployment -ResourceGroupName $ResourceGroupName -TemplateFilePath $templateFilePath -TemplateParametersFilePath $templateParametersFilePath
}
