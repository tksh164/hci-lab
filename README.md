# HCI Lab

This template deploys an HCI lab environment with Azure Stack HCI or Windows Server 2022 on a single Azure virtual machine in about 30 minutes.

## 🚀 Quickstart

1. Open Azure portal from the following **Deploy to Azure** to deploy your HCI lab environment. To keep this page, open it as a new tab (Ctrl + Click).

    | UI language at deployment | Deploy to Azure |
    | ---- | ---- |
    | English | [![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#view/Microsoft_Azure_CreateUIDef/CustomDeploymentBlade/uri/https%3A%2F%2Fraw.githubusercontent.com%2Ftksh164%2Fhci-lab%2Fmain%2Ftemplate%2Ftemplate.json/uiFormDefinitionUri/https%3A%2F%2Fraw.githubusercontent.com%2Ftksh164%2Fhci-lab%2Fmain%2Fuiforms%2Fuiform.json) |
    | Japanese (日本語) | [![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#view/Microsoft_Azure_CreateUIDef/CustomDeploymentBlade/uri/https%3A%2F%2Fraw.githubusercontent.com%2Ftksh164%2Fhci-lab%2Fmain%2Ftemplate%2Ftemplate.json/uiFormDefinitionUri/https%3A%2F%2Fraw.githubusercontent.com%2Ftksh164%2Fhci-lab%2Fmain%2Fuiforms%2Fuiform-jajp.json) |

2. Fill out required fields in the **Basics** tab on Azure portal. Other fields in the rest tabs can leave with default values. **Click Review + create** to start deployment.

3. The deployment will be complete in about 30 minutes if the deployment starts with default values.

4. After completing the deployment, you need to allow Remote Desktop access to your lab host Azure VM from your local machine. It can be by [enabling JIT VM access](https://learn.microsoft.com/en-us/azure/defender-for-cloud/just-in-time-access-usage) or [adding an inbound security rule in the Network Security Group](https://learn.microsoft.com/en-us/azure/virtual-network/tutorial-filter-network-traffic#create-security-rules). The recommended way is using JIT VM access.

5. Connect to your lab host Azure VM using your favorite Remote Desktop client. To connect, use the credentials that you specified at deployment.

6. You can start accessing your HCI lab environment from the icons on the desktop of your lab host Azure VM. To access the Hyper-V VMs in the HCI lab environment, use Administrator account and the password that you specified at deployment (the same password as the lab host Azure VM).

## ✒️ Notes

- The log files of the custom scripts are stored under `C:\temp\hcilab-logs` in the lab host Azure VM. Those log files are helpful for troubleshooting when deployment fails.

## 📦 External artifacts

- The custom script `create-base-vhd.ps1` in this template downloads `Convert-WindowsImage.ps1` from [microsoft/MSLab](https://github.com/microsoft/MSLab) and uses it during the deployment.

## ⚖️ License

Copyright (c) 2022-present Takeshi Katano. All rights reserved. This software is released under the [MIT License](https://github.com/tksh164/hci-lab/blob/main/LICENSE).

Disclaimer: The codes stored herein are my own personal codes and do not related my employer's any way.
