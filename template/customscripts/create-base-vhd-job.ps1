[CmdletBinding()]
param (
    [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
    [string[]] $ImportModulePath,

    [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
    [string] $LogFileName,

    [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
    [string] $LogContext,

    [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
    [string] $JobParamsJson
)

$ErrorActionPreference = [Management.Automation.ActionPreference]::Stop
$WarningPreference = [Management.Automation.ActionPreference]::Continue
$VerbosePreference = [Management.Automation.ActionPreference]::Continue
$ProgressPreference = [Management.Automation.ActionPreference]::SilentlyContinue

function Get-UpdatePackageFilePath {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateScript({ Test-Path -PathType Container -LiteralPath $_ })]
        [string] $UpdatePackageFolderPath
    )

    $updatePackagePaths = @()
    $updatePackagePaths += Get-ChildItem -LiteralPath $UpdatePackageFolderPath | Select-Object -ExpandProperty 'FullName' | Sort-Object
    return $updatePackagePaths
}

function Test-WimFile {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateScript({ Test-Path -PathType Leaf -LiteralPath $_ })]
        [string] $WimFilePath,

        [Parameter(Mandatory = $true)][ValidateRange(1, 20)]
        [int] $ImageIndex,

        [Parameter(Mandatory = $true)]
        [ValidateScript({ Test-Path -PathType Container -LiteralPath $_ })]
        [string] $ScratchDirectory,

        [Parameter(Mandatory = $true)]
        [string] $LogFilePath
    )

    $params = @{
        ImagePath        = $WimFilePath
        Index            = $ImageIndex
        ScratchDirectory = $ScratchDirectory
        LogPath          = $LogFilePath
    }
    $windowsImage = Get-WindowsImage @params
    return $windowsImage -ne $null
}

function Add-DriveLetterToPartition {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [Microsoft.Management.Infrastructure.CimInstance] $Partition
    )

    $isDriveLetterAssigned = $false
    $ATTEMPT_LIMIT = 20
    $workingPartition = $Partition
    for ($attempt = 0; $attempt -lt $ATTEMPT_LIMIT; $attempt++) {
        $workingPartition | Add-PartitionAccessPath -AssignDriveLetter
        $workingPartition = $workingPartition | Get-Partition
        if($workingPartition.DriveLetter -ne 0) {
            $isDriveLetterAssigned = $true
            break
        }

        'Could not assigna a drive letter. Try again.' | Write-ScriptLog
        $attempt++
        Start-Sleep -Seconds 5
    }

    if (-not $isDriveLetterAssigned) {
        throw 'Could not assign a drive letter to the partition (Type:{0}, DiskNumber:{1}, PartitionNumber:{2}, Size:{3}).' -f $Partition.Type, $Partition.DiskNumber, $Partition.PartitionNumber, $Partition.Size
    }

    return $workingPartition
}

function Set-VhdToBootable {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [char] $SystemVolumeDriveLetter,

        [Parameter(Mandatory = $true)]
        [char] $WindowsVolumeDriveLetter,

        [Parameter(Mandatory = $true)]
        [string] $LogFilePathStdout,

        [Parameter(Mandatory = $true)]
        [string] $LogFilePathStderr
    )

    $params = @{
        FilePath     = 'C:\Windows\System32\bcdboot.exe'
        ArgumentList = @(
            ('{0}:\Windows' -f $WindowsVolumeDriveLetter), # Specifies the location of the windows system root.
            ('/s {0}:' -f $SystemVolumeDriveLetter),       # Specifies an optional volume letter parameter to designate the target system partition where boot environment files are copied.
            '/f UEFI',                                     # Specifies the firmware type of the target system partition.
            '/v'                                           # Enables verbose mode.
        )
        RedirectStandardOutput = $LogFilePathStdout
        RedirectStandardError  = $LogFilePathStderr
        NoNewWindow            = $true
        Wait                   = $true
        Passthru               = $true
    }
    $result = Start-Process @params

    if ($result.ExitCode -ne 0) {
        throw 'The bcdboot.exe failed with exit code {0}.' -f $result.ExitCode
    }
}

