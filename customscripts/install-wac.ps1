[CmdletBinding()]
param ()

$ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop
$ProgressPreference = [System.Management.Automation.ActionPreference]::SilentlyContinue

Import-Module -Name '.\common.psm1'

$configParams = GetConfigParameters
Start-Transcript -OutputDirectory $configParams.transcriptFolder
$configParams

# function InstallWAC
# {
#     param (
#         [Parameter(Mandatory = $true)]
#         [string] $InstallerFilePath,

#         [Parameter(Mandatory = $true)]
#         [string] $LogFilePath
#     )

#     $msiArgs = '/i', ('"{0}"' -f $InstallerFilePath), '/qn', '/L*v', ('"{0}"' -f $LogFilePath), 'SME_PORT=443', 'SSL_CERTIFICATE_OPTION=generate'
#     Start-Process -FilePath 'msiexec.exe' -ArgumentList $msiArgs -Wait -PassThru
# }

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
$msiArgs = @(
    '/i',
    ('"{0}"' -f $wacMsiFilePath.FullName),
    '/qn',
    '/L*v',
    ('"{0}"' -f [IO.Path]::Combine($configParams.tempFolder, 'wac-install-log.txt')),
    'SME_PORT=443',
    'SSL_CERTIFICATE_OPTION=generate'
)
$result = Start-Process -FilePath 'msiexec.exe' -ArgumentList $msiArgs -Wait -PassThru
$result | Format-List -Property '*'
if ($result.ExitCode -ne 0) {
    throw 'Windows Admin Center installation failed.'
}
# $result = InstallWAC -InstallerFilePath $wacMsiFilePath.FullName -LogFilePath ([IO.Path]::Combine($configParams.tempFolder, 'wac-install-log.txt'))
# $result | Format-List -Property '*'
# if ($result.ExitCode -ne 0) {
#     # Retry to installation (for CustomAction CreateFirewallRule returned actual error code 1603).
#     $result = InstallWAC -InstallerFilePath $wacMsiFilePath.FullName -LogFilePath ([IO.Path]::Combine($configParams.tempFolder, 'wac-install-log2.txt'))
#     $result | Format-List -Property '*'
#     if ($result.ExitCode -ne 0) {
#         throw 'Windows Admin Center installation failed.'
#     }
# }

# Create shortcut for Windows Admin Center in desktop.
$wshShell = New-Object -ComObject 'WScript.Shell'
$shortcut = $wshShell.CreateShortcut('C:\Users\Public\Desktop\Windows Admin Center.lnk')
$shortcut.TargetPath = 'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe'
$shortcut.Arguments = 'https://{0}' -f $env:ComputerName
$shortcut.Description = 'Windows Admin Center for the lab environment.'
$shortcut.IconLocation = 'shell32.dll,34'
$shortcut.Save()

Stop-Transcript
