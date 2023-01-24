# HCI Lab

[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#view/Microsoft_Azure_CreateUIDef/CustomDeploymentBlade/uri/https%3A%2F%2Fraw.githubusercontent.com%2Ftksh164%2Fazure-demo-scripts-templates%2Fmaster%2Farm-templates%2Fhci-lab%2Ftemplate.json/uiFormDefinitionUri/https%3A%2F%2Fraw.githubusercontent.com%2Ftksh164%2Fazure-demo-scripts-templates%2Fmaster%2Farm-templates%2Fhci-lab%2Fuiform.json)

## Template overview

This template deploys an HCI lab environment with Azure Stack HCI or Windows Server 2022.

## Notes

- The log files of the custom scripts are stored under `C:\Temp` in the lab host Azure VM. Those log files are helpful for troubleshooting when deployment fails.

## License

- The custom script `create-base-vhd.ps1` in this template downloads `Convert-WindowsImage.ps1` from [x0nn/Convert-WindowsImage](https://github.com/x0nn/Convert-WindowsImage) and uses it during the deployment. `Convert-WindowsImage.ps1` licensed under the GPLv3-License. See [here](https://github.com/x0nn/Convert-WindowsImage#license) for details.
