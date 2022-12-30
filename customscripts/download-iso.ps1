[CmdletBinding()]
param ()

$ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop
$WarningPreference = [System.Management.Automation.ActionPreference]::Continue
$VerbosePreference = [System.Management.Automation.ActionPreference]::Continue
$ProgressPreference = [System.Management.Automation.ActionPreference]::SilentlyContinue

Import-Module -Name '.\common.psm1'

$configParams = GetConfigParameters
Start-Transcript -OutputDirectory $configParams.folderPath.transcript
$configParams | ConvertTo-Json -Depth 16

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

# Create the download folder if it does not exist.
New-Item -ItemType Directory -Path $configParams.folderPath.temp -Force

# Download the ISO file.
$params = @{
    SourceUri      = $isoUris[$configParams.hciNode.operatingSystem][$configParams.hciNode.culture]
    DownloadFolder = $configParams.folderPath.temp
    FileNameToSave = '{0}_{1}.iso' -f $configParams.hciNode.operatingSystem, $configParams.hciNode.culture
}
DownloadFile @params

if ($configParams.hciNode.operatingSystem -ne 'ws2022') {
    # The Windows Server 2022 ISO is always needed for the domain controller VM.
    $params = @{
        SourceUri      = $isoUris['ws2022'][$configParams.hciNode.culture]
        DownloadFolder = $configParams.folderPath.temp
        FileNameToSave = '{0}_{1}.iso' -f 'ws2022', $configParams.hciNode.culture
    }
    DownloadFile @params
}

Stop-Transcript
