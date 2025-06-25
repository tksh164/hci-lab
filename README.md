# HCI Lab

The HCI Lab provides a plain HCI lab environment on Azure in reasonable preparation time and cost.

- An HCI lab environment with Azure Local (formerly Azure Stack HCI) or Windows Server 2025/2022 on a single Azure virtual machine in about 30 minutes minimum.
- Just a plain environment, so you can try many workloads and features to start from the clean environment by yourself. Also, you can customize it to your own needs easily.
- You can choose an operating system from the [selectable HCI node's operating systems](#-selectable-hci-nodes-operating-systems) to use deploy your HCI lab environment.

## 🚀 Quickstart

1. Open Azure portal from the following **Deploy to Azure** to deploy your HCI lab environment. To keep this page, open it as a new tab (Ctrl + Click).

    The differences between "UI languages at deployment" are just the UI language difference in Azure portal when deployment. The template and the deployed lab environment are the same with either.

    | UI language at deployment | Deploy to Azure |
    | ---- | ---- |
    | English | [![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#view/Microsoft_Azure_CreateUIDef/CustomDeploymentBlade/uri/https%3A%2F%2Fraw.githubusercontent.com%2Ftksh164%2Fhci-lab%2Fmain%2Ftemplate%2Ftemplate.json/uiFormDefinitionUri/https%3A%2F%2Fraw.githubusercontent.com%2Ftksh164%2Fhci-lab%2Fmain%2Fuiforms%2Fuiform.json) |
    | Japanese (日本語) | [![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#view/Microsoft_Azure_CreateUIDef/CustomDeploymentBlade/uri/https%3A%2F%2Fraw.githubusercontent.com%2Ftksh164%2Fhci-lab%2Fmain%2Ftemplate%2Ftemplate.json/uiFormDefinitionUri/https%3A%2F%2Fraw.githubusercontent.com%2Ftksh164%2Fhci-lab%2Fmain%2Fuiforms%2Fuiform-jajp.json) |

2. Fill out required fields in the **Basics** tab on Azure portal. Other fields in the rest tabs can leave with default values. **Click Review + create** to start deployment.

    The deployment will be complete in about 30 minutes if the deployment starts with default values.

    > If the deployment failed, try deploying again that will resolving the issue in most cases. If not, please create an issue, it will help HCI Lab quality improvement.

3. After completing the deployment, you need to allow Remote Desktop access to your lab host Azure VM from your local machine. It can be by [enabling JIT VM access](https://learn.microsoft.com/azure/defender-for-cloud/just-in-time-access-usage) or [adding an inbound security rule in the Network Security Group](https://learn.microsoft.com/azure/virtual-network/tutorial-filter-network-traffic#create-security-rules). The recommended way is using JIT VM access.

4. Connect to your lab host Azure VM using your favorite Remote Desktop client. To connect, use the credentials that you specified at deployment.

5. The HCI cluster is ready for you. Let's access your HCI cluster via Windows Admin Center from **Windows Admin Center icon** on the desktop with **HCI\\Administrator** account and the password that you specified at deployment (the same password as the lab host Azure VM). Also, you can access your entire HCI lab environment from the other icons on the desktop.

## 🗺️ HCI Lab tour

Learn more about the HCI lab in the [HCI Lab tour](./docs/hci-lab-tour.md).

## 📚 Selectable HCI node's operating systems

| Operating system | Description | HCI Lab |
| ---- | ---- | ---- |
| Azure Local 2505 (24H2) | The latest generally available version of Azure Local. | Available |
| Azure Local 2504 (24H2) | The previous version of Azure Local. | Selectable. Not tested. |
| Azure Local 2503 (23H2) | The previous version of Azure Local (formerly Azure Stack HCI). | Selectable. Not tested. |
| Azure Stack HCI, version 22H2 | This version of Azure Stack HCI reached the end of service on May 31, 2025. | Selectable. Not tested. |
| Azure Stack HCI, version 21H2 | This version of Azure Stack HCI reached the end of service on November 14, 2023. | Selectable. Not tested. |
| Azure Stack HCI, version 20H2 | This version of Azure Stack HCI reached the end of service on December 13, 2022. | Selectable. Not tested. |
| Windows Server 2025 Datacenter Evaluation (Desktop Experience) | Windows Server 2025 Datacenter with the standard graphical user interface. | Available |
| Windows Server 2022 Datacenter Evaluation (Desktop Experience) | Windows Server 2022 Datacenter with the standard graphical user interface. | Available |

## ⚖️ License

Copyright (c) 2022-present Takeshi Katano. All rights reserved. This software is released under the [MIT License](https://github.com/tksh164/hci-lab/blob/main/LICENSE).

Disclaimer: The codes stored herein are my own personal codes and do not related my employer's any way.
