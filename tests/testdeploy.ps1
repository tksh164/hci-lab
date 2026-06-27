[CmdletBinding()]
param (
    [Parameter(Mandatory = $true, HelpMessage = 'Resource group name.')]
    [string] $ResourceGroupName,

    [Parameter(Mandatory = $true, HelpMessage = 'Resource group location.')]
    [string] $ResourceGroupLocation,

    [Parameter(Mandatory = $true, HelpMessage = 'Template file path.')]
    [string] $TemplateFile,

    [Parameter(Mandatory = $true, HelpMessage = 'Template parameters file path.')]
    [string] $TemplateParametersFile,

    [Parameter(Mandatory = $false, HelpMessage = 'Resource group tags.')]
    [HashTable] $ResourceGroupTag,

    [switch] $WhatIf,

    [switch] $ValidateOnly
)

$ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop
Set-StrictMode -Version 3

function Compare-SecureString {
    param (
        [Parameter(Mandatory = $true)]
        [SecureString] $SecureString1,

        [Parameter(Mandatory = $true)]
        [SecureString] $SecureString2
    )

    $plain1 = [System.Net.NetworkCredential]::new('', $SecureString1).Password
    $plain2 = [System.Net.NetworkCredential]::new('', $SecureString2).Password
    return $plain1 -ceq $plain2
}

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
Write-Host 'Template  : ' -NoNewline -ForegroundColor Green
Write-Host $templateFilePath -ForegroundColor White
Write-Host 'Parameter : ' -NoNewline -ForegroundColor Green
Write-Host $templateParametersFilePath -ForegroundColor White
Write-Host ''

$response = Read-Host -Prompt 'Press Y to continue or other to cancel' -ErrorAction SilentlyContinue
if ($response -ne 'Y') {
    Write-Host 'Deployment canceled.'
    return
}

# Check the adminPassword parameter ahead of deployment to avoid the deployment with an unintended password.
$adminPassword = Read-Host -Prompt 'adminPassword' -AsSecureString
$confirmPassword = Read-Host -Prompt 'adminPassword (Confirm)' -AsSecureString
if (-not (Compare-SecureString -SecureString1 $adminPassword -SecureString2 $confirmPassword)) {
    throw 'Passwords do not match.'
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
            adminPassword           = $adminPassword  # The adminPassword parameter for the template
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
