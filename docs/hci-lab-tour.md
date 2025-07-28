# HCI Lab tour

## Virtual machines

The HCI lab environment consists of three roles of Hyper-V VMs on a single Azure VM.

| Computer/VM name | Role | VM kind<br/>(Host) | AD domain joined | Operating system | Notes |
| ---- | ---- | ---- | ---- | ---- | --- |
| labenv-vm1 (default) | Lab host | Azure VM<br/>(Azure) | No | Windows Server 2025 Datacenter Azure Edition Hotpatch | |
| hcinode## | HCI node | Hyper-V VM<br/>(Lab host) | Depends on your deploy option | Depends on your deploy option. You can choose Azure Local or Windows Server (Desktop Experience). | `##` in the name is changed depending on the number of HCI nodes such as `01`, `02`, `03`, ... |
| addsdc | Domain controller of Active Directory Domain Services | Hyper-V VM<br/>(Lab host) | Yes | Windows Server 2025 Datacenter Evaluation (Server Core) | |
| wac | Management tools server | Hyper-V VM<br/>(Lab host) | Yes | Windows Server 2025 Datacenter Evaluation (with Desktop Experience) | Windows Admin Center works on this server with gateway mode, and many server management tools are installed on this server. |

### Lab host (Azure VM)

- Deploy options
    - **Visual Studio Code:** You can install Visual Studio Code during the deployment if you choose the deployment option.

- Credentials

    | Account type | User name | Password |
    | ---- | ---- | ---- |
    | Local administrator | Your supplied user name at Azure VM deployment. | Your supplied password at Azure VM deployment. |

- Remote Desktop access
    - You need to allow Remote Desktop access to your lab host Azure VM from your local machine. It can be by [enabling JIT VM access](https://learn.microsoft.com/en-us/azure/defender-for-cloud/just-in-time-access-usage) or [adding an inbound security rule in the Network Security Group](https://learn.microsoft.com/en-us/azure/virtual-network/tutorial-filter-network-traffic#create-security-rules).
    - The recommended way is using JIT VM access.

- Desktop icons

    | Icon | Notes |
    | ---- | ---- |
    | Windows Admin Center | Open Windows Admin Center on the management tools server (**wac**) Hyper-V VM with Microsoft Edge.  |
    | Management tools server | Connect to the management tools server (**wac**) Hyper-V VM using Remote Desktop. |
    | hcinode01 | Connect to a HCI node (**hcinode01**) Hyper-V VM using Remote Desktop. |
    | Hyper-V Manager | Open the Hyper-V Manager to manage Hyper-V VMs for the HCI lab environment. |
    | Visual Studio Code | There is an icon if installed via deployment option. |

- Data volume
    - Volume **V:** is the data volume. Hyper-V VM files, VHD files, ISO file and other working files are stored on this volume.

- If you deallocate your Azure VM, all Hyper-V VMs that run on your Azure VM are shutting down according to the Automatic Stop Action of the Hyper-V setting.
    - Sometimes, you will see the unexpected shutdown dialog at the next sign-in to the Hyper-V VMs. It means the Hyper-V VM could not complete shutting down in acceptable time. It's rare that unexpected shutdown has impacts on your lab environment.
    - You can manually shutdown the Hyper-V VMs before Azure VM deallocation safely.

- The log files of the custom scripts are stored under `C:\temp\hcilab-logs` in the lab host Azure VM. Those log files are helpful for troubleshooting when deployment fails.

### VMs in the lab environment (Hyper-V VMs)

- Deploy options
    - **Join to the AD DS domain:** Should you choose to **Not join** if you plan to [provisioning your HCI cluster from Azure portal](https://learn.microsoft.com/en-us/azure-stack/hci/deploy/deploy-via-portal).
    - **Create HCI cluster:** You can automatically create your HCI cluster during the deployment if you choose the deployment option. Also, by not choosing it, you can manually create an HCI cluster for cluster creation with custom configuration such as Network ATC.

- AD domain name (default): **hci.internal**

- Credentials

    | Account type | User name | Password |
    | ---- | ---- | ---- |
    | Domain administrator | HCI\\Administrator | Your supplied password in the HCI Lab deployment. |
    | Local administrator | Administrator | Your supplied password in the HCI Lab deployment. |

- You can access each Hyper-V VM such as **wac**, **hcinode##**, **addsdc** in you lab environment via Remote Desktop connection (mstsc.exe) and Virtual Machine connection (vmconnect.exe) from the lab host VM (Azure VM).

- Windows Server 2022/2025 Datacenter Evaluation expires in **180 days**.

- Management tools server (**wac** VM)

    - Windows Admin Center works on the **wac** VM as gateway mode. You can access via `https://wac/` from the **wac** VM and the lab host VM.
    - Traditional server management tools (RSAT) are installed on the **wac** VM.

    - Desktop icons on the wac VM

        | Icon | Notes |
        | ---- | ---- |
        | Windows Admin Center | Open Windows Admin Center on the management tools server (**wac**) Hyper-V VM with Microsoft Edge.  |
        | hcinode01 | Connect to a HCI node (**hcinode01**) Hyper-V VM using Remote Desktop. |

## Networking

### Simplified logical networking configuration

- [Large image](https://raw.githubusercontent.com/tksh164/hci-lab/main/docs/media/hci-lab-networking-logical-simplified.svg)

![](./media/hci-lab-networking-logical-simplified.svg)

### _With_ the HCI cluster creation option deployment

- [Large image](https://raw.githubusercontent.com/tksh164/hci-lab/main/docs/media/hci-lab-networking-with-hci-cluster.svg)

![](./media/hci-lab-networking-with-hci-cluster.svg)

### _Without_ the HCI cluster creation option deployment

- [Large image](https://raw.githubusercontent.com/tksh164/hci-lab/main/docs/media/hci-lab-networking-without-hci-cluster.svg)

![](./media/hci-lab-networking-without-hci-cluster.svg)
