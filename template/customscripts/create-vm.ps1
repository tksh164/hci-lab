[CmdletBinding()]
param ()

$ErrorActionPreference = [Management.Automation.ActionPreference]::Stop
$WarningPreference = [Management.Automation.ActionPreference]::Continue
$VerbosePreference = [Management.Automation.ActionPreference]::Continue
$ProgressPreference = [Management.Automation.ActionPreference]::SilentlyContinue

try {
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    Import-Module -Name ([IO.Path]::Combine($PSScriptRoot, 'common.psm1')) -Force

    $labConfig = Get-LabDeploymentConfig
    Start-ScriptLogging -OutputDirectory $labConfig.labHost.folderPath.log

    'Script file: {0}' -f $PSScriptRoot | Write-ScriptLog
    'Lab deployment config:' | Write-ScriptLog
    $labConfig | ConvertTo-Json -Depth 16 | Write-Host

    $jobs = @()

    'Start the AD DS VM creation job.' | Write-ScriptLog
    $jobScriptFilePath = [IO.Path]::Combine($PSScriptRoot, 'create-vm-job-addsdc.ps1')
    $params = @{
        PSModuleNameToImport = (Get-Module -Name 'common').Path
        LogFileName          = [IO.Path]::GetFileNameWithoutExtension($jobScriptFilePath)
    }
    $jobs += Start-Job -Name 'addsdc-vm' -LiteralPath $jobScriptFilePath -InputObject ([PSCustomObject] $params)
    'Start the AD DS VM creation job completed.' | Write-ScriptLog

    'Start the management server VM creation job.' | Write-ScriptLog
    $jobScriptFilePath = [IO.Path]::Combine($PSScriptRoot, 'create-vm-job-wac.ps1')
    $params = @{
        PSModuleNameToImport = (Get-Module -Name 'common').Path
        LogFileName          = [IO.Path]::GetFileNameWithoutExtension($jobScriptFilePath)
    }
    $jobs += Start-Job -Name 'wac-vm' -LiteralPath $jobScriptFilePath -InputObject ([PSCustomObject] $params)
    'Start the management server VM creation job completed.' | Write-ScriptLog

    'Start the HCI node VM creation jobs.' | Write-ScriptLog
    $jobScriptFilePath = [IO.Path]::Combine($PSScriptRoot, 'create-vm-job-hcinode.ps1')
    for ($nodeIndex = 0; $nodeIndex -lt $labConfig.hciNode.nodeCount; $nodeIndex++) {
        $vmName = Format-HciNodeName -Format $labConfig.hciNode.vmName -Offset $labConfig.hciNode.vmNameOffset -Index $nodeIndex
        'Start a VM creation job for the VM "{0}".' -f $vmName | Write-ScriptLog
        $params = @{
            NodeIndex            = $nodeIndex
            PSModuleNameToImport = (Get-Module -Name 'common').Path
            LogFileName          = [IO.Path]::GetFileNameWithoutExtension($jobScriptFilePath) + '-' + $vmName
        }
        $jobs += Start-Job -Name $vmName -LiteralPath $jobScriptFilePath -InputObject ([PSCustomObject] $params)
    }
    'Start the HCI node VM creation jobs completed.' | Write-ScriptLog

    'The HCI lab VMs creation job status:' | Write-ScriptLog
    $jobs | Format-Table -Property Id, Name, State, HasMoreData, PSBeginTime, PSEndTime

    'Start waiting for all HCI lab VMs creation jobs completion.' | Write-ScriptLog
    $jobs | Receive-Job -Wait
    'All HCI lab VMs creation jobs completed.' | Write-ScriptLog

    'The HCI lab VMs creation has been successfully completed.' | Write-ScriptLog
}
catch {
    $exceptionMessage = New-ExceptionMessage -ErrorRecord $_
    $exceptionMessage | Write-ScriptLog -Level Error
    throw $exceptionMessage
}
finally {
    'The HCI lab VMs creation job final status:' | Write-ScriptLog
    $jobs | Format-Table -Property Id, Name, State, HasMoreData, PSBeginTime, PSEndTime

    'The HCI lab VMs creation has been finished.' | Write-ScriptLog
    $stopWatch.Stop()
    'Duration of this script ran: {0}' -f $stopWatch.Elapsed.toString('hh\:mm\:ss') | Write-ScriptLog
    Stop-ScriptLogging
}
