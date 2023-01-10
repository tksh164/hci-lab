[CmdletBinding()]
param ()

$ErrorActionPreference = [Management.Automation.ActionPreference]::Stop
$WarningPreference = [Management.Automation.ActionPreference]::Continue
$VerbosePreference = [Management.Automation.ActionPreference]::Continue
$ProgressPreference = [Management.Automation.ActionPreference]::SilentlyContinue

Import-Module -Name '.\shared.psm1' -Force

$configParams = GetConfigParameters
Start-Transcript -OutputDirectory $configParams.labHost.folderPath.transcript
$configParams | ConvertTo-Json -Depth 16

function CreateVhdFileFromIso
{
    param (
        [Parameter(Mandatory = $true)]
        [string] $IsoFolder,

        [Parameter(Mandatory = $true)]
        [string] $VhdFolder,

        [Parameter(Mandatory = $true)]
        [string] $OperatingSystem,

        [Parameter(Mandatory = $true)]
        [string] $Culture,

        [Parameter(Mandatory = $true)]
        [int] $ImageIndex,

        [Parameter(Mandatory = $true)]
        [string] $WorkFolder,

        [Parameter(Mandatory = $false)]
        [string[]] $UpdatePackage = @()
    )

    $params = @{
        SourcePath    = [IO.Path]::Combine($IsoFolder, ('{0}_{1}.iso' -f $OperatingSystem, $Culture))
        Edition       = $ImageIndex
        VHDPath       = [IO.Path]::Combine($VhdFolder, ('{0}_{1}.vhdx' -f $OperatingSystem, $Culture))
        VHDFormat     = 'VHDX'
        IsFixed       = $false
        DiskLayout    = 'UEFI'
        SizeBytes     = 127GB
        TempDirectory = $WorkFolder
        Passthru      = $true
        Verbose       = $true
    }
    if ($UpdatePackage.Length -ne 0) {
        $params.Package = $UpdatePackage | Sort-Object
    }
    Convert-WindowsImage @params
}

WriteLog -Context $env:ComputerName -Message 'Creating the temp folder if it does not exist...'
New-Item -ItemType Directory -Path $configParams.labHost.folderPath.temp -Force

WriteLog -Context $env:ComputerName -Message 'Creating the VHD folder if it does not exist...'
New-Item -ItemType Directory -Path $configParams.labHost.folderPath.vhd -Force

WriteLog -Context $env:ComputerName -Message 'Downloading the Convert-WindowsImage.ps1...'
$params = @{
    SourceUri      = 'https://raw.githubusercontent.com/x0nn/Convert-WindowsImage/main/Convert-WindowsImage.ps1'
    DownloadFolder = $configParams.labHost.folderPath.temp
    FileNameToSave = 'Convert-WindowsImage.ps1'
}
$convertWimScriptFile = DownloadFile @params
$convertWimScriptFile

WriteLog -Context $env:ComputerName -Message 'Importing the Convert-WindowsImage.ps1...'
Import-Module -Name $convertWimScriptFile.FullName -Force

$updatesFolderPath = [IO.Path]::Combine($configParams.labHost.folderPath.updates, $configParams.hciNode.operatingSystem)
$params = @{
    IsoFolder       = $configParams.labHost.folderPath.temp
    VhdFolder       = $configParams.labHost.folderPath.vhd
    OperatingSystem = $configParams.hciNode.operatingSystem
    Culture         = $configParams.guestOS.culture
    ImageIndex      = $configParams.hciNode.imageIndex
    WorkFolder      = $configParams.labHost.folderPath.temp
}
if (Test-Path -PathType Container -LiteralPath $updatesFolderPath) {
    $params.UpdatePackage = Get-ChildItem -LiteralPath $updatesFolderPath | Select-Object -ExpandProperty 'FullName'
}
CreateVhdFileFromIso @params

if ($configParams.hciNode.operatingSystem -ne 'ws2022') {
    # The Windows Server 2022 VHD is always needed for the domain controller VM.
    $updatesFolderPath = [IO.Path]::Combine($configParams.labHost.folderPath.updates, 'ws2022')
    $params = @{
        IsoFolder       = $configParams.labHost.folderPath.temp
        VhdFolder       = $configParams.labHost.folderPath.vhd
        OperatingSystem = 'ws2022'
        Culture         = $configParams.guestOS.culture
        ImageIndex      = 4  # Datacenter with Desktop Experience
        WorkFolder      = $configParams.labHost.folderPath.temp
    }
    if (Test-Path -PathType Container -LiteralPath $updatesFolderPath) {
        $params.UpdatePackage = Get-ChildItem -LiteralPath $updatesFolderPath | Select-Object -ExpandProperty 'FullName'
    }
    CreateVhdFileFromIso @params
}

WriteLog -Context $env:ComputerName -Message 'The base VHDs creation has been completed.'

Stop-Transcript
