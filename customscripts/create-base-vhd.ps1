[CmdletBinding()]
param ()

$ErrorActionPreference = [Management.Automation.ActionPreference]::Stop
$WarningPreference = [Management.Automation.ActionPreference]::Continue
$VerbosePreference = [Management.Automation.ActionPreference]::Continue
$ProgressPreference = [Management.Automation.ActionPreference]::SilentlyContinue

try {
    Import-Module -Name ([IO.Path]::Combine($PSScriptRoot, 'shared.psm1')) -Force

    $labConfig = Get-LabDeploymentConfig
    Start-ScriptLogging -OutputDirectory $labConfig.labHost.folderPath.log
    $labConfig | ConvertTo-Json -Depth 16 | Write-Host

    'Creating the temp folder if it does not exist...' | Write-ScriptLog -Context $env:ComputerName
    New-Item -ItemType Directory -Path $labConfig.labHost.folderPath.temp -Force

    'Creating the VHD folder if it does not exist...' | Write-ScriptLog -Context $env:ComputerName
    New-Item -ItemType Directory -Path $labConfig.labHost.folderPath.vhd -Force

    'Downloading the Convert-WindowsImage.ps1...' | Write-ScriptLog -Context $env:ComputerName
    $params = @{
        SourceUri      = 'https://raw.githubusercontent.com/microsoft/MSLab/master/Tools/Convert-WindowsImage.ps1'
        DownloadFolder = $labConfig.labHost.folderPath.temp
        FileNameToSave = 'Convert-WindowsImage.ps1'
    }
    $convertWimScriptFile = DownloadFile @params
    $convertWimScriptFile

    # NOTE: Only one VHD file can be created from a single ISO file at the same time.
    # The second VHD creation will fail if create multiple VHDs from a single ISO file
    # because the ISO file will unmount when finish first one.
    'Copying Windows Server ISO file for concurrency...' | Write-ScriptLog -Context $env:ComputerName
    $isoFileNameSuffix = 'for-concurrent'
    $sourceIsoFilePath = [IO.Path]::Combine($labConfig.labHost.folderPath.temp, (GetIsoFileName -OperatingSystem 'ws2022' -Culture $labConfig.guestOS.culture))
    $isoFilePathForConcurrency = [IO.Path]::Combine($labConfig.labHost.folderPath.temp, (GetIsoFileName -OperatingSystem 'ws2022' -Culture $labConfig.guestOS.culture -Suffix $isoFileNameSuffix))
    Copy-Item -LiteralPath $sourceIsoFilePath -Destination $isoFilePathForConcurrency -Force -PassThru

    'Creating the base VHD creation jobs...' | Write-ScriptLog -Context $env:ComputerName
    $jobScriptFilePath = [IO.Path]::Combine($PSScriptRoot, 'create-base-vhd-job.ps1')
    $jobs = @()

    'Starting the HCI node base VHD creation job...' | Write-ScriptLog -Context $env:ComputerName
    $params = @{
        PSModuleNameToImport = (Get-Module -Name 'shared').Path, $convertWimScriptFile.FullName
        OperatingSystem      = $labConfig.hciNode.operatingSystem.sku
        ImageIndex           = $labConfig.hciNode.operatingSystem.imageIndex
        LogFileName          = [IO.Path]::GetFileNameWithoutExtension($jobScriptFilePath) + '-hcinode'
    }
    $jobs += Start-Job -Name 'hci-node' -LiteralPath $jobScriptFilePath -InputObject ([PSCustomObject] $params)

    # Create a Windows Server Server Core (= index 3) VHD for AD DS domain controller VM if HCI node's OS is not Windows Server Server Core.
    if (-not (($labConfig.hciNode.operatingSystem.sku -eq 'ws2022') -and ($labConfig.hciNode.operatingSystem.imageIndex -eq 3))) {
        'Starting the Windows Server Core base VHD creation job...' | Write-ScriptLog -Context $env:ComputerName
        $params = @{
            PSModuleNameToImport = (Get-Module -Name 'shared').Path, $convertWimScriptFile.FullName
            OperatingSystem      = 'ws2022'
            ImageIndex           = 3 # Datacenter (Server Core)
            LogFileName          = [IO.Path]::GetFileNameWithoutExtension($jobScriptFilePath) + '-wscore'
        }

        # Use the for-concurrency ISO file if HCI node's OS is Windows Server with Desktop Experience (= index 4)
        # because the ISO file without suffix is already used for HCI node's VHD creation.
        if (($labConfig.hciNode.operatingSystem.sku -eq 'ws2022') -and ($labConfig.hciNode.operatingSystem.imageIndex -eq 4)) {
            $params.IsoFileNameSuffix = $isoFileNameSuffix
        }

        $jobs += Start-Job -Name 'ws-server-core' -LiteralPath $jobScriptFilePath -InputObject ([PSCustomObject] $params)
    }

    # Create a Windows Server with Desktop Experience (= index 4) VHD for Windows Admin Center VM if HCI node's OS is not Windows Server with Desktop Experience.
    if (-not (($labConfig.hciNode.operatingSystem.sku -eq 'ws2022') -and ($labConfig.hciNode.operatingSystem.imageIndex -eq 4))) {
        'Starting the Windows Server Desktop Experience base VHD creation job...' | Write-ScriptLog -Context $env:ComputerName
        $params = @{
            PSModuleNameToImport = (Get-Module -Name 'shared').Path, $convertWimScriptFile.FullName
            OperatingSystem      = 'ws2022'
            ImageIndex           = 4  # Datacenter with Desktop Experience
            IsoFileNameSuffix    = $isoFileNameSuffix
            LogFileName          = [IO.Path]::GetFileNameWithoutExtension($jobScriptFilePath) + '-wsdexp'
        }
        $jobs += Start-Job -Name 'ws-desktop-experience' -LiteralPath $jobScriptFilePath -InputObject ([PSCustomObject] $params)
    }

    $jobs | Format-Table -Property Id, Name, State, HasMoreData, PSBeginTime, PSEndTime
    $jobs | Receive-Job -Wait
    $jobs | Format-Table -Property Id, Name, State, HasMoreData, PSBeginTime, PSEndTime

    Remove-Item -LiteralPath $isoFilePathForConcurrency -Force

    'The base VHDs creation has been completed.' | Write-ScriptLog -Context $env:ComputerName
}
catch {
    $jobs | Format-Table -Property Id, Name, State, HasMoreData, PSBeginTime, PSEndTime
    throw $_
}
finally {
    Stop-ScriptLogging
}
