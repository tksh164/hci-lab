[CmdletBinding()]
param (
    [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
    [string[]] $PSModulePathToImport,

    [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
    [string] $LogFileName,

    [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
    [string] $LogContext,

    [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
    [string] $WimFilePath,

    [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
    [ValidateRange(1, 20)]
    [int] $ImageIndex,

    [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
    [string] $VhdFilePath,

    [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
    [string[]] $UpdatePackagePath = @()
)

$ErrorActionPreference = [Management.Automation.ActionPreference]::Stop
$WarningPreference = [Management.Automation.ActionPreference]::Continue
$VerbosePreference = [Management.Automation.ActionPreference]::Continue
$ProgressPreference = [Management.Automation.ActionPreference]::SilentlyContinue

function Test-WimFile
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string] $WimFilePath,

        [Parameter(Mandatory = $true)][ValidateRange(1, 20)]
        [int] $ImageIndex,

        [Parameter(Mandatory = $true)]
        [string] $ScratchDirectory,

        [Parameter(Mandatory = $true)]
        [string] $LogFilePath
    )

    if (-not (Test-Path -PathType Leaf -LiteralPath $WimFilePath)) {
        throw 'Cannot find the specified file "{0}".' -f $WimFilePath
    }

    $params = @{
        ImagePath        = $WimFilePath
        Index            = $ImageIndex
        ScratchDirectory = $ScratchDirectory
        LogPath          = $LogFilePath
    }
    $windowsImage = Get-WindowsImage @params
    return $windowsImage -ne $null
}

function Add-DriveLetterToPartition
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [Microsoft.Management.Infrastructure.CimInstance] $Partition
    )

    $isDriveLetterAssigned = $false
    $attempts = 0
    $workingPartition = $Partition
    do {
        $workingPartition | Add-PartitionAccessPath -AssignDriveLetter
        $workingPartition = $workingPartition | Get-Partition
        if($workingPartition.DriveLetter -ne 0)
        {
            $isDriveLetterAssigned = $true
            break
        }

        'Could not assigna a drive letter. Try again.' | Write-ScriptLog
        Get-Random -Minimum 1 -Maximum 5 | Start-Sleep
        $attempts++
    } while ($attempts -lt 20)

    if (-not($isDriveLetterAssigned)) {
        throw 'Could not assign a drive letter to the partition (Type:{0}, DiskNumber:{1}, PartitionNumber:{2}, Size:{3}).' -f $Partition.Type, $Partition.DiskNumber, $Partition.PartitionNumber, $Partition.Size
    }

    return $workingPartition
}

function Resolve-LogFilePath
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string] $FolderPath,

        [Parameter(Mandatory = $true)]
        [string] $LogFileName
    )

    $logFileNameWithTimestamp = (Get-Date -Format 'yyyyMMdd-HHmmss') + '_' + $env:ComputerName + '_' + $LogFileName
    return [IO.Path]::Combine($FolderPath, $logFileNameWithTimestamp)
}

