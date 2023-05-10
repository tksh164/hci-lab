[CmdletBinding()]
param ()

$ErrorActionPreference = [Management.Automation.ActionPreference]::Stop
$WarningPreference = [Management.Automation.ActionPreference]::Continue
$VerbosePreference = [Management.Automation.ActionPreference]::Continue
$ProgressPreference = [Management.Automation.ActionPreference]::SilentlyContinue

Import-Module -Name ([IO.Path]::Combine($PSScriptRoot, 'shared.psm1')) -Force

$labConfig = Get-LabDeploymentConfig
Start-ScriptLogging -OutputDirectory $labConfig.labHost.folderPath.log
$labConfig | ConvertTo-Json -Depth 16 | Write-Host

$jobs = @()

'Creating an AD DS VM...' | Write-ScriptLog -Context $env:ComputerName
$jobScriptFilePath = [IO.Path]::Combine($PSScriptRoot, 'create-adds-dc-vm.ps1')
$params = @{
    PSModuleNameToImport = (Get-Module -Name 'shared').Path
    LogFileName          = [IO.Path]::GetFileNameWithoutExtension($jobScriptFilePath)
}
$jobs += Start-Job -Name 'addsdc-vm' -LiteralPath $jobScriptFilePath -InputObject ([PSCustomObject] $params)

'Creating a WAC VM...' | Write-ScriptLog -Context $env:ComputerName
$jobScriptFilePath = [IO.Path]::Combine($PSScriptRoot, 'create-wac-vm.ps1')
$params = @{
    PSModuleNameToImport = (Get-Module -Name 'shared').Path
    LogFileName          = [IO.Path]::GetFileNameWithoutExtension($jobScriptFilePath)
}
$jobs += Start-Job -Name 'wac-vm' -LiteralPath $jobScriptFilePath -InputObject ([PSCustomObject] $params)

$jobs | Format-Table -Property Id, Name, State, HasMoreData, PSBeginTime, PSEndTime
$jobs | Receive-Job -Wait
$jobs | Format-Table -Property Id, Name, State, HasMoreData, PSBeginTime, PSEndTime

'The essential VMs creation has been completed.' | Write-ScriptLog -Context $env:ComputerName

Stop-ScriptLogging
