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

# Create the download folder if it does not exist.
New-Item -ItemType Directory -Path $configParams.folderPath.temp -Force

# Download the Windows Admin Center installer.
$params = @{
    SourceUri      = 'https://aka.ms/WACDownload'
    DownloadFolder = $configParams.folderPath.temp
    FileNameToSave = 'WindowsAdminCenter.msi'
}
$wacMsiFile = DownloadFile @params
$wacMsiFile

# Install Windows Admin Center.
$msiArgs = @(
    '/i',
    ('"{0}"' -f $wacMsiFile.FullName),
    '/qn',
    '/L*v',
    ('"{0}"' -f [IO.Path]::Combine($configParams.folderPath.temp, 'wac-install-log.txt')),
    'SME_PORT=443',
    'SSL_CERTIFICATE_OPTION=generate'
)
$result = Start-Process -FilePath 'msiexec.exe' -ArgumentList $msiArgs -Wait -PassThru
$result | Format-List -Property '*'
if ($result.ExitCode -ne 0) {
    throw ('Windows Admin Center installation failed with exit code {0}.' -f $result.ExitCode)
}

# Create shortcut for Windows Admin Center in desktop.
$wshShell = New-Object -ComObject 'WScript.Shell'
$shortcut = $wshShell.CreateShortcut('C:\Users\Public\Desktop\Windows Admin Center.lnk')
$shortcut.TargetPath = 'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe'
$shortcut.Arguments = 'https://{0}' -f $env:ComputerName
$shortcut.Description = 'Windows Admin Center for the lab environment.'
$shortcut.IconLocation = 'shell32.dll,34'
$shortcut.Save()

Stop-Transcript