function Set-VhdToBootable
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [char] $SystemVolumeDriveLetter,

        [Parameter(Mandatory = $true)]
        [char] $WindowsVolumeDriveLetter,

        [Parameter(Mandatory = $true)]
        [string] $LogFilePathForStandardOutput,

        [Parameter(Mandatory = $true)]
        [string] $LogFilePathForStandardError
    )

    $params = @{
        FilePath     = 'C:\Windows\System32\bcdboot.exe'
        ArgumentList = @(
            ('{0}:\Windows' -f $WindowsVolumeDriveLetter), # Specifies the location of the windows system root.
            ('/s {0}:' -f $SystemVolumeDriveLetter),       # Specifies an optional volume letter parameter to designate the target system partition where boot environment files are copied.
            '/f UEFI',                                     # Specifies the firmware type of the target system partition.
            '/v'                                           # Enables verbose mode.
        )
        RedirectStandardOutput = $LogFilePathForStandardOutput
        RedirectStandardError  = $LogFilePathForStandardError
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
    Import-Module -Name $PSModulePathToImport -Force

    $labConfig = Get-LabDeploymentConfig
    Start-ScriptLogging -OutputDirectory $labConfig.labHost.folderPath.log -FileName $LogFileName
    Set-ScriptLogDefaultContext -LogContext $LogContext

    # Log the job parameters.
    'PSModulePathToImport:' | Write-ScriptLog
    foreach ($modulePath in $PSModulePathToImport) { '  "{0}"' -f $modulePath | Write-ScriptLog }
    'LogFileName: {0}' -f $LogFileName | Write-ScriptLog
    'LogContext: {0}' -f $LogContext | Write-ScriptLog
    'WimFilePath: "{0}"' -f $WimFilePath | Write-ScriptLog
    'ImageIndex: {0}' -f $ImageIndex | Write-ScriptLog
    'VhdFilePath: "{0}"' -f $VhdFilePath | Write-ScriptLog
    'UpdatePackagePath ({0}):' -f $UpdatePackagePath.Length | Write-ScriptLog
    foreach ($packagePath in $UpdatePackagePath) { '  "{0}"' -f $packagePath | Write-ScriptLog }

    # Log the lab deployment configuration.
    'Lab deployment config:' | Write-ScriptLog
    $labConfig | ConvertTo-Json -Depth 16 | Write-Host
    
    'Start to create a new base VHD from the "{0}" with the image index {1}.' -f $WimFilePath, $ImageIndex | Write-ScriptLog
    $params = @{
        WimFilePath      = $WimFilePath
        ImageIndex       = $ImageIndex
        ScratchDirectory = $labConfig.labHost.folderPath.temp
        LogFilePath      = Resolve-LogFilePath -FolderPath $labConfig.labHost.folderPath.log -LogFileName ($LogFileName + '_test-image.log')
    }
    if (-not (Test-WimFile @params)) {
        throw 'The specified Windows image "{0}" has not the image index {1}.' -f $WimFilePath, $ImageIndex
    }
    
    'Create a new VHD file.' | Write-ScriptLog
    $params = @{
        Path                    = $VhdFilePath
        Dynamic                 = $true
        SizeBytes               = 500GB
        BlockSizeBytes          = 128MB
        PhysicalSectorSizeBytes = 4KB
        LogicalSectorSizeBytes  = 512
    }
    $vhd = New-VHD @params
    Get-Item -LiteralPath $vhd.Path | Format-List -Property 'Name','FullName','Length','LastWriteTimeUtc' | Out-String -Width 200 | Write-ScriptLog
    'Create a new VHD file completed.' | Write-ScriptLog

    'Mount the VHD file.' | Write-ScriptLog
    $disk = $vhd | Mount-VHD -PassThru | Get-Disk
    'Mount the VHD file completed.' | Write-ScriptLog

    'Initialize the VHD.' | Write-ScriptLog
    $disk | Initialize-Disk -PartitionStyle GPT
    'Initialize the VHD completed.' | Write-ScriptLog

    # The partition type GUIDs.
    $PARTITION_SYSTEM_GUID = '{c12a7328-f81f-11d2-ba4b-00a0c93ec93b}'
    $PARTITION_MSFT_RESERVED_GUID = '{e3c9e316-0b5c-4db8-817d-f92df00215ae}'
    $PARTITION_BASIC_DATA_GUID = '{ebd0a0a2-b9e5-4433-87c0-68b6b72699c7}'

    'Create an EFI system partition.' | Write-ScriptLog
    $systemPartition = $disk | New-Partition -GptType $PARTITION_SYSTEM_GUID -Size 200MB
    'Create an EFI system partition completed.' | Write-ScriptLog

    'Create a Microsoft reserved partition.' | Write-ScriptLog
    $disk | New-Partition -GptType $PARTITION_MSFT_RESERVED_GUID -Size 16MB | Out-Null
    'Create a Microsoft reserved partition completed.' | Write-ScriptLog

    'Create a Windows partition.' | Write-ScriptLog
    $windowsPartition = $disk | New-Partition -GptType $PARTITION_BASIC_DATA_GUID -UseMaximumSize
    'Create a Windows partition completed.' | Write-ScriptLog

    'Format the EFI system partition.' | Write-ScriptLog
    $systemVolume = $systemPartition | Format-Volume -FileSystem 'FAT32' -AllocationUnitSize 512 -Confirm:$false -Force
    'Format the EFI system partition completed.' | Write-ScriptLog

    'Format the Windows partition.' | Write-ScriptLog
    $windowsVolume = $windowsPartition | Format-Volume -FileSystem 'NTFS' -AllocationUnitSize 4KB -Confirm:$false -Force
    'Format the Windows partition completed.' | Write-ScriptLog

    'Assign a drive letter to the EFI system partition.' | Write-ScriptLog
    $systemPartition = Add-DriveLetterToPartition -Partition $systemPartition
    'Assign a drive letter to the EFI system partition completed.' | Write-ScriptLog

    $systemVolumeDriveLetter = (Get-Partition -Volume $systemVolume | Get-Volume).DriveLetter
    'The EFI system partition''s drive letter is "{0}".' -f $systemVolumeDriveLetter | Write-ScriptLog

    'Assign a drive letter to the Windows partition.' | Write-ScriptLog
    $windowsPartition = Add-DriveLetterToPartition -Partition $windowsPartition
    'Assign a drive letter to the Windows partition completed.' | Write-ScriptLog

    $windowsVolumeDriveLetter = (Get-Partition -Volume $windowsVolume | Get-Volume).DriveLetter
    'The Windows partition''s drive letter is "{0}".' -f $windowsVolumeDriveLetter | Write-ScriptLog

    'Expand the Windows image to the Windows partition.' | Write-ScriptLog
    $params = @{
        ApplyPath        = ('{0}:' -f $windowsVolumeDriveLetter)
        ImagePath        = $WimFilePath
        Index            = $ImageIndex
        ScratchDirectory = $labConfig.labHost.folderPath.temp
        LogPath          = Resolve-LogFilePath -FolderPath $labConfig.labHost.folderPath.log -LogFileName ($LogFileName + '_expand-image.log')
        LogLevel         = 'Debug'
    }
    Expand-WindowsImage @params | Out-String -Width 200 | Write-ScriptLog
    'Expand the Windows image to the Windows partition completed.' | Write-ScriptLog

    'The new VHD to bootable.' | Write-ScriptLog
    $params = @{
        SystemVolumeDriveLetter      = $systemVolumeDriveLetter
        WindowsVolumeDriveLetter     = $windowsVolumeDriveLetter
        LogFilePathForStandardOutput = Resolve-LogFilePath -FolderPath $labConfig.labHost.folderPath.log -LogFileName ($LogFileName + '_bcdboot-stdout.log')
        LogFilePathForStandardError  = Resolve-LogFilePath -FolderPath $labConfig.labHost.folderPath.log -LogFileName ($LogFileName + '_bcdboot-stderr.log')
    }
    Set-VhdToBootable @params
    'The new VHD to bootable completed.' | Write-ScriptLog

    if ($UpdatePackagePath.Length -gt 0) {
        'Add {0} update packages to the VHD.' -f $UpdatePackagePath.Length | Write-ScriptLog
        foreach ($packagePath in $UpdatePackagePath) {
            'Add an update package "{0}" to the VHD.' -f $packagePath | Write-ScriptLog
            $params = @{
                Path             = ('{0}:' -f $windowsVolumeDriveLetter)
                PackagePath      = $packagePath
                ScratchDirectory = $labConfig.labHost.folderPath.temp
                LogPath          = Resolve-LogFilePath -FolderPath $labConfig.labHost.folderPath.log -LogFileName ($LogFileName + '_add-package.log')
                LogLevel         = 'Debug'
            }
            Add-WindowsPackage @params | Out-String -Width 200 | Write-ScriptLog
            'Add an update package "{0}" to the VHD completed.' -f $packagePath | Write-ScriptLog
        }
        'Add update packages to the VHD completed.' | Write-ScriptLog
    }
    else {
        'There are no update packages.' | Write-ScriptLog
    }

    'The VHD creation job has been successfully completed.' | Write-ScriptLog
}
catch {
    $exceptionMessage = New-ExceptionMessage -ErrorRecord $_
    $exceptionMessage | Write-ScriptLog -Level Error
    throw $exceptionMessage
}
finally {
    if ($vhd -and ($vhd | Get-VHD).Attached) {
        'Dismount the VHD.' | Write-ScriptLog
        $vhd | Dismount-VHD
        'Dismount the VHD completed.' | Write-ScriptLog

        'The created VHD file:' | Write-ScriptLog
        Get-Item -LiteralPath $vhd.Path | Format-List -Property 'Name','FullName','Length','LastWriteTimeUtc' | Out-String -Width 200 | Write-ScriptLog
        Get-VHD -Path $vhd.Path | Format-List -Property '*' | Out-String -Width 200 | Write-ScriptLog
    }

    'The VHD creation job has been finished.' | Write-ScriptLog
    Stop-ScriptLogging
}
