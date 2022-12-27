[CmdletBinding()]
param (
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

# Create the download folder if it does not exist.
New-Item -ItemType Directory -Path $DownloadFolder -Force

# Download the ISO file.
$params = @{
    SourceUri      = 'https://software-static.download.prss.microsoft.com/dbazure/988969d5-f34g-4e03-ac9d-1f9786c66751/20349.1129.221007-2120.fe_release_hciv3_svc_refresh_SERVERAZURESTACKHCICOR_OEMRET_x64FRE_ja-jp.iso'
    DownloadFolder = $configParams.tempFolder
    FileNameToSave = 'as22h2.iso'
}
DownloadFile @params

# Download the ISO file.
$params = @{
    SourceUri      = 'https://software-download.microsoft.com/download/sg/AzureStackHCI_20348.288_ja-jp.iso'
    DownloadFolder = $configParams.tempFolder
    FileNameToSave = 'as21h2.iso'
}
DownloadFile @params

# Download the ISO file.
$params = @{
    SourceUri      = 'https://software-download.microsoft.com/download/sg/AzureStackHCI_17784.1408_ja-jp.iso'
    DownloadFolder = $configParams.tempFolder
    FileNameToSave = 'as20h2.iso'
}
DownloadFile @params

# Download the ISO file.
$params = @{
    SourceUri      = 'https://go.microsoft.com/fwlink/p/?LinkID=2195280&clcid=0x411&culture=ja-jp&country=JP'
    DownloadFolder = $configParams.tempFolder
    FileNameToSave = 'ws2022.iso'
}
DownloadFile @params

Stop-Transcript
