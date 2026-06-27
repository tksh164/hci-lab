[CmdletBinding()]
param ()

$symbol = 'azloc24h2-2606'

$params = @{
    ResourceGroupName      = '{0}-{1}' -f $symbol, [datetime]::Now.ToString('yyMMddHHmmss')
    ResourceGroupLocation  = 'japaneast'
    TemplateFile           = Resolve-Path -LiteralPath '../../templates/labenv/template.json' -RelativeBasePath $PSScriptRoot
    TemplateParametersFile = Resolve-Path -LiteralPath ('./{0}.parameters.json' -f $symbol) -RelativeBasePath $PSScriptRoot
    ResourceGroupTag       = @{ 'usage' = 'experimental' }
    WhatIf                 = $false
    ValidateOnly           = $false
} 

$testDeployScriptPath = Resolve-Path -LiteralPath '../testdeploy.ps1' -RelativeBasePath $PSScriptRoot

& $testDeployScriptPath @params
