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
        FileNameToSave = '{0}_{1}.iso' -f $OperatingSystem, $Culture
    }
    DownloadFile @params
}

# Create the download folder if it does not exist.
New-Item -ItemType Directory -Path $configParams.labHost.folderPath.temp -Force

Write-Verbose -Message 'Downloading the ISO file...'
DownloadIso -OperatingSystem $configParams.hciNode.operatingSystem -Culture $configParams.guestOS.culture -DownloadFolderPath $configParams.labHost.folderPath.temp

if ($configParams.hciNode.operatingSystem -ne 'ws2022') {
    # The Windows Server 2022 ISO is always needed for the domain controller VM.
    Write-Verbose -Message 'Downloading Windows Server 2022 ISO file...'
    DownloadIso -OperatingSystem 'ws2022' -Culture $configParams.guestOS.culture -DownloadFolderPath $configParams.labHost.folderPath.temp
}

Write-Verbose -Message 'The ISO download has been completed.'

Stop-Transcript
