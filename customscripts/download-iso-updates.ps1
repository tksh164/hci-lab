[CmdletBinding()]
param ()

$ErrorActionPreference = [Management.Automation.ActionPreference]::Stop
$WarningPreference = [Management.Automation.ActionPreference]::Continue
$VerbosePreference = [Management.Automation.ActionPreference]::Continue
$ProgressPreference = [Management.Automation.ActionPreference]::SilentlyContinue

Import-Module -Name '.\shared.psm1' -Force

$configParams = GetConfigParameters
Start-Transcript -OutputDirectory $configParams.labHost.folderPath.log
$configParams | ConvertTo-Json -Depth 16

function DownloadIso
{
    param (
        [Parameter(Mandatory = $true)]
        [string] $OperatingSystem,

        [Parameter(Mandatory = $true)]
        [string] $Culture,

        [Parameter(Mandatory = $true)]
        [string] $DownloadFolderPath
    )

    $isoUris = @{
        'as22h2' = @{
            'en-us' = 'https://software-static.download.prss.microsoft.com/dbazure/988969d5-f34g-4e03-ac9d-1f9786c66751/20349.1129.221007-2120.fe_release_hciv3_svc_refresh_SERVERAZURESTACKHCICOR_OEMRET_x64FRE_en-us.iso'
            'ja-jp' = 'https://software-static.download.prss.microsoft.com/dbazure/988969d5-f34g-4e03-ac9d-1f9786c66751/20349.1129.221007-2120.fe_release_hciv3_svc_refresh_SERVERAZURESTACKHCICOR_OEMRET_x64FRE_ja-jp.iso'
        }
        'as21h2' = @{
            'en-us' = 'https://software-download.microsoft.com/download/sg/AzureStackHCI_20348.288_en-us.iso'
            'ja-jp' = 'https://software-download.microsoft.com/download/sg/AzureStackHCI_20348.288_ja-jp.iso'
        }
        'as20h2' = @{
            'en-us' = 'https://software-download.microsoft.com/download/sg/AzureStackHCI_17784.1408_en-us.iso'
            'ja-jp' = 'https://software-download.microsoft.com/download/sg/AzureStackHCI_17784.1408_ja-jp.iso'
        }
        'ws2022' = @{
            'en-us' = 'https://go.microsoft.com/fwlink/p/?LinkID=2195280&clcid=0x409&culture=en-us&country=US'
            'ja-jp' = 'https://go.microsoft.com/fwlink/p/?LinkID=2195280&clcid=0x411&culture=ja-jp&country=JP'
        }
    }

    $params = @{
        SourceUri      = $isoUris[$OperatingSystem][$Culture]
        DownloadFolder = $DownloadFolderPath
        FileNameToSave = (BuildIsoFileName -OperatingSystem $OperatingSystem -Culture $Culture)
    }
    DownloadFile @params
}

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
            'https://catalog.s.download.windowsupdate.com/c/msdownload/update/software/secu/2023/01/windows10.0-kb5022291-x64_7a517cbbe1288fd246efebc6089d0a4d91818c0e.msu',
            'https://catalog.s.download.windowsupdate.com/d/msdownload/update/software/secu/2022/10/windows10.0-kb5020877-x64-ndp48_f16f6550da2375d2d9c2ffb0ca61e399d303766d.msu'
        )
        'as21h2' = @(
            'https://catalog.s.download.windowsupdate.com/c/msdownload/update/software/secu/2023/01/windows10.0-kb5022291-x64_7a517cbbe1288fd246efebc6089d0a4d91818c0e.msu',
            'https://catalog.s.download.windowsupdate.com/d/msdownload/update/software/secu/2022/10/windows10.0-kb5020877-x64-ndp48_f16f6550da2375d2d9c2ffb0ca61e399d303766d.msu'
        )
        'as20h2' = @(
            # Need to apply SSU before applying updates.
        )
        'ws2022' = @(
            'https://catalog.s.download.windowsupdate.com/c/msdownload/update/software/secu/2023/01/windows10.0-kb5022291-x64_7a517cbbe1288fd246efebc6089d0a4d91818c0e.msu',
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

# ISO

'Creating the download folder if it does not exist...' | WriteLog -Context $env:ComputerName
New-Item -ItemType Directory -Path $configParams.labHost.folderPath.temp -Force

'Downloading the ISO file...' | WriteLog -Context $env:ComputerName
DownloadIso -OperatingSystem $configParams.hciNode.operatingSystem.sku -Culture $configParams.guestOS.culture -DownloadFolderPath $configParams.labHost.folderPath.temp

# The Windows Server 2022 ISO is always needed for the domain controller VM.
if ($configParams.hciNode.operatingSystem.sku -ne 'ws2022') {
    'Downloading Windows Server 2022 ISO file...' | WriteLog -Context $env:ComputerName
    DownloadIso -OperatingSystem 'ws2022' -Culture $configParams.guestOS.culture -DownloadFolderPath $configParams.labHost.folderPath.temp
}

'The ISO download has been completed.' | WriteLog -Context $env:ComputerName

# Updates

# Download the updates if the flag was true only.
if ($configParams.guestOS.applyUpdates) {
    'Creating the updates folder if it does not exist...' | WriteLog -Context $env:ComputerName
    New-Item -ItemType Directory -Path $configParams.labHost.folderPath.updates -Force
    
    'Downloading updates...' | WriteLog -Context $env:ComputerName
    DownloadUpdates -OperatingSystem $configParams.hciNode.operatingSystem.sku -DownloadFolderBasePath $configParams.labHost.folderPath.updates
    
    if ($configParams.hciNode.operatingSystem.sku -ne 'ws2022') {
        'Downloading Windows Server 2022 updates...' | WriteLog -Context $env:ComputerName
        DownloadUpdates -OperatingSystem 'ws2022' -DownloadFolderBasePath $configParams.labHost.folderPath.updates
    }

    'The updates download has been completed.' | WriteLog -Context $env:ComputerName
}
else {
    'Skipped download of updates due to applyUpdates not set.' | WriteLog -Context $env:ComputerName
}

Stop-Transcript
