[CmdletBinding()]
param ()

$ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop
$ProgressPreference = [System.Management.Automation.ActionPreference]::SilentlyContinue

Import-Module -Name '.\common.psm1'

$configParams = GetConfigParameters
Start-Transcript -OutputDirectory $configParams.transcriptFolder
$configParams

# Create the download folder if it does not exist.
New-Item -ItemType Directory -Path $configParams.tempFolder -Force

# Download the Windows Admin Center installer.
$params = @{
    SourceUri      = 'https://aka.ms/WACDownload'
    DownloadFolder = $configParams.tempFolder
    FileNameToSave = 'WindowsAdminCenter.msi'
}
$wacMsiFilePath = DownloadFile @params
$wacMsiFilePath

# Install Windows Admin Center.
$msiArgs = '/i', ('"{0}"' -f $wacMsiFilePath.FullName), '/qn', '/L*v', 'log.txt', 'SME_PORT=443', 'SSL_CERTIFICATE_OPTION=generate'
Start-Process -FilePath 'msiexec.exe' -ArgumentList $msiArgs -Wait

Stop-Transcript
