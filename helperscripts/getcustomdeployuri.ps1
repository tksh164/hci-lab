[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)]
    [string] $TemplateUri,

    [Parameter(Mandatory = $false)]
    [string] $UiFormUri
)

$ErrorActionPreference = 'Stop'
$WarningPreference = 'Continue'

$customDeploymentUriFragment = 'https://portal.azure.com/#view/Microsoft_Azure_CreateUIDef/CustomDeploymentBlade/uri/'
$uiFormDefinitionUriFragment = '/uiFormDefinitionUri/'

$encodedTemplateUri = [uri]::EscapeDataString($TemplateUri)
$customDeploymentUri = $customDeploymentUriFragment + $encodedTemplateUri

if ($PSBoundParameters.ContainsKey('UiFormUri')) {
    $encodedUiFormUri = [uri]::EscapeDataString($UiFormUri)
    $customDeploymentUri = $customDeploymentUri + $uiFormDefinitionUriFragment + $encodedUiFormUri
}

Write-Host 'Custom deployment URI: ' -NoNewline
Write-Host $customDeploymentUri -ForegroundColor Cyan
