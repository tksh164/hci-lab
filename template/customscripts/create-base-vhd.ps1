[CmdletBinding()]
param ()

$ErrorActionPreference = [Management.Automation.ActionPreference]::Stop
$WarningPreference = [Management.Automation.ActionPreference]::Continue
$VerbosePreference = [Management.Automation.ActionPreference]::Continue
$ProgressPreference = [Management.Automation.ActionPreference]::SilentlyContinue

function Get-DeduplicatedBaseVhdSpec
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [PSCustomObject[]] $BaseVhdSpec
    )

    $result = @{}
    foreach ($spec in $BaseVhdSpec) {
        $key = '{0}_{1}_{2}' -f $spec.OperatingSystem, $spec.ImageIndex, $spec.Culture
        if (-not $result.ContainsKey($key)) {
            $result[$key] = $spec
        }
    }
    return $result.Values
}

function Get-PracticalBaseVhdSpec
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [PSCustomObject[]] $BaseVhdSpec
    )

    $countPerOSSku = @{}
    $suffixGeneratedCountPerOSSku = @{}
    $BaseVhdSpec |
        Group-Object -Property 'OperatingSystem' -NoElement |
        ForEach-Object -Process {
            # Counting the base VHD spec instances per OS SKU.
            $countPerOSSku[$_.Name] = $_.Count

            # Initialize the suffix generated count per OS SKU.
            $suffixGeneratedCountPerOSSku[$_.Name] = 0
        }

    # Create practical base VHD spec instances.
    $result = @()
    foreach ($spec in $BaseVhdSpec) {
        $practicalSpec = @{
            OperatingSystem = $spec.OperatingSystem
            ImageIndex      = $spec.ImageIndex
            Culture         = $spec.Culture
        }
        
        # Add IsoFileNameSuffix if there are multiple base VHD spec instances of the same OS SKU and it's not the first spec instance.
        if (($countPerOSSku[$spec.OperatingSystem] -gt 1) -and ($suffixGeneratedCountPerOSSku[$spec.OperatingSystem] -gt 0)) {
            $practicalSpec.IsoFileNameSuffix = 'copied-imgidx{0}' -f $spec.ImageIndex
        }

        $result += [PSCustomObject] $practicalSpec
        $suffixGeneratedCountPerOSSku[$spec.OperatingSystem]++
    }

    return $result
}

try {
    Import-Module -Name ([IO.Path]::Combine($PSScriptRoot, 'common.psm1')) -Force

    $labConfig = Get-LabDeploymentConfig
    Start-ScriptLogging -OutputDirectory $labConfig.labHost.folderPath.log

    'Lab deployment config:' | Write-ScriptLog
    $labConfig | ConvertTo-Json -Depth 16 | Write-Host

    # Base VHD specs.
    $addsDcVhdSpec = [PSCustomObject] @{
        OperatingSystem = [HciLab.OSSku]::WindowsServer2022
        ImageIndex      = [int]([HciLab.OSImageIndex]::WSDatacenterServerCore)
        Culture         = $labConfig.guestOS.culture
    }
    $wacVhdSpec = [PSCustomObject] @{
        OperatingSystem = [HciLab.OSSku]::WindowsServer2022
        ImageIndex      = [int]([HciLab.OSImageIndex]::WSDatacenterDesktopExperience)
        Culture         = $labConfig.guestOS.culture
    }
    $hciNodeVhdSpec = [PSCustomObject] @{
        OperatingSystem = $labConfig.hciNode.operatingSystem.sku
        ImageIndex      = $labConfig.hciNode.operatingSystem.imageIndex
        Culture         = $labConfig.guestOS.culture
    }

    'Create the temp folder if it does not exist.' | Write-ScriptLog
    New-Item -ItemType Directory -Path $labConfig.labHost.folderPath.temp -Force
    'Create the temp folder completed.' | Write-ScriptLog

    'Create the VHD folder if it does not exist.' | Write-ScriptLog
    New-Item -ItemType Directory -Path $labConfig.labHost.folderPath.vhd -Force
    'Create the VHD folder completed.' | Write-ScriptLog

    'Download the Convert-WindowsImage.ps1.' | Write-ScriptLog
    $params = @{
        SourceUri      = 'https://raw.githubusercontent.com/microsoft/MSLab/master/Tools/Convert-WindowsImage.ps1'
        DownloadFolder = $labConfig.labHost.folderPath.temp
        FileNameToSave = 'Convert-WindowsImage.ps1'
    }
    $convertWimScriptFile = Invoke-FileDownload @params
    $convertWimScriptFile
    'Download the Convert-WindowsImage.ps1 completed.' | Write-ScriptLog

    'Clarify the base VHD''s specification.' | Write-ScriptLog
    $dedupedVhdSpecs = Get-DeduplicatedBaseVhdSpec -BaseVhdSpec $addsDcVhdSpec, $wacVhdSpec, $hciNodeVhdSpec
    $dedupedVhdSpecs | Format-Table -Property 'OperatingSystem', 'ImageIndex', 'Culture' | Out-String | Write-ScriptLog
    $vhdSpecs = Get-PracticalBaseVhdSpec -BaseVhdSpec $dedupedVhdSpecs
    $vhdSpecs | Format-Table -Property 'OperatingSystem', 'ImageIndex', 'Culture', 'IsoFileNameSuffix' | Out-String | Write-ScriptLog
    'Clarify the base VHD''s specification completed.' | Write-ScriptLog

    'Create the base VHD creation jobs.' | Write-ScriptLog
    $jobScriptFilePath = [IO.Path]::Combine($PSScriptRoot, 'create-base-vhd-job.ps1')
    $jobs = @()
    foreach ($spec in $vhdSpecs) {
        $jobName = '{0}_{1}_{2}' -f $spec.OperatingSystem, $spec.ImageIndex, $spec.Culture
        $jobParams = @{
            PSModuleNameToImport = (Get-Module -Name 'common').Path, $convertWimScriptFile.FullName
            OperatingSystem      = $spec.OperatingSystem
            ImageIndex           = $spec.ImageIndex
            Culture              = $spec.Culture
            LogFileName          = [IO.Path]::GetFileNameWithoutExtension($jobScriptFilePath) + '_' + $jobName
        }
        if ($spec.IsoFileNameSuffix -ne $null) {
            $jobParams.IsoFileNameSuffix = $spec.IsoFileNameSuffix
        }
        'Start a base VHD creation job "{0}".' -f $jobName | Write-ScriptLog
        $jobs += Start-Job -Name $jobName -LiteralPath $jobScriptFilePath -InputObject ([PSCustomObject] $jobParams)
    }

    $jobs | Format-Table -Property Id, Name, State, HasMoreData, PSBeginTime, PSEndTime
    $jobs | Receive-Job -Wait
    $jobs | Format-Table -Property Id, Name, State, HasMoreData, PSBeginTime, PSEndTime
    'Create the base VHD creation jobs completed.' | Write-ScriptLog

    'The base VHDs creation has been completed.' | Write-ScriptLog
}
catch {
    $jobs | Format-Table -Property Id, Name, State, HasMoreData, PSBeginTime, PSEndTime
    throw $_
}
finally {
    Stop-ScriptLogging
}
