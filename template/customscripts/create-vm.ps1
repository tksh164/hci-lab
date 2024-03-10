[CmdletBinding()]
param ()

$ErrorActionPreference = [Management.Automation.ActionPreference]::Stop
$WarningPreference = [Management.Automation.ActionPreference]::Continue
$VerbosePreference = [Management.Automation.ActionPreference]::Continue
$ProgressPreference = [Management.Automation.ActionPreference]::SilentlyContinue

try {
    Import-Module -Name ([IO.Path]::Combine($PSScriptRoot, 'common.psm1')) -Force

    $labConfig = Get-LabDeploymentConfig
    Start-ScriptLogging -OutputDirectory $labConfig.labHost.folderPath.log
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
        'Start the {0} VM creation job.' -f $vmName | Write-ScriptLog -AdditionalContext $vmName
        $params = @{
            NodeIndex            = $nodeIndex
            PSModuleNameToImport = (Get-Module -Name 'common').Path
            LogFileName          = [IO.Path]::GetFileNameWithoutExtension($jobScriptFilePath) + '-' + $vmName
        }
        $jobs += Start-Job -Name $vmName -LiteralPath $jobScriptFilePath -InputObject ([PSCustomObject] $params)
        'Start the {0} VM creation job completed.' -f $vmName | Write-ScriptLog -AdditionalContext $vmName
    }

    $jobs | Format-Table -Property Id, Name, State, HasMoreData, PSBeginTime, PSEndTime
    $jobs | Receive-Job -Wait
    $jobs | Format-Table -Property Id, Name, State, HasMoreData, PSBeginTime, PSEndTime

    'The HCI lab VMs creation has been completed.' | Write-ScriptLog
}
catch {
    $jobs | Format-Table -Property Id, Name, State, HasMoreData, PSBeginTime, PSEndTime
    throw $_
}
finally {
    Stop-ScriptLogging
}
