[CmdletBinding()]
param ()

$ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop
$WarningPreference = [System.Management.Automation.ActionPreference]::Continue
$VerbosePreference = [System.Management.Automation.ActionPreference]::Continue
$ProgressPreference = [System.Management.Automation.ActionPreference]::SilentlyContinue

Import-Module -Name '.\common.psm1' -Force

$configParams = GetConfigParameters
Start-Transcript -OutputDirectory $configParams.folderPath.transcript
$configParams | ConvertTo-Json -Depth 16

# Set Hyper-V host settings.
$params = @{
    VirtualMachinePath        = $configParams.folderPath.vm
    VirtualHardDiskPath       = $configParams.folderPath.vhd
    EnableEnhancedSessionMode = $true
}
Set-VMHost @params

# Create a NAT vSwitch.
$params = @{
    Name        = $configParams.natOnLabHost.vSwitchName
    SwitchType  = 'Internal'
}
New-VMSwitch @params

# Assign an IP address to the NAT vSwitch network interface.
$params= @{
    InterfaceIndex = (Get-NetAdapter | Where-Object { $_.Name -match $configParams.natOnLabHost.vSwitchName }).ifIndex
    AddressFamily  = 'IPv4'
    IPAddress      = $configParams.natOnLabHost.hostIpAddress
    PrefixLength   = $configParams.natOnLabHost.hostPrefixLength
}
New-NetIPAddress @params

# Create a network NAT.
$params = @{
    Name                             = $configParams.natOnLabHost.vSwitchName
    InternalIPInterfaceAddressPrefix = $configParams.natOnLabHost.subnet
}
New-NetNat @params

Stop-Transcript
