# HCI Lab

The HCI Lab provides a plain lab environment on Azure in reasonable preparation time and cost.

- A lab environment on a single Azure virtual machine for Azure Local or Windows Server 2025/2022 HCI.
- The lab environment will be deployed in about 30 to 120 minutes.
- It is just a plain environment, so you can try many workloads and features to start from the clean environment by yourself. Also, you can customize it to your own needs easily.
- You can choose an [operating system](#-selectable-lab-machine-operating-systems) to use deploy your lab environment.

## 🚀 Quickstart

1. Open Azure portal from the following **Deploy to Azure** to deploy your HCI lab environment. To keep this page, open it as a new tab (Ctrl + Click).

    The differences between "UI languages at deployment" are just the UI language difference in Azure portal when deployment. The template and the deployed lab environment are the same with either.

    | UI language at deployment | Deploy to Azure |
    | ---- | ---- |
    | English | [![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#view/Microsoft_Azure_CreateUIDef/CustomDeploymentBlade/uri/https%3A%2F%2Fraw.githubusercontent.com%2Ftksh164%2Fhci-lab%2Fmain%2Ftemplate%2Ftemplate.json/uiFormDefinitionUri/https%3A%2F%2Fraw.githubusercontent.com%2Ftksh164%2Fhci-lab%2Fmain%2Fuiforms%2Fuiform.json) |
    | Japanese (日本語) | [![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#view/Microsoft_Azure_CreateUIDef/CustomDeploymentBlade/uri/https%3A%2F%2Fraw.githubusercontent.com%2Ftksh164%2Fhci-lab%2Fmain%2Ftemplate%2Ftemplate.json/uiFormDefinitionUri/https%3A%2F%2Fraw.githubusercontent.com%2Ftksh164%2Fhci-lab%2Fmain%2Fuiforms%2Fuiform-jajp.json) |

2. Fill out required fields in the **Basics** tab on Azure portal. Other fields in the rest tabs can leave with default values. **Click Review + create** to start deployment.

    > If the deployment failed, try deploying again that will resolving the issue in most cases. If not, please create an issue, it will help HCI Lab quality improvement.

3. After completing the deployment, you need to allow Remote Desktop access to your lab host Azure VM from your local machine. It can be by [enabling JIT VM access](https://learn.microsoft.com/azure/defender-for-cloud/just-in-time-access-usage) or [adding an inbound security rule in the Network Security Group](https://learn.microsoft.com/azure/virtual-network/tutorial-filter-network-traffic#create-security-rules). The recommended way is using JIT VM access.

4. Connect to your lab host Azure VM using your favorite Remote Desktop client. To connect, use the credentials that you specified at deployment.

5. The HCI cluster is ready for you. Let's access your HCI cluster via Windows Admin Center from **Windows Admin Center icon** on the desktop with **LAB\\Administrator** account and the password that you specified at deployment (the same password as the lab host Azure VM). Also, you can access your entire HCI lab environment from the other icons on the desktop.

## 🗺️ HCI Lab tour

Learn more about the HCI lab in the [HCI Lab tour](./docs/hci-lab-tour.md).

## 📚 Selectable lab machine operating systems

### Available

| Operating system | OS build | Description |
| ---- | ---- | ---- |
| Azure Local 2510 (24H2) | 26100.6899 | The latest generally available version of Azure Local. |
| Windows Server 2025 Datacenter Evaluation (Desktop Experience) | 26100.1742 | Windows Server 2025 Datacenter with the standard graphical user interface. |
| Windows Server 2022 Datacenter Evaluation (Desktop Experience) | 20348.587 | Windows Server 2022 Datacenter with the standard graphical user interface. |

### Selectable, but not tested

| Operating system | OS build | Description |
| ---- | ---- | ---- |
| Azure Local 2509 (24H2) | 26100.6584 | The previous version of Azure Local. |
| Azure Local 2508 (24H2) | 26100.4946 | The previous version of Azure Local. |
| Azure Local 2507 (24H2) | 26100.4652 | The previous version of Azure Local. |
| Azure Local 2506 (24H2) | 26100.4349 | The previous version of Azure Local. |
| Azure Local 2505 (24H2) | 26100.4061 | The previous version of Azure Local. |
| Azure Local 2504 (24H2) | 26100.3775 | This version of Azure Local reached the end of support. |
| Azure Local 2503 (23H2)<br>Azure Stack HCI, version 23H2 | 25398.1486 | This version of Azure Local (formerly Azure Stack HCI) reached the end of support. |
| Azure Stack HCI, version 22H2 | 20348.1607 | This version of Azure Stack HCI reached the end of support on May 31, 2025. |
| Azure Stack HCI, version 21H2 | 20348.288 | This version of Azure Stack HCI reached the end of support on November 14, 2023. |
| Azure Stack HCI, version 20H2 | 17784.1408 | This version of Azure Stack HCI reached the end of support on December 13, 2022. |

## ⚖️ License

Copyright (c) 2022-present Takeshi Katano. All rights reserved. This software is released under the [MIT License](https://github.com/tksh164/hci-lab/blob/main/LICENSE).

Disclaimer: The codes stored herein are my own personal codes and do not related my employer's any way.
