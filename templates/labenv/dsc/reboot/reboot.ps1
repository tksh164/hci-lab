Configuration reboot
{
    param ()

    Import-DscResource -ModuleName 'PSDesiredStateConfiguration'

    Node 'localhost' {
        LocalConfigurationManager {
            ConfigurationMode  = 'ApplyOnly'
            RebootNodeIfNeeded = $true
            ActionAfterReboot  = 'ContinueConfiguration'
        }

        $regKey = 'HKLM:\SOFTWARE\HciLabConfig\RebootFlagKey'

        Script 'Reboot machine' {
            TestScript = {
                return (Test-Path -LiteralPath $using:regKey)
            }
            SetScript = {
                New-Item -Path $using:regKey -Force
                $global:DSCMachineStatus = 1
            }
            GetScript = {
                return @{
                    Result = if ([scriptblock]::Create($TestScript).Invoke()) { 'Reboot has been completed.' } else { 'Reboot has not yet been completed.' }
                }
            }
        }
    }
}