try {
    # Mandatory pre-processing.
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    Import-Module -Name $ImportModulePath -Force
    $labConfig = Get-LabDeploymentConfig
    Start-ScriptLogging -OutputDirectory $labConfig.labHost.folderPath.log -FileName $LogFileName
    Set-ScriptLogDefaultContext -LogContext $LogContext
    'Lab deployment config: {0}' -f ($labConfig | ConvertTo-Json -Depth 16) | Write-ScriptLog

    # Log the job parameters.
    'Job parameters:' | Write-ScriptLog
    foreach ($key in $PSBoundParameters.Keys) {
        if ($PSBoundParameters[$key].GetType().FullName -eq 'System.String[]') {
            '- {0}: {1}' -f $key, ($PSBoundParameters[$key] -join ',') | Write-ScriptLog
        }
        else {
            '- {0}: {1}' -f $key, $PSBoundParameters[$key] | Write-ScriptLog
        }
    }

    # Retrieve the job parameters from the JSON string.
    $jobParams = $JobParamsJson | ConvertFrom-Json

    # Retrieve the update package file paths.
    if ([string]::IsNullOrEmpty($jobParams.UpdatePackageFolderPath)) {
        $updatePackageFilePaths = @()
        'No update packages to be applied.' | Write-ScriptLog
    }
    else {
        $updatePackageFilePaths = Get-UpdatePackageFilePath -UpdatePackageFolderPath $jobParams.UpdatePackageFolderPath
        '{0} update packages to be applied.' -f $updatePackageFilePaths.Length | Write-ScriptLog
    }

    'Validate the WIM file "{0}" with the image index {1}.' -f $jobParams.WimFilePath, $jobParams.ImageIndex | Write-ScriptLog
    $params = @{
        WimFilePath      = $jobParams.WimFilePath
        ImageIndex       = $jobParams.ImageIndex
        ScratchDirectory = $labConfig.labHost.folderPath.temp
        LogFilePath      = [System.IO.Path]::Combine($labConfig.labHost.folderPath.log, (New-LogFileName -FileName ($LogFileName + '_test-wim')))
    }
    if (-not (Test-WimFile @params)) {
        throw 'The specified WIM file "{0}" has not a valid WIM file with image index {1}.' -f $jobParams.WimFilePath, $jobParams.ImageIndex
    }
    'The WIM file "{0}" with the image index {1} is valid.' -f $jobParams.WimFilePath, $jobParams.ImageIndex | Write-ScriptLog

    'Create a new VHD file.' | Write-ScriptLog
    $params = @{
        Path                    = $jobParams.VhdFilePath
        Dynamic                 = $true
        SizeBytes               = 500GB
        BlockSizeBytes          = 128MB
        PhysicalSectorSizeBytes = 4KB
        LogicalSectorSizeBytes  = 512
    }
    $vhd = New-VHD @params
    Get-Item -LiteralPath $vhd.Path | Format-List -Property 'Name', 'FullName', 'Length', 'LastWriteTimeUtc' | Out-String -Width 200 | Write-ScriptLog
    'Create a new VHD file has been completed.' | Write-ScriptLog

    'Mount the VHD file.' | Write-ScriptLog
    $disk = $vhd | Mount-VHD -PassThru | Get-Disk
    'Mount the VHD file has been completed.' | Write-ScriptLog

    'Initialize the VHD.' | Write-ScriptLog
    $disk | Initialize-Disk -PartitionStyle GPT
    'Initialize the VHD has been completed.' | Write-ScriptLog

    # The partition type GUIDs.
    $PARTITION_SYSTEM_GUID = '{c12a7328-f81f-11d2-ba4b-00a0c93ec93b}'
    $PARTITION_MSFT_RESERVED_GUID = '{e3c9e316-0b5c-4db8-817d-f92df00215ae}'
    $PARTITION_BASIC_DATA_GUID = '{ebd0a0a2-b9e5-4433-87c0-68b6b72699c7}'

    'Create an EFI system partition.' | Write-ScriptLog
    $systemPartition = $disk | New-Partition -GptType $PARTITION_SYSTEM_GUID -Size 200MB
    'Create an EFI system partition has been completed.' | Write-ScriptLog

    'Create a Microsoft reserved partition.' | Write-ScriptLog
    $disk | New-Partition -GptType $PARTITION_MSFT_RESERVED_GUID -Size 16MB | Out-Null
    'Create a Microsoft reserved partition has been completed.' | Write-ScriptLog

    'Create a Windows partition.' | Write-ScriptLog
    $windowsPartition = $disk | New-Partition -GptType $PARTITION_BASIC_DATA_GUID -UseMaximumSize
    'Create a Windows partition has been completed.' | Write-ScriptLog

    'Format the EFI system partition.' | Write-ScriptLog
    $systemVolume = $systemPartition | Format-Volume -FileSystem 'FAT32' -AllocationUnitSize 512 -Confirm:$false -Force
    'Format the EFI system partition has been completed.' | Write-ScriptLog

    'Format the Windows partition.' | Write-ScriptLog
    $windowsVolume = $windowsPartition | Format-Volume -FileSystem 'NTFS' -AllocationUnitSize 4KB -Confirm:$false -Force
    'Format the Windows partition has been completed.' | Write-ScriptLog

    'Assign a drive letter to the EFI system partition.' | Write-ScriptLog
    $systemPartition = Add-DriveLetterToPartition -Partition $systemPartition
    'Assign a drive letter to the EFI system partition has been completed.' | Write-ScriptLog

    $systemVolumeDriveLetter = (Get-Partition -Volume $systemVolume | Get-Volume).DriveLetter
    'The EFI system partition''s drive letter is "{0}".' -f $systemVolumeDriveLetter | Write-ScriptLog

    'Assign a drive letter to the Windows partition.' | Write-ScriptLog
    $windowsPartition = Add-DriveLetterToPartition -Partition $windowsPartition
    'Assign a drive letter to the Windows partition has been completed.' | Write-ScriptLog

    $windowsVolumeDriveLetter = (Get-Partition -Volume $windowsVolume | Get-Volume).DriveLetter
    'The Windows partition''s drive letter is "{0}".' -f $windowsVolumeDriveLetter | Write-ScriptLog

    'Expand the Windows image to the Windows partition.' | Write-ScriptLog
    $params = @{
        ApplyPath        = ('{0}:' -f $windowsVolumeDriveLetter)
        ImagePath        = $jobParams.WimFilePath
        Index            = $jobParams.ImageIndex
        ScratchDirectory = $labConfig.labHost.folderPath.temp
        LogPath          = [System.IO.Path]::Combine($labConfig.labHost.folderPath.log, (New-LogFileName -FileName ($LogFileName + '_expand-image')))
        LogLevel         = 'Debug'
    }
    Expand-WindowsImage @params | Out-String -Width 200 | Write-ScriptLog
    'Expand the Windows image to the Windows partition has been completed.' | Write-ScriptLog

    'The new VHD to bootable.' | Write-ScriptLog
    $params = @{
        SystemVolumeDriveLetter  = $systemVolumeDriveLetter
        WindowsVolumeDriveLetter = $windowsVolumeDriveLetter
        LogFilePathStdout        = [System.IO.Path]::Combine($labConfig.labHost.folderPath.log, (New-LogFileName -FileName ($LogFileName + '_bcdboot-stdout')))
        LogFilePathStderr        = [System.IO.Path]::Combine($labConfig.labHost.folderPath.log, (New-LogFileName -FileName ($LogFileName + '_bcdboot-stderr')))
    }
    Set-VhdToBootable @params
    'The new VHD to bootable has been completed.' | Write-ScriptLog

    if ($updatePackageFilePaths.Length -gt 0) {
        'Add {0} update packages to the VHD.' -f $updatePackageFilePaths.Length | Write-ScriptLog
        $logFilePath = [System.IO.Path]::Combine($labConfig.labHost.folderPath.log, (New-LogFileName -FileName ($LogFileName + '_add-package')))
        foreach ($packageFilePath in $updatePackageFilePaths) {
            'Add an update package "{0}" to the VHD.' -f $packageFilePath | Write-ScriptLog
            $params = @{
                Path             = ('{0}:' -f $windowsVolumeDriveLetter)
                PackagePath      = $packageFilePath
                ScratchDirectory = $labConfig.labHost.folderPath.temp
                LogPath          = $logFilePath
                LogLevel         = 'Debug'
            }
            Add-WindowsPackage @params | Out-String -Width 200 | Write-ScriptLog
            'Add an update package "{0}" to the VHD has been completed.' -f $packageFilePath | Write-ScriptLog
        }
        'Add update packages to the VHD has been completed.' | Write-ScriptLog
    }

    'The created VHD file: {0}' -f (Get-VHD -Path $vhd.Path | Format-List -Property '*' | Out-String -Width 200) | Write-ScriptLog

    'This script has been completed all tasks.' | Write-ScriptLog
}
catch {
    $exceptionMessage = New-ExceptionMessage -ErrorRecord $_
    $exceptionMessage | Write-ScriptLog -Level Error
    throw $exceptionMessage
}
finally {
    if ($vhd -and ($vhd | Get-VHD).Attached) {
        'Dismount the VHD "{0}".' -f $vhd.Path | Write-ScriptLog
        $vhd | Dismount-VHD
    }

    # Mandatory post-processing.
    $stopWatch.Stop()
    'Script duration: {0}' -f $stopWatch.Elapsed.toString('hh\:mm\:ss') | Write-ScriptLog
    Stop-ScriptLogging
}
