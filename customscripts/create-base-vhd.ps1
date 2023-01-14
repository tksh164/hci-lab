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

function CreateVhdFileFromIsoJobParameter
{
    param (
        [Parameter(Mandatory = $true)]
        [string] $SharedModulePath,

        [Parameter(Mandatory = $true)]
        [string] $ConvertWimModulePath,

        [Parameter(Mandatory = $true)]
        [string] $IsoFolder,

        [Parameter(Mandatory = $true)]
        [string] $UpdatesFolder,

        [Parameter(Mandatory = $true)]
        [string] $VhdFolder,

        [Parameter(Mandatory = $true)]
        [string] $OperatingSystem,

        [Parameter(Mandatory = $true)]
        [int] $ImageIndex,

        [Parameter(Mandatory = $true)]
        [string] $Culture,

        [Parameter(Mandatory = $true)]
        [string] $WorkFolder,

        [Parameter(Mandatory = $true)]
        [string] $LogFolder
    )

    $jobParams = @{
        SharedModulePath     = $SharedModulePath
        ConvertWimModulePath = $ConvertWimModulePath
        IsoFolder            = $IsoFolder
        VhdFolder            = $VhdFolder
        OperatingSystem      = $OperatingSystem
        ImageIndex           = $ImageIndex
        Culture              = $Culture
        WorkFolder           = $WorkFolder
        UpdatePackage        = @()
        LogFolder            = $LogFolder
    }

    $updatesFolderPath = [IO.Path]::Combine($UpdatesFolder, $OperatingSystem)
    if (Test-Path -PathType Container -LiteralPath $updatesFolderPath) {
        $jobParams.UpdatePackage += Get-ChildItem -LiteralPath $updatesFolderPath | Select-Object -ExpandProperty 'FullName'
    }
    
    $jobParams
}

function CreateVhdFileFromIsoAsJob
{
    $jobParams = $args[0]
    Import-Module -Name $jobParams.SharedModulePath -Force
    Import-Module -Name $jobParams.ConvertWimModulePath -Force

    # Create a VHD file.
    $params = @{
        SourcePath    = [IO.Path]::Combine($jobParams.IsoFolder, (BuildIsoFileName -OperatingSystem $jobParams.OperatingSystem -Culture $jobParams.Culture))
        Edition       = $jobParams.ImageIndex
        VHDPath       = [IO.Path]::Combine($jobParams.VhdFolder, (BuildBaseVhdFileName -OperatingSystem $jobParams.OperatingSystem -ImageIndex $jobParams.ImageIndex -Culture $jobParams.Culture))
        VHDFormat     = 'VHDX'
        IsFixed       = $false
        DiskLayout    = 'UEFI'
        SizeBytes     = 127GB
        TempDirectory = $jobParams.WorkFolder
        #Passthru      = $true
        Verbose       = $true
    }
    if ($jobParams.UpdatePackage.Count -ne 0) {
        $params.Package = $jobParams.UpdatePackage | Sort-Object
    }
    Convert-WindowsImage @params
    #$vhd = Convert-WindowsImage @params

    <#
    $dismExePath = Join-Path -Path $env:windir -ChildPath 'System32\dism.exe' -Resolve
    $vhdDisk = Mount-VHD -Path $vhd.ImagePath -Passthru | Get-Disk
    $vhdPartition = $vhdDisk | Get-Partition | Where-Object -Property IsHidden -EQ $false | Select-Object -First 1
    $volumeRootPath = '{0}:\\' -f $vhdPartition.DriveLetter  # Use \\ with intent because \ is meaning escape character in dism.

    # Cleanup the VHD file.
    $params = @{
        FilePath               = $dismExePath
        ArgumentList           = @(
            ('/Image:"{0}"' -f $volumeRootPath),
            '/Cleanup-Image',
            '/StartComponentCleanup',
            '/ResetBase',
            '/LogLevel:3',
            ('/LogPath:"{0}"' -f [IO.Path]::Combine($jobParams.LogFolder, ('{0}_{1}-cleanup-dism.txt' -f $jobParams.OperatingSystem, $jobParams.Culture)))
        )
        RedirectStandardOutput = [IO.Path]::Combine($jobParams.LogFolder, ('{0}_{1}-cleanup-stdout.txt' -f $jobParams.OperatingSystem, $jobParams.Culture))
        RedirectStandardError  = [IO.Path]::Combine($jobParams.LogFolder, ('{0}_{1}-cleanup-stderr.txt' -f $jobParams.OperatingSystem, $jobParams.Culture))
        NoNewWindow            = $true
        Wait                   = $true
        PassThru               = $true
        Verbose                = $true
    }
    Start-Process @params

    # Optimize the VHD file.
    $params = @{
        FilePath               = $dismExePath
        ArgumentList           = @(
            ('/Image:"{0}"' -f $volumeRootPath),
            '/Optimize-Image',
            '/Boot',
            '/LogLevel:3',
            ('/LogPath:"{0}"' -f [IO.Path]::Combine($jobParams.LogFolder, ('{0}_{1}-optimize-dism.txt' -f $jobParams.OperatingSystem, $jobParams.Culture)))
        )
        RedirectStandardOutput = [IO.Path]::Combine($jobParams.LogFolder, ('{0}_{1}-optimize-stdout.txt' -f $jobParams.OperatingSystem, $jobParams.Culture))
        RedirectStandardError  = [IO.Path]::Combine($jobParams.LogFolder, ('{0}_{1}-optimize-stderr.txt' -f $jobParams.OperatingSystem, $jobParams.Culture))
        NoNewWindow            = $true
        Wait                   = $true
        PassThru               = $true
        Verbose                = $true
    }
    Start-Process @params

    Dismount-VHD -DiskNumber $vhdDisk.DiskNumber
    #>
}

