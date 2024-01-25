Configuration install-roles-and-features
{
    param ()

    Import-DscResource -ModuleName 'PSDesiredStateConfiguration'

    Node 'localhost' {
        LocalConfigurationManager {
            ConfigurationMode  = 'ApplyOnly'
            RebootNodeIfNeeded = $true
            ActionAfterReboot  = 'ContinueConfiguration'
        }

        $requiredFeatureNames = @(
            'Microsoft-Hyper-V',
            'Microsoft-Hyper-V-Management-Clients',
            'Microsoft-Hyper-V-Management-PowerShell'
        )
    
        Script 'Install roles and features' {
            TestScript = {
                foreach ($featureName in $using:requiredFeatureNames) {
                    $faeture = Get-WindowsOptionalFeature -Online -FeatureName $featureName
                    if ($faeture.State -ne 'Enabled') {
                        return $false  # The SetScript execution needed.
                    }
                }
                return $true  # The SetScript execution is not needed.
            }
            SetScript = {
                # NOTE: Use the Enable-WindowsOptionalFeature cmdlet instead of the Install-WindowsFeature cmdlet because
                # cannot install the Hyper-V role with the hotpatch images.
                Enable-WindowsOptionalFeature -Online -FeatureName $using:requiredFeatureNames -All -NoRestart
                $global:DSCMachineStatus = 1  # The reboot is needed.
            }
            GetScript = {
                $results = @()
                foreach ($featureName in $using:requiredFeatureNames) {
                    $faeture = Get-WindowsOptionalFeature -Online -FeatureName $featureName
                    $results += '{0}:{1}' -f $faeture.FeatureName, $faeture.State
                }
                return @{
                    Result = $results -join ', '
                }
            }
        }
    }
}
