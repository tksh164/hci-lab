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

function CalculateHciNodeRamBytes
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [int] $NodeCount,

        [Parameter(Mandatory = $true)]
        [ValidateRange(0, [long]::MaxValue)]
        [long] $AddsDcVMRamBytes,

        [Parameter(Mandatory = $true)]
        [ValidateRange(0, [long]::MaxValue)]
        [long] $WacVMRamBytes
    )

    $totalRamBytes = (Get-ComputerInfo).OsTotalVisibleMemorySize * 1KB
    $labHostReservedRamBytes = [Math]::Floor($totalRamBytes * 0.04)  # Reserve a few percent of the total RAM for the lab host.

    'TotalRamBytes: {0}' -f $totalRamBytes | Write-ScriptLog -Context $env:ComputerName
    'LabHostReservedRamBytes: {0}' -f $labHostReservedRamBytes | Write-ScriptLog -Context $env:ComputerName
    'AddsDcVMRamBytes: {0}' -f $AddsDcVMRamBytes | Write-ScriptLog -Context $env:ComputerName
    'WacVMRamBytes: {0}' -f $WacVMRamBytes | Write-ScriptLog -Context $env:ComputerName

    # StartupBytes should be a multiple of 2 MB (2 * 1024 * 1024 bytes).
    [Math]::Floor((($totalRamBytes - $labHostReservedRamBytes - $AddsDcVMRamBytes - $WacVMRamBytes) / $NodeCount) / 2MB) * 2MB
}

$parentVhdPath = [IO.Path]::Combine($labConfig.labHost.folderPath.vhd, (GetBaseVhdFileName -OperatingSystem $labConfig.hciNode.operatingSystem.sku -ImageIndex $labConfig.hciNode.operatingSystem.imageIndex -Culture $labConfig.guestOS.culture))
$ramBytes = CalculateHciNodeRamBytes -NodeCount $labConfig.hciNode.nodeCount -AddsDcVMRamBytes $labConfig.addsDC.maximumRamBytes -WacVMRamBytes $labConfig.wac.maximumRamBytes
$adminPassword = GetSecret -KeyVaultName $labConfig.keyVault.name -SecretName $labConfig.keyVault.secretName
$jobScriptFilePath = [IO.Path]::Combine($PSScriptRoot, 'create-hci-node-vm-job.ps1')

$jobs = @()
for ($nodeIndex = 0; $nodeIndex -lt $labConfig.hciNode.nodeCount; $nodeIndex++) {
    $vmName = GetHciNodeVMName -Format $labConfig.hciNode.vmName -Offset $labConfig.hciNode.vmNameOffset -Index $nodeIndex
    'Start creating a HCI node VM...' -f $vmName | Write-ScriptLog -Context $vmName
    $params = @{
        NodeIndex            = $nodeIndex
        ParentVhdPath        = $parentVhdPath
        RamBytes             = $ramBytes
        AdminPassword        = $adminPassword
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
