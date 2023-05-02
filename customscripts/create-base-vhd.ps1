[CmdletBinding()]
param ()

$ErrorActionPreference = [Management.Automation.ActionPreference]::Stop
$WarningPreference = [Management.Automation.ActionPreference]::Continue
$VerbosePreference = [Management.Automation.ActionPreference]::Continue
$ProgressPreference = [Management.Automation.ActionPreference]::SilentlyContinue

Import-Module -Name '.\shared.psm1' -Force

$labConfig = GetLabConfig
Start-ScriptTranscript -OutputDirectory $labConfig.labHost.folderPath.log -ScriptName $MyInvocation.MyCommand.Name
$labConfig | ConvertTo-Json -Depth 16

'Creating the temp folder if it does not exist...' | WriteLog -Context $env:ComputerName
New-Item -ItemType Directory -Path $labConfig.labHost.folderPath.temp -Force

'Creating the VHD folder if it does not exist...' | WriteLog -Context $env:ComputerName
New-Item -ItemType Directory -Path $labConfig.labHost.folderPath.vhd -Force

'Downloading the Convert-WindowsImage.ps1...' | WriteLog -Context $env:ComputerName
$params = @{
    SourceUri      = 'https://raw.githubusercontent.com/microsoft/MSLab/master/Tools/Convert-WindowsImage.ps1'
    DownloadFolder = $labConfig.labHost.folderPath.temp
    FileNameToSave = 'Convert-WindowsImage.ps1'
}
$convertWimScriptFile = DownloadFile @params
$convertWimScriptFile

# NOTE: Only one VHD file can create from the same single ISO file. The second VHD creation will fail if create
# multiple VHDs from the same single ISO because the ISO unmount when finish first one.
'Copying Windows Server ISO file...' | WriteLog -Context $env:ComputerName
$tempIsoFileNameSuffix = 'concurrent'
$ws2022SourceIsoFilePath = [IO.Path]::Combine($labConfig.labHost.folderPath.temp, (GetIsoFileName -OperatingSystem 'ws2022' -Culture $labConfig.guestOS.culture))
$ws2022TempIsoFilePath = [IO.Path]::Combine($labConfig.labHost.folderPath.temp, (GetIsoFileName -OperatingSystem 'ws2022' -Culture $labConfig.guestOS.culture -Suffix $tempIsoFileNameSuffix))
Copy-Item -LiteralPath $ws2022SourceIsoFilePath -Destination $ws2022TempIsoFilePath -Force -PassThru

'Creating the base VHD creation jobs.' | WriteLog -Context $env:ComputerName
$jobScriptFilePath = [IO.Path]::Combine($PSScriptRoot, 'create-base-vhd-job.ps1')
$jobs = @()

'Starting the HCI node base VHD creation job.' | WriteLog -Context $env:ComputerName
$params = [PSCustomObject] @{
    PSModuleNameToImport = (Get-Module -Name 'shared').Path, $convertWimScriptFile.FullName
    IsoFolder            = $labConfig.labHost.folderPath.temp
    OperatingSystem      = $labConfig.hciNode.operatingSystem.sku
    ImageIndex           = $labConfig.hciNode.operatingSystem.imageIndex
    Culture              = $labConfig.guestOS.culture
    VhdFolder            = $labConfig.labHost.folderPath.vhd
    UpdatesFolder        = $labConfig.labHost.folderPath.updates
    WorkFolder           = $labConfig.labHost.folderPath.temp
    LogFolder            = $labConfig.labHost.folderPath.log
    LogFileName          = 'create-base-vhd-job-hcinode'
}
$jobs += Start-Job -Name 'HCI node' -LiteralPath $jobScriptFilePath -InputObject $params

if (-not (($labConfig.hciNode.operatingSystem.sku -eq 'ws2022') -and ($labConfig.hciNode.operatingSystem.imageIndex -eq 4))) {
    # Use the Windows Server with Desktop Experience VHD for Windows Admin Center always.
    'Starting the Windows Server Desktop Experience base VHD creation job.' | WriteLog -Context $env:ComputerName
    $params = [PSCustomObject] @{
        PSModuleNameToImport = (Get-Module -Name 'shared').Path, $convertWimScriptFile.FullName
        IsoFolder            = $labConfig.labHost.folderPath.temp
        OperatingSystem      = 'ws2022'
        ImageIndex           = 4  # Datacenter with Desktop Experience
        Culture              = $labConfig.guestOS.culture
        VhdFolder            = $labConfig.labHost.folderPath.vhd
        UpdatesFolder        = $labConfig.labHost.folderPath.updates
        WorkFolder           = $labConfig.labHost.folderPath.temp
        LogFolder            = $labConfig.labHost.folderPath.log
        LogFileName          = 'create-base-vhd-job-wsgui'
    }
    $jobs += Start-Job -Name 'WS Desktop Experience' -LiteralPath $jobScriptFilePath -InputObject $params
}

if (-not (($labConfig.hciNode.operatingSystem.sku -eq 'ws2022') -and ($labConfig.hciNode.operatingSystem.imageIndex -eq 3))) {
    # Use the Windows Server Server Core VHD for AD DS domain controller always.
    'Starting the Windows Server Core base VHD creation job.' | WriteLog -Context $env:ComputerName
    $params = [PSCustomObject] @{
        PSModuleNameToImport = (Get-Module -Name 'shared').Path, $convertWimScriptFile.FullName
        IsoFolder            = $labConfig.labHost.folderPath.temp
        OperatingSystem      = 'ws2022'
        ImageIndex           = 3 # Datacenter (Server Core)
        IsoFileNameSuffix    = $tempIsoFileNameSuffix
        Culture              = $labConfig.guestOS.culture
        VhdFolder            = $labConfig.labHost.folderPath.vhd
        UpdatesFolder        = $labConfig.labHost.folderPath.updates
        WorkFolder           = $labConfig.labHost.folderPath.temp
        LogFolder            = $labConfig.labHost.folderPath.log
        LogFileName          = 'create-base-vhd-job-wscore'
    }
    $jobs += Start-Job -Name 'WS Server Core' -LiteralPath $jobScriptFilePath -InputObject $params
}

$jobs | Format-Table -Property Id, Name, State, HasMoreData, PSBeginTime, PSEndTime
$jobs | Receive-Job -Wait
$jobs | Format-Table -Property Id, Name, State, HasMoreData, PSBeginTime, PSEndTime

Remove-Item -LiteralPath $ws2022TempIsoFilePath -Force

'The base VHDs creation has been completed.' | WriteLog -Context $env:ComputerName

Stop-ScriptTranscript