'Creating the temp folder if it does not exist...' | WriteLog -Context $env:ComputerName
New-Item -ItemType Directory -Path $configParams.labHost.folderPath.temp -Force

'Creating the VHD folder if it does not exist...' | WriteLog -Context $env:ComputerName
New-Item -ItemType Directory -Path $configParams.labHost.folderPath.vhd -Force

'Downloading the Convert-WindowsImage.ps1...' | WriteLog -Context $env:ComputerName
$params = @{
    SourceUri      = 'https://raw.githubusercontent.com/x0nn/Convert-WindowsImage/main/Convert-WindowsImage.ps1'
    DownloadFolder = $configParams.labHost.folderPath.temp
    FileNameToSave = 'Convert-WindowsImage.ps1'
}
$convertWimScriptFile = DownloadFile @params
$convertWimScriptFile

'Creating the base VHD creation jobs.' | WriteLog -Context $env:ComputerName
$jobs = @()

$params = @{
    SharedModulePath     = (Get-Module -Name 'shared').Path
    ConvertWimModulePath = $convertWimScriptFile.FullName
    IsoFolder            = $configParams.labHost.folderPath.temp
    UpdatesFolder        = $configParams.labHost.folderPath.updates
    VhdFolder            = $configParams.labHost.folderPath.vhd
    OperatingSystem      = $configParams.hciNode.operatingSystem
    ImageIndex           = $configParams.hciNode.imageIndex
    Culture              = $configParams.guestOS.culture
    WorkFolder           = $configParams.labHost.folderPath.temp
    LogFolder            = $configParams.labHost.folderPath.transcript
}
$jobParams = CreateVhdFileFromIsoJobParameter @params
$jobs += Start-Job -ArgumentList $jobParams -ScriptBlock ${function:CreateVhdFileFromIsoAsJob}

# Windows Server 2022 with Desktop Experience VHD is always used for the domain controller and Windows Admin Center VMs.
if (-not (($configParams.hciNode.operatingSystem -eq 'ws2022') -and ($configParams.hciNode.imageIndex -eq 4))) {
    $params = @{
        SharedModulePath     = (Get-Module -Name 'shared').Path
        ConvertWimModulePath = $convertWimScriptFile.FullName
        IsoFolder            = $configParams.labHost.folderPath.temp
        UpdatesFolder        = $configParams.labHost.folderPath.updates
        VhdFolder            = $configParams.labHost.folderPath.vhd
        OperatingSystem      = 'ws2022'
        ImageIndex           = 4  # Datacenter with Desktop Experience
        Culture              = $configParams.guestOS.culture
        WorkFolder           = $configParams.labHost.folderPath.temp
        LogFolder            = $configParams.labHost.folderPath.transcript
    }
    $jobParams = CreateVhdFileFromIsoJobParameter @params
    $jobs += Start-Job -ArgumentList $jobParams -ScriptBlock ${function:CreateVhdFileFromIsoAsJob}
}

'Waiting for the base VHD creation jobs.' | WriteLog -Context $env:ComputerName
$jobs | Format-Table -Property Id, Name, PSJobTypeName, State, HasMoreData, Location, PSBeginTime, PSEndTime
$jobs | Wait-Job
$jobs | Format-Table -Property Id, Name, PSJobTypeName, State, HasMoreData, Location, PSBeginTime, PSEndTime
$jobs | Receive-Job

'The base VHDs creation has been completed.' | WriteLog -Context $env:ComputerName

Stop-Transcript
