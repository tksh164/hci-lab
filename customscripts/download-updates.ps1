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

function DownloadUpdates
{
    param (
        [Parameter(Mandatory = $true)]
        [string] $OperatingSystem,

        [Parameter(Mandatory = $true)]
        [string] $DownloadFolderBasePath
    )

    #
    # Azure Stack HCI
    # OS: https://learn.microsoft.com/en-us/azure-stack/hci/release-information
    #
    # Azure Stack HCI 22H2
    # OS: https://support.microsoft.com/en-us/topic/fea63106-a0a9-4b6c-bb72-a07985c98a56
    # .NET: https://support.microsoft.com/en-us/topic/57cf4b09-c538-4bdf-8954-37b690e52a12
    #
    # Azure Stack HCI 21H2
    # OS: https://support.microsoft.com/en-us/topic/5c5e6adf-e006-4a29-be22-f6faeff90173
    # .NET: https://support.microsoft.com/en-us/topic/fde41bff-0ae6-479f-9e35-708f62ebbc08
    #
    # Azure Stack HCI 20H2
    # OS: https://support.microsoft.com/en-us/topic/64c79b7f-d536-015d-b8dd-575f01090efd
    # .NET: 
    #
    # Windows Server
    # OS: https://support.microsoft.com/en-us/topic/e1caa597-00c5-4ab9-9f3e-8212fe80b2ee
    # .NET: https://support.microsoft.com/en-us/topic/f61ae6ae-6f7a-493f-84d3-42ae1ebff494
    #
    $updates = @{
        'as22h2' = @(
            'https://catalog.s.download.windowsupdate.com/d/msdownload/update/software/updt/2022/12/windows10.0-kb5022553-x64_06fa4af116114f39709a1404a318e1f7fa644e5d.msu',
            'https://catalog.s.download.windowsupdate.com/d/msdownload/update/software/secu/2022/10/windows10.0-kb5020877-x64-ndp48_f16f6550da2375d2d9c2ffb0ca61e399d303766d.msu'
        )
        'as21h2' = @(
            'https://catalog.s.download.windowsupdate.com/d/msdownload/update/software/updt/2022/12/windows10.0-kb5022553-x64_06fa4af116114f39709a1404a318e1f7fa644e5d.msu',
            'https://catalog.s.download.windowsupdate.com/d/msdownload/update/software/secu/2022/10/windows10.0-kb5020877-x64-ndp48_f16f6550da2375d2d9c2ffb0ca61e399d303766d.msu'
        )
        'as20h2' = @(
            # Need to apply SSU before applying updates.
        )
        'ws2022' = @(
            'https://catalog.s.download.windowsupdate.com/d/msdownload/update/software/updt/2022/12/windows10.0-kb5022553-x64_06fa4af116114f39709a1404a318e1f7fa644e5d.msu',
            'https://catalog.s.download.windowsupdate.com/d/msdownload/update/software/secu/2022/10/windows10.0-kb5020877-x64-ndp48_f16f6550da2375d2d9c2ffb0ca61e399d303766d.msu',
            'https://catalog.s.download.windowsupdate.com/d/msdownload/update/software/secu/2022/12/windows10.0-kb5020883-x64-ndp481_e73af78018fcd37145c3ff4fd6b94dc0d46070fc.msu'
        )
    }

    $downloadFolderPath = [IO.Path]::Combine($DownloadFolderBasePath, $OperatingSystem)
    New-Item -ItemType Directory -Path $downloadFolderPath -Force

    $updates[$OperatingSystem] | ForEach-Object -Process {
        $params = @{
            SourceUri      = $_
            DownloadFolder = $downloadFolderPath
            FileNameToSave = [IO.Path]::GetFileName([uri]($_))
        }
        DownloadFile @params
    }
}

# Download the updates if the flag was true only.
if (-not $configParams.guestOS.applyUpdates) { return }

# Create the updates folder if it does not exist.
New-Item -ItemType Directory -Path $configParams.labHost.folderPath.updates -Force

Write-Verbose -Message 'Downloading updates...'
DownloadUpdates -OperatingSystem $configParams.hciNode.operatingSystem -DownloadFolderBasePath $configParams.labHost.folderPath.updates

if ($configParams.hciNode.operatingSystem -ne 'ws2022') {
    Write-Verbose -Message 'Downloading Windows Server 2022 updates...'
    DownloadUpdates -OperatingSystem 'ws2022' -DownloadFolderBasePath $configParams.labHost.folderPath.updates
}

Write-Verbose -Message 'The updates download has been completed.'

Stop-Transcript
