# 🗺️ HCI Lab tour

## Virtual machines

The HCI lab environment consists of three roles of Hyper-V VMs on a single Azure VM.

| Computer/VM name | Role | VM type (Host) | AD DS domain joined | Operating system | Notes |
| ---- | ---- | ---- | ---- | ---- | --- |
| hcilab-vm1 (default) | Lab host | Azure VM (Azure) | No | Windows Server 2022 Datacenter Azure Edition | |
| hcinode## | HCI node | Hyper-V VM (Lab host) | Yes | Depends on your deploy option. You can choose Azure Stack HCI or Windows Server 2022 Datacenter Evaluation. | **##** in the name is changed depending on the number of HCI nodes such as 01, 02, 03, ... |
| addsdc | Active Directory Domain Services Domain Controller | Hyper-V VM (Lab host) | Yes | Windows Server 2022 Datacenter Evaluation (Server Core) | |
| wac | Management tools server | Hyper-V VM (Lab host) | Yes | Windows Server 2022 Datacenter Evaluation (with Desktop Experience) | Windows Admin Center works on this machine as gateway mode, and many server management tools are installed on this machine. |

### Lab host VM (Azure VM)

- Deploy options
    - Windows Terminal: You can install Windows Terminal during the deployment if you choose the deployment option.
    - Visual Studio Code: You can install Visual Studio Code during the deployment if you choose the deployment option.

- Credentials

    | Account type | User name | Password |
    | ---- | ---- | ---- |
    | Local administrator | Your supplied user name at Azure VM deployment. | Your supplied password at Azure VM deployment. |

- Remote Desktop access
    - You need to allow Remote Desktop access to your lab host Azure VM from your local machine. It can be by [enabling JIT VM access](https://learn.microsoft.com/en-us/azure/defender-for-cloud/just-in-time-access-usage) or [adding an inbound security rule in the Network Security Group](https://learn.microsoft.com/en-us/azure/virtual-network/tutorial-filter-network-traffic#create-security-rules).
    - The recommended way is using JIT VM access.

- Desktop icons
    - Remote Desktop - WAC: Connect to the wac VM using Remote Desktop.
    - Windows Admin Center: Open Windows Admin Center on the wac VM with Microsoft Edge. 
    - Hyper-V Manager
    - Visual Studio Code (if installed via deployment option)

- Data volume
    - Volume **V:** is the data volume. Hyper-V VM files, VHD files, ISO file and other working files are stored on this volume.

- The log files of the custom scripts are stored under `C:\temp\hcilab-logs` in the lab host Azure VM. Those log files are helpful for troubleshooting when deployment fails.

### VMs in the lab environment (Hyper-V VMs)

- Deploy options
    - HCI cluster creation: You can automatically create an HCI cluster during the deployment if you choose the deployment option. Also, by not choosing it, you can manually create an HCI cluster for cluster creation with custom configuration such as Network ATC.

- AD DS domain name: **hci.local** (default)

- Credentials

    | Account type | User name | Password |
    | ---- | ---- | ---- |
    | Domain administrator | HCI\\Administrator | Your supplied password at Azure VM deployment. |
    | Local administrator | Administrator | Your supplied password at Azure VM deployment. |

- Management tools
    - Windows Admin Center works on the **wac** VM as gateway mode. You can access via `https://wac/` from the **wac** VM and the lab host VM.
    - Traditional server management tools (RSAT) are installed on the **wac** VM.

- Desktop icons on the wac VM
    - Windows Admin Center: Open Windows Admin Center on the wac VM with Microsoft Edge. 

- Windows Server 2022 Datacenter Evaluation expires in **180 days**.

## Networking

### The HCI lab networking deployment with the HCI cluster creation option

![](./media/hci-lab-networking-with-hci-cluster.svg)

### The HCI lab networking deployment without the HCI cluster creation option

![](./media/hci-lab-networking-without-hci-cluster.svg)

