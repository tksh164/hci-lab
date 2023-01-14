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
        [string] $ModulePath,

        [Parameter(Mandatory = $true)]
        [string] $IsoFolder,

        [Parameter(Mandatory = $true)]
        [string] $UpdatesFolder,

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

        [Parameter(Mandatory = $true)]
        [string] $LogFolder
    )

    $jobParams = @{
        ModulePath      = $ModulePath
        IsoFolder       = $IsoFolder
        VhdFolder       = $VhdFolder
        OperatingSystem = $OperatingSystem
        Culture         = $Culture
        ImageIndex      = $ImageIndex
        WorkFolder      = $WorkFolder
        UpdatePackage   = @()
        LogFolder       = $LogFolder
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
    Import-Module -Name $jobParams.ModulePath -Force

    # Create a VHD file.
    $params = @{
        SourcePath    = [IO.Path]::Combine($jobParams.IsoFolder, ('{0}_{1}.iso' -f $jobParams.OperatingSystem, $jobParams.Culture))
        Edition       = $jobParams.ImageIndex
        VHDPath       = [IO.Path]::Combine($jobParams.VhdFolder, ('{0}_{1}.vhdx' -f $jobParams.OperatingSystem, $jobParams.Culture))
        VHDFormat     = 'VHDX'
        IsFixed       = $false
        DiskLayout    = 'UEFI'
        SizeBytes     = 127GB
        TempDirectory = $jobParams.WorkFolder
        Passthru      = $true
        Verbose       = $true
    }
    if ($jobParams.UpdatePackage.Count -ne 0) {
        $params.Package = $jobParams.UpdatePackage | Sort-Object
    }
    $vhd = Convert-WindowsImage @params

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
    ModulePath      = $convertWimScriptFile.FullName
    IsoFolder       = $configParams.labHost.folderPath.temp
    UpdatesFolder   = $configParams.labHost.folderPath.updates
    VhdFolder       = $configParams.labHost.folderPath.vhd
    OperatingSystem = $configParams.hciNode.operatingSystem
    Culture         = $configParams.guestOS.culture
    ImageIndex      = $configParams.hciNode.imageIndex
    WorkFolder      = $configParams.labHost.folderPath.temp
    LogFolder       = $configParams.labHost.folderPath.transcript
}
$jobParams = CreateVhdFileFromIsoJobParameter @params
$jobs += Start-Job -ArgumentList $jobParams -ScriptBlock ${function:CreateVhdFileFromIsoAsJob}

if ($configParams.hciNode.operatingSystem -ne 'ws2022') {
    # The Windows Server 2022 VHD is always needed for the domain controller VM.
    $params = @{
        ModulePath      = $convertWimScriptFile.FullName
        IsoFolder       = $configParams.labHost.folderPath.temp
        UpdatesFolder   = $configParams.labHost.folderPath.updates
        VhdFolder       = $configParams.labHost.folderPath.vhd
        OperatingSystem = 'ws2022'
        Culture         = $configParams.guestOS.culture
        ImageIndex      = 4  # Datacenter with Desktop Experience
        WorkFolder      = $configParams.labHost.folderPath.temp
        LogFolder       = $configParams.labHost.folderPath.transcript
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
