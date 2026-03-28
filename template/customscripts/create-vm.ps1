[CmdletBinding()]
param ()

$ErrorActionPreference = [Management.Automation.ActionPreference]::Stop
$WarningPreference = [Management.Automation.ActionPreference]::Continue
$VerbosePreference = [Management.Automation.ActionPreference]::Continue
$ProgressPreference = [Management.Automation.ActionPreference]::SilentlyContinue

try {
    # Mandatory pre-processing.
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    Import-Module -Name ([System.IO.Path]::Combine($PSScriptRoot, 'common.psm1')) -Force
    $labConfig = Get-LabDeploymentConfig
    Start-ScriptLogging -OutputDirectory $labConfig.labHost.folderPath.log
    'Script path: "{0}"' -f $PSCommandPath | Write-ScriptLog
    'Lab deployment config: {0}' -f ($labConfig | ConvertTo-Json -Depth 16) | Write-ScriptLog

    'Prepare the job specs.' | Write-ScriptLog
    $importModulePaths = @( (Get-Module -Name 'common').Path )
    $jobSpecs = @(
        # AD DS DC
        [PSCustomObject]@{
            JobName           = 'addsdc'
            JobScriptFilePath = [System.IO.Path]::Combine($PSScriptRoot, 'create-vm-job-addsdc.ps1')
            ImportModulePaths = $importModulePaths
            LogFileName       = 'create-vm-job-addsdc'
            LogContext        = $labConfig.addsDC.vmName
        },
        # Workbox
        [PSCustomObject]@{
            JobName           = 'workbox'
            JobScriptFilePath = [System.IO.Path]::Combine($PSScriptRoot, 'create-vm-job-wac.ps1')
            ImportModulePaths = $importModulePaths
            LogFileName       = 'create-vm-job-wac'
            LogContext        = $labConfig.wac.vmName
        }
    )
    # HCI nodes
    $jobScriptFilePath = [System.IO.Path]::Combine($PSScriptRoot, 'create-vm-job-hcinode.ps1')
    $jobSpecs += for ($nodeIndex = 0; $nodeIndex -lt $labConfig.hciNode.nodeCount; $nodeIndex++) {
        $nodeName = Format-HciNodeName -Format $labConfig.hciNode.vmName -Offset $labConfig.hciNode.vmNameOffset -Index $nodeIndex
        [PSCustomObject]@{
            JobName           = $nodeName
            JobScriptFilePath = $jobScriptFilePath
            ImportModulePaths = $importModulePaths
            LogFileName       = [System.IO.Path]::GetFileNameWithoutExtension($jobScriptFilePath) + '-' + $nodeName
            LogContext        = $nodeName
            JobParamsJson     = (@{
                NodeIndex = $nodeIndex
            } | ConvertTo-Json -Compress -Depth 5)
        }
    }
    'The job specs: {0}' -f ($jobSpecs | Format-List -Property '*' | Out-String -Width 200) | Write-ScriptLog
    'Prepare the job specs has been completed.' | Write-ScriptLog

    'Create the Hyper-V VM creation jobs.' | Write-ScriptLog
    $jobs = @()
    $jobs += foreach ($spec in $jobSpecs) {
        $jobParams = @{
            ImportModulePath = $spec.ImportModulePaths
            LogFileName      = $spec.LogFileName
            LogContext       = $spec.LogContext
            JobParamsJson    = $spec.JobParamsJson
        }
        Start-Job -Name $spec.JobName -LiteralPath $spec.JobScriptFilePath -InputObject ([PSCustomObject] $jobParams)
        'The job "{0}" has started.' -f $spec.JobName | Write-ScriptLog
    }
    $jobStatus = $jobs | Format-Table -Property 'Id', 'Name', 'State', 'HasMoreData', 'PSBeginTime', 'PSEndTime' | Out-String -Width 200
    'The Hyper-V VM creation job status: {0}' -f $jobStatus | Write-ScriptLog
    'Create the Hyper-V VM creation jobs has been completed.' | Write-ScriptLog

    'Waiting for completion of the all Hyper-V VM creation jobs.' | Write-ScriptLog
    $jobs | Receive-Job -Wait

    'This script has been completed all tasks.' | Write-ScriptLog
}
catch {
    $exceptionMessage = New-ExceptionMessage -ErrorRecord $_
    $exceptionMessage | Write-ScriptLog -Level Error
    throw $exceptionMessage
}
finally {
    $finalStatus = $jobs | Format-Table -Property 'Id', 'Name', 'State', 'HasMoreData', 'PSBeginTime', 'PSEndTime', @{ Label = 'ElapsedTime'; Expression = { $_.PSEndTime - $_.PSBeginTime } } | Out-String -Width 200
    'The final status of the Hyper-V VM creation jobs: {0}' -f $finalStatus | Write-ScriptLog

    # Mandatory post-processing.
    $stopWatch.Stop()
    'Script duration: {0}' -f $stopWatch.Elapsed.toString('hh\:mm\:ss') | Write-ScriptLog
    Stop-ScriptLogging
}
