[CmdletBinding()]
param (
    [Parameter(Mandatory = $false, HelpMessage = 'Resource group location.')]
    [string] $Location = 'japaneast',

    [Parameter(Mandatory = $false, HelpMessage = 'Resource group tags.')]
    [HashTable] $Tag = @{ 'usage' = 'experimental' },

    [switch] $WhatIf,

    [switch] $ValidateOnly
)

$symbol = 'azloc24h2-2602'

$params = @{
    ResourceGroupName      = 'labenv-{0}-{1}' -f $symbol, [datetime]::Now.ToString('yyMMddHHmmss')
    ResourceGroupLocation  = $Location
    TemplateFile           = Resolve-Path -LiteralPath '../../templates/labenv/template.json' -RelativeBasePath $PSScriptRoot
    TemplateParametersFile = Resolve-Path -LiteralPath ('./{0}.parameters.json' -f $symbol) -RelativeBasePath $PSScriptRoot
    ResourceGroupTag       = $Tag
    WhatIf                 = $WhatIf
    ValidateOnly           = $ValidateOnly
}
$testDeployScriptPath = Resolve-Path -LiteralPath '../testdeploy.ps1' -RelativeBasePath $PSScriptRoot

& $testDeployScriptPath @params
