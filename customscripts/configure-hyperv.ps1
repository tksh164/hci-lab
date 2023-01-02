[CmdletBinding()]
param ()

$ErrorActionPreference = [Management.Automation.ActionPreference]::Stop
$WarningPreference = [Management.Automation.ActionPreference]::Continue
$VerbosePreference = [Management.Automation.ActionPreference]::Continue
$ProgressPreference = [Management.Automation.ActionPreference]::SilentlyContinue

Import-Module -Name '.\common.psm1' -Force

$configParams = GetConfigParameters
Start-Transcript -OutputDirectory $configParams.labHost.folderPath.transcript
$configParams | ConvertTo-Json -Depth 16

# Set Hyper-V host settings.
$params = @{
    VirtualMachinePath        = $configParams.labHost.folderPath.vm
    VirtualHardDiskPath       = $configParams.labHost.folderPath.vhd
    EnableEnhancedSessionMode = $true
}
Set-VMHost @params

# Create a NAT vSwitch.
$params = @{
    Name        = $configParams.labHost.vSwitch.nat.name
    SwitchType  = 'Internal'
}
New-VMSwitch @params

# Create a network NAT.
$params = @{
    Name                             = $configParams.labHost.vSwitch.nat.name
    InternalIPInterfaceAddressPrefix = $configParams.labHost.vSwitch.nat.subnet
}
New-NetNat @params

# Assign an IP address to the NAT vSwitch network interface.
$params= @{
    InterfaceIndex = (Get-NetAdapter | Where-Object { $_.Name -match $configParams.labHost.vSwitch.nat.name }).ifIndex
    AddressFamily  = 'IPv4'
    IPAddress      = $configParams.labHost.vSwitch.nat.hostIPAddress
    PrefixLength   = $configParams.labHost.vSwitch.nat.hostPrefixLength
}
New-NetIPAddress @params

Write-Verbose -Message 'The Hyper-V configuration has been completed.'

Stop-Transcript
