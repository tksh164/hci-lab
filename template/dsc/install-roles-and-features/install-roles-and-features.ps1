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

        WindowsFeatureSet 'Install roles and features' {
            Ensure = 'Present'
            Name   = 'Hyper-V', 'RSAT-Hyper-V-Tools'
        }
    }
}
