# HCI Lab

This template deploys an HCI lab environment with Azure Stack HCI or Windows Server 2022 on a single Azure virtual machine in about 30 minutes.

## 🚀 Quickstart

Start your deployment with Azure portal from the following **Deploy to Azure**.

| UI language at deployment | Deploy to Azure |
| ---- | ---- |
| English | [![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#view/Microsoft_Azure_CreateUIDef/CustomDeploymentBlade/uri/https%3A%2F%2Fraw.githubusercontent.com%2Ftksh164%2Fhci-lab%2Fmain%2Ftemplate%2Ftemplate.json/uiFormDefinitionUri/https%3A%2F%2Fraw.githubusercontent.com%2Ftksh164%2Fhci-lab%2Fmain%2Fuiforms%2Fuiform.json) |
| Japanese (日本語) | [![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#view/Microsoft_Azure_CreateUIDef/CustomDeploymentBlade/uri/https%3A%2F%2Fraw.githubusercontent.com%2Ftksh164%2Fhci-lab%2Fmain%2Ftemplate%2Ftemplate.json/uiFormDefinitionUri/https%3A%2F%2Fraw.githubusercontent.com%2Ftksh164%2Fhci-lab%2Fmain%2Fuiforms%2Fuiform-jajp.json) |

## ✒️ Notes

- The log files of the custom scripts are stored under `C:\temp\hcilab-logs` in the lab host Azure VM. Those log files are helpful for troubleshooting when deployment fails.

## 📦 External artifacts

- The custom script `create-base-vhd.ps1` in this template downloads `Convert-WindowsImage.ps1` from [microsoft/MSLab](https://github.com/microsoft/MSLab) and uses it during the deployment.

## ⚖️ License

Copyright (c) 2022-present Takeshi Katano. All rights reserved. This software is released under the [MIT License](https://github.com/tksh164/hci-lab/blob/main/LICENSE).

Disclaimer: The codes stored herein are my own personal codes and do not related my employer's any way.
