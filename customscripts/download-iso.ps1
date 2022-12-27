[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)]
    [ValidateSet('as22h2', 'as21h2', 'as20h2', 'ws2022')]
    [string] $NodeOS = 'as22h2',

    [Parameter(Mandatory = $true)]
    [ValidateSet('enus', 'jajp')]
    [string] $NodeOSLang = 'enus',

    [Parameter(Mandatory = $false)]
    [string] $ConfigParametersFile = '.\config-parameters.json'
)

$ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop
$ProgressPreference = [System.Management.Automation.ActionPreference]::SilentlyContinue

$logFolderPath = 'C:\Temp'
New-Item -ItemType Directory -Path $logFolderPath -Force
Start-Transcript -OutputDirectory $logFolderPath

Import-Module -Name '.\common.psm1'

$configParams = GetConfigParametersFromJsonFile -FilePath $ConfigParametersFile

$isoUris = @{
    'as22h2' = @{
        'enus' = 'https://software-static.download.prss.microsoft.com/dbazure/988969d5-f34g-4e03-ac9d-1f9786c66751/20349.1129.221007-2120.fe_release_hciv3_svc_refresh_SERVERAZURESTACKHCICOR_OEMRET_x64FRE_en-us.iso'
        'jajp' = 'https://software-static.download.prss.microsoft.com/dbazure/988969d5-f34g-4e03-ac9d-1f9786c66751/20349.1129.221007-2120.fe_release_hciv3_svc_refresh_SERVERAZURESTACKHCICOR_OEMRET_x64FRE_ja-jp.iso'
    }
    'as21h2' = @{
        'enus' = 'https://software-download.microsoft.com/download/sg/AzureStackHCI_20348.288_en-us.iso'
        'jajp' = 'https://software-download.microsoft.com/download/sg/AzureStackHCI_20348.288_ja-jp.iso'
    }
    'as20h2' = @{
        'enus' = 'https://software-download.microsoft.com/download/sg/AzureStackHCI_17784.1408_en-us.iso'
        'jajp' = 'https://software-download.microsoft.com/download/sg/AzureStackHCI_17784.1408_ja-jp.iso'
    }
    'ws2022' = @{
        'enus' = 'https://go.microsoft.com/fwlink/p/?LinkID=2195280&clcid=0x409&culture=en-us&country=US'
        'jajp' = 'https://go.microsoft.com/fwlink/p/?LinkID=2195280&clcid=0x411&culture=ja-jp&country=JP'
    }
}

# Create the download folder if it does not exist.
New-Item -ItemType Directory -Path $configParams.tempFolder -Force

# Download the ISO file.
$params = @{
    SourceUri      = $isoUris[$NodeOS][$NodeOSLang]
    DownloadFolder = $configParams.tempFolder
    FileNameToSave = '{0}{1}.iso' -f $NodeOS, $NodeOSLang
}
DownloadFile @params

if ($NodeOS -ne 'ws2022') {
    # The Windows Server 2022 ISO is always needed for the domain controller VM.
    $params = @{
        SourceUri      = $isoUris['ws2022'][$NodeOSLang]
        DownloadFolder = $configParams.tempFolder
        FileNameToSave = '{0}{1}.iso' -f 'ws2022', $NodeOSLang
    }
    DownloadFile @params
}

Stop-Transcript
