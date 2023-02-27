[CmdletBinding()]
param ()

$ErrorActionPreference = [Management.Automation.ActionPreference]::Stop
$WarningPreference = [Management.Automation.ActionPreference]::Continue
$VerbosePreference = [Management.Automation.ActionPreference]::Continue
$ProgressPreference = [Management.Automation.ActionPreference]::SilentlyContinue

Import-Module -Name '.\shared.psm1' -Force

$labConfig = GetConfigParameters
Start-ScriptTranscript -OutputDirectory $labConfig.labHost.folderPath.log -ScriptName $MyInvocation.MyCommand.Name
$labConfig | ConvertTo-Json -Depth 16

function BuildJobParameters
{
    param (
        [Parameter(Mandatory = $true)]
        [string[]] $ImportModules,

        [Parameter(Mandatory = $true)]
        [string] $IsoFolder,

        [Parameter(Mandatory = $true)]
        [string] $VhdFolder,

        [Parameter(Mandatory = $true)]
        [string] $UpdatesFolder,

        [Parameter(Mandatory = $true)]
        [string] $OperatingSystem,

        [Parameter(Mandatory = $true)]
        [int] $ImageIndex,

        [Parameter(Mandatory = $true)]
        [string] $Culture,

        [Parameter(Mandatory = $true)]
        [string] $WorkFolder,

        [Parameter(Mandatory = $false)]
        [string] $IsoFileNameSuffix
    )

    $jobParams = @{
        ImportModules = $ImportModules
        SourcePath    = if ($PSBoundParameters.Keys.Contains('IsoFileNameSuffix')) {
            [IO.Path]::Combine($IsoFolder, (BuildIsoFileName -OperatingSystem $OperatingSystem -Culture $Culture -Suffix $IsoFileNameSuffix))
        }
        else {
            [IO.Path]::Combine($IsoFolder, (BuildIsoFileName -OperatingSystem $OperatingSystem -Culture $Culture))
        }
        ImageIndex    = $ImageIndex
        VhdPath       = [IO.Path]::Combine($VhdFolder, (BuildBaseVhdFileName -OperatingSystem $OperatingSystem -ImageIndex $ImageIndex -Culture $Culture))
        UpdatePackage = @()
        WorkFolder    = $WorkFolder
    }

    # Add update package paths if the update packages exist.
    $updatesFolderPath = [IO.Path]::Combine($UpdatesFolder, $OperatingSystem)
    if (Test-Path -PathType Container -LiteralPath $updatesFolderPath) {
        $jobParams.UpdatePackage += Get-ChildItem -LiteralPath $updatesFolderPath | Select-Object -ExpandProperty 'FullName' | Sort-Object
    }
    
    $jobParams
}

function CreateBaseVhdFromIsoAsJob
{
    $jobParams = $args[0]
    Import-Module -Name $jobParams.ImportModules -Force

    $params = @{
        SourcePath    = $jobParams.SourcePath
        Edition       = $jobParams.ImageIndex
        VHDPath       = $jobParams.VhdPath
        VHDFormat     = 'VHDX'
        DiskLayout    = 'UEFI'
        SizeBytes     = 40GB
        TempDirectory = $jobParams.WorkFolder
        Verbose       = $true
    }
    if ($jobParams.UpdatePackage.Count -ne 0) {
        $params.Package = $jobParams.UpdatePackage
    }
    Convert-WindowsImage @params
}

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
'Copying Windows Server 2022 ISO file...' | WriteLog -Context $env:ComputerName
$tempIsoFileNameSuffix = 'temp'
$ws2022SourceIsoFilePath = [IO.Path]::Combine($labConfig.labHost.folderPath.temp, (BuildIsoFileName -OperatingSystem 'ws2022' -Culture $labConfig.guestOS.culture))
$ws2022TempIsoFilePath = [IO.Path]::Combine($labConfig.labHost.folderPath.temp, (BuildIsoFileName -OperatingSystem 'ws2022' -Culture $labConfig.guestOS.culture -Suffix $tempIsoFileNameSuffix))
Copy-Item -LiteralPath $ws2022SourceIsoFilePath -Destination $ws2022TempIsoFilePath -Force -PassThru

'Creating the base VHD creation jobs.' | WriteLog -Context $env:ComputerName
$jobs = @()

$params = @{
    ImportModules   = (Get-Module -Name 'shared').Path, $convertWimScriptFile.FullName
    IsoFolder       = $labConfig.labHost.folderPath.temp
    VhdFolder       = $labConfig.labHost.folderPath.vhd
    UpdatesFolder   = $labConfig.labHost.folderPath.updates
    OperatingSystem = $labConfig.hciNode.operatingSystem.sku
    ImageIndex      = $labConfig.hciNode.operatingSystem.imageIndex
    Culture         = $labConfig.guestOS.culture
    WorkFolder      = $labConfig.labHost.folderPath.temp
}
$jobs += Start-Job -Name 'HCI node' -ScriptBlock ${function:CreateBaseVhdFromIsoAsJob} -ArgumentList (BuildJobParameters @params)

if (-not (($labConfig.hciNode.operatingSystem.sku -eq 'ws2022') -and ($labConfig.hciNode.operatingSystem.imageIndex -eq 3))) {
    # Use the Windows Server Server Core VHD for AD DS domain controller always.
    $params = @{
        ImportModules   = (Get-Module -Name 'shared').Path, $convertWimScriptFile.FullName
        IsoFolder       = $labConfig.labHost.folderPath.temp
        VhdFolder       = $labConfig.labHost.folderPath.vhd
        UpdatesFolder   = $labConfig.labHost.folderPath.updates
        OperatingSystem = 'ws2022'
        ImageIndex      = 3 # Datacenter (Server Core)
        Culture         = $labConfig.guestOS.culture
        WorkFolder      = $labConfig.labHost.folderPath.temp
    }
    $jobs += Start-Job -Name 'WS Server Core' -ScriptBlock ${function:CreateBaseVhdFromIsoAsJob} -ArgumentList (BuildJobParameters @params)
}

if (-not (($labConfig.hciNode.operatingSystem.sku -eq 'ws2022') -and ($labConfig.hciNode.operatingSystem.imageIndex -eq 4))) {
    # Use the Windows Server with Desktop Experience VHD for Windows Admin Center always.
    $params = @{
        ImportModules     = (Get-Module -Name 'shared').Path, $convertWimScriptFile.FullName
        IsoFolder         = $labConfig.labHost.folderPath.temp
        VhdFolder         = $labConfig.labHost.folderPath.vhd
        UpdatesFolder     = $labConfig.labHost.folderPath.updates
        OperatingSystem   = 'ws2022'
        ImageIndex        = 4  # Datacenter with Desktop Experience
        Culture           = $labConfig.guestOS.culture
        WorkFolder        = $labConfig.labHost.folderPath.temp
        IsoFileNameSuffix = $tempIsoFileNameSuffix
    }
    $jobs += Start-Job -Name 'WS Desktop Experience' -ScriptBlock ${function:CreateBaseVhdFromIsoAsJob} -ArgumentList (BuildJobParameters @params)
}

$jobs | Format-Table -Property Id, Name, State, HasMoreData, PSBeginTime, PSEndTime
$jobs | Receive-Job -Wait
$jobs | Format-Table -Property Id, Name, State, HasMoreData, PSBeginTime, PSEndTime

Remove-Item -LiteralPath $ws2022TempIsoFilePath -Force

'The base VHDs creation has been completed.' | WriteLog -Context $env:ComputerName

Stop-ScriptTranscript
