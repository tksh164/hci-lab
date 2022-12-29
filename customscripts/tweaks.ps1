[CmdletBinding()]
param ()

$ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop
$ProgressPreference = [System.Management.Automation.ActionPreference]::SilentlyContinue

Import-Module -Name '.\common.psm1'

$configParams = GetConfigParameters
Start-Transcript -OutputDirectory $configParams.folderPath.transcript
$configParams | ConvertTo-Json -Depth 16

# Stop Server Manager launch at logon.
Set-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\ServerManager' -Name 'DoNotOpenServerManagerAtLogon' -Value 1

# Stop Windows Admin Center popup at Server Manager launch.
Set-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\ServerManager' -Name 'DoNotPopWACConsoleAtSMLaunch' -Value 1

# Hide the Network Location wizard. All networks will be Public.
New-Item -ItemType Directory -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Network' -Name 'NewNetworkWindowOff'

Stop-Transcript
