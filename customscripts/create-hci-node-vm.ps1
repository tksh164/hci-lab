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

$jobScriptFilePath = [IO.Path]::Combine($PSScriptRoot, 'create-hci-node-vm-job.ps1')

$jobs = @()
for ($nodeIndex = 0; $nodeIndex -lt $labConfig.hciNode.nodeCount; $nodeIndex++) {
    $vmName = GetHciNodeVMName -Format $labConfig.hciNode.vmName -Offset $labConfig.hciNode.vmNameOffset -Index $nodeIndex
    'Start creating a HCI node VM...' -f $vmName | Write-ScriptLog -Context $vmName
    $params = @{
        NodeIndex            = $nodeIndex
        PSModuleNameToImport = (Get-Module -Name 'shared').Path
        LogFileName          = [IO.Path]::GetFileNameWithoutExtension($jobScriptFilePath) + '-' + $vmName
    }
    $jobs += Start-Job -Name $vmName -LiteralPath $jobScriptFilePath -InputObject ([PSCustomObject] $params)
}

$jobs | Format-Table -Property Id, Name, State, HasMoreData, PSBeginTime, PSEndTime
$jobs | Receive-Job -Wait
$jobs | Format-Table -Property Id, Name, State, HasMoreData, PSBeginTime, PSEndTime

'The HCI node VMs creation has been completed.' | Write-ScriptLog -Context $env:ComputerName

Stop-ScriptLogging
