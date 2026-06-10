# Tutorial: Deploy Azure Local with Azure Local Lab

> **Note:** This tutorial is based on Azure Local 2605.

This tutorial describes the Azure Local deployment sequence with Azure Local Lab. The Azure Local deployment sequence has [6 steps](https://learn.microsoft.com/azure/azure-local/deploy/deployment-introduction). Azure Local Lab provides automation of step 1 to 3.

| Step | Step # in Azure Local deployment sequence | Step # in this tutorial |
| ---- | :--: | :--: |
| Prepare Active Directory | 1 | 1 |
| Download the operating system | 2 | 1 |
| Install the OS to the machines | 3 | 1 |
| Set up subscription permissions | 4 | 2 |
| Register Azure Local machines with Azure Arc | 5 | 3 |
| Deploy the system | 6 | 4 |

We recommend that you quickly review the [Lab tour](https://github.com/tksh164/hci-lab/blob/main/docs/hci-lab-tour.md) before starting the Azure Local Lab deployment to familiarize yourself with Azure Local Lab.

## 1. Deploy Azure Local Lab environment

This step covers [Step 1: Prepare Active Directory](https://learn.microsoft.com/azure/azure-local/deploy/deployment-prep-active-directory), [Step 2: Download the operating system](https://learn.microsoft.com/azure/azure-local/deploy/download-23h2-software) and [Step 3A: Install OS manually via ISO](https://learn.microsoft.com/azure/azure-local/deploy/deployment-install-os).

1. Open the Azure portal from the **Deploy to Azure** button on the [README](https://github.com/tksh164/hci-lab/blob/main/README.md) to deploy your lab environment. To keep the README open, use Ctrl + Click to open the Azure portal in a new tab.

    > **Tip:** The only difference between languages is the UI language displayed when you deploy your lab environment in the Azure portal. The language does not affect the lab environment you deploy.

    > **Tip:** We recommend choosing **Yes, I trust the authors** to use the user friendly deployment UI. Read the [FAQ](./hci-lab-tour.md#why-the-trust-confirmation-message-shown-when-opening-deploy-to-azure) for details.

2. Fill out required fields in the UI form.

    **Basics tab**

    - **Project details**
        - **Subscription:** Select a subscription to deploy your Azure Local Lab.
        - **Resource group:** Select a resource group to deploy your Azure Local Lab.

    - **Instance details**
        - **Region:** Select a region to deploy your Azure Local Lab resources.
        - **Lab host VM name:** Specify your Azure Local Lab host VM's name.
        - **Size:** Select your lab host VM size. The default VM size or larger is recommended.

    - **Administrator account**
        - **Username:** Specify the username for your Azure Local Lab host VM. This username will also be used for Hyper-V VMs in your Azure Local Lab environment.
        - **Password:** Specify the password for your Azure Local Lab host VM. This password will also be used for Hyper-V VMs in your Azure Local Lab environment.
        - **Confirm password:** Re-enter the password for confirmation.

    - **Azure Hybrid Benefit**
        - You can apply Azure Hybrid Benefit if you have an eligible Windows Server license with Software Assurance or Windows Server subscription.

    **Lab host tab**

    - **Disks**
        - **OS disk type:** Select the lab host VM's OS disk type. It is recommended to use the default value.
        - **Data disk type:** Select the lab host VM's data disk type. It is recommended to use the default value.

    - **Data volume**
        - **Data volume capacity:** Select the data volume capacity. All assets in your lab are stored on this volume. It is recommended to use the default volume size or larger.

    - **Azure Bastion Developer**
        - Select **Enable** if you want to use Azure Bastion to access your lab host VM. Bastion Developer is a free, lightweight offering of the Azure Bastion service. It is ideal for Dev/Test users who want to securely connect to VMs. It is recommended to select **Enable** even if you plan to connect to your lab host via any Remote Desktop client because there is no tradeoff.

    - **Apps**
        - **Visual Studio Code:** Select this if you want to install Visual Studio Code on your Azure Local lab host VM.

    - **Auto-shutdown**
        - **Auto-shutdown:** Enable this if you want to use the auto-shutdown feature.

    **Azure Local tab**

    - **Machine configuration**
        - **Operating system:** Use the default value in the case of this tutorial. The default value is the latest Azure Local release.
        - **Number of machines:** Select how many Azure Local machines you want for your Azure Local Lab. In this tutorial, use the default value.

    **Active Directory tab**

    - **Active Directory domain**
        - **AD domain FQDN:** The Active Directory domain FQDN for your Azure Local Lab environment. Leave default for this tutorial.

    - **Preparation for Azure Local deployment**
        - **Active Directory preparation for Azure Local deployment:** Select **Prepare Active Directory** for this tutorial. By select this, [Step 1: Prepare Active Directory](https://learn.microsoft.com/azure/azure-local/deploy/deployment-prep-active-directory) will done during Azure Local Lab deployment.
        - **AD organization unit (OU) for Azure Local:** Use the default value for this tutorial.
        - **Lifecycle Manager (LCM) user account name:** Use the default value for this tutorial.

    **Peripheral servers tab**

    - **General configuration**
        - **Culture:** Use the default value **English (en-US)** for this tutorial. This option specify the display language, locale and input method of the operating systems for peripheral servers in your lab environment.
        - **Time zone:** Use the default value **(UTC) Coordinated Universal Time** for this tutorial. This option specify the time zone of the operating systems for peripheral servers in your lab environment.
        - **Operating system's updates:** Use the default value **Not install** for this tutorial.

    - **Tools on the workbox machine**
        - **Configurator App for Azure Local:** Use the default value **Install** for this tutorial. We will use the Configurator App in the later steps.
        - **Windows Admin Center:** Leave with default value for this tutorial.

    **Advanced options tab**

    You can skip this tab because there are no necessary settings for this tutorial. Click **Next**.

    **Review + create tab**

    Click **Create** to start your Azure Local Lab deployment. The deployment process will take 30 to 40 minutes.

## 2. Set up the required permissions on your subscription to deploy Azure Local

This step covers [Step 4: Set up subscription permissions](https://learn.microsoft.com/azure/azure-local/deploy/deployment-arc-register-server-permissions).

1. Register required resource providers. Make sure that your Azure subscription is registered with the required resource providers. To register, you must be an **Owner** or **Contributor** on your subscription. You can also ask the administrator of your Azure subscription to register them.

    ```powershell
    $providerNamespaces = @(
        'Microsoft.HybridCompute'
        'Microsoft.GuestConfiguration'
        'Microsoft.HybridConnectivity'
        'Microsoft.AzureStackHCI'
        'Microsoft.Kubernetes'
        'Microsoft.KubernetesConfiguration'
        'Microsoft.ExtendedLocation'
        'Microsoft.ResourceConnector'
        'Microsoft.HybridContainerService'
        'Microsoft.Attestation'
        'Microsoft.Storage'
        'Microsoft.Insights'
        'Microsoft.KeyVault'
    )

    # Register required resource providers.
    $providerNamespaces |% { Register-AzResourceProvider -ProviderNamespace $_ }

    # Check the registration state of the required resource providers. All resource providers should show as "Registered".
    Get-AzResourceProvider -ProviderNamespace $providerNamespaces | Group-Object -Property 'RegistrationState'
    ```

2. Verify roles on the resource group to register machines as Arc resources. Make sure that you have either the **Owner** role on the resource group or the following roles on the resource group where the machines are provisioned as Arc resources.

    - Azure Connected Machine Onboarding
    - Azure Connected Machine Resource Administrator

    In this tutorial, we will register machines to the same resource group that we deployed Azure Local Lab in the previous step.

3. Verify roles on the resource group that used to register machines as Arc resources to deploy Azure Local instance for the later steps. Assign the following permissions to the user who deploys the Azure Local instance.

    - Key Vault Data Access Administrator
    - Key Vault Secrets Officer
    - Key Vault Contributor
    - Storage Account Contributor

    In this tutorial, we will deploy Azure Local instance into the same resource group that we deployed Azure Local Lab in the previous step.

4. Verify roles on the Azure subscription for Azure Local deployment. Assign the following roles to the user who deploys the Azure Local instance.

    - Azure Stack HCI Administrator
    - Reader

**Summary of roles for this tutorial:**

| Purpose | Scope | Roles | Assign access to | Notes |
| ---- | ---- | ---- | ---- | ---- |
| Arc Machine registration | The **resource group** that you specify in **1. Deploy Azure Local Lab environment** | Require one of them: <ul><li>Owner</li><li>Azure Connected Machine Onboarding and Azure Connected Machine Resource Administrator</li></ul> | The user who registers the machines as Arc resources. In this tutorial, that's you. | You don't need to worry about these permissions if you have the **Owner** role on the Azure subscription because the permissions are inherited from the Azure subscription down to the resource group. |
| Azure Local instance deployment | The **resource group** that you specify in **1. Deploy Azure Local Lab environment** | Require all: <ul><li>Key Vault Data Access Administrator</li><li>Key Vault Secrets Officer</li><li>Key Vault Contributor</li><li>Storage Account Contributor</li></ul> | The user who deploys the Azure Local instance. In this tutorial, that's you. | You can actually skip preparation for these permissions because they are granted during the Azure Local instance deployment via the Azure portal. |
| Azure Local instance deployment | The **Azure subscription** that you specify in **1. Deploy Azure Local Lab environment** | Require all: <ul><li>Azure Stack HCI Administrator</li><li>Reader</li></ul> | The user who deploys the Azure Local instance. In this tutorial, that's you. | The **Reader** role is not required if you have the **Owner** role on the Azure subscription. The **Owner** role is a superset role of the **Reader** role. |

> **Tip:** Actually, for this tutorial, you need to configure only the **Azure Stack HCI Administrator** role if you have the **Owner** role of the Azure subscription.

## 3. Register Azure Local machines with Azure Arc using Configurator app

This step covers [Step 5A: Register Azure Local machines with Azure Arc, without using the Arc gateway](https://learn.microsoft.com/azure/azure-local/deploy/deployment-without-azure-arc-gateway).

1. You need to allow Remote Desktop access to your lab host Azure VM from your local machine. You can do this by [enabling JIT VM access](https://learn.microsoft.com/azure/defender-for-cloud/enable-just-in-time-access) or [adding an inbound security rule in the Network Security Group](https://learn.microsoft.com/azure/virtual-network/tutorial-filter-network-traffic?tabs=portal#create-security-rules). The recommended way is using JIT VM access.

2. Connect to your lab host Azure VM using your favorite Remote Desktop client. To connect, use the credentials that you specified in **1. Deploy Azure Local Lab environment**.

3. Open the Hyper-V Manager that located on the desktop and connect to **workbox**.

4. Sign into **workbox** using the domain administrator credentials. That is `LAB\Administrator` in this tutorial. The password is you specified in **1. Deploy Azure Local Lab environment** as the password of Administrator account.

5. Launch **Configurator App** from the Start menu. You can find **Configurator App** in the list of all apps.

6. Connect a machine in Configurator App.

    - Machine name: machine01
    - Sign in (Username): Administrator
    - Enter password: The password that you specified in **1. Deploy Azure Local Lab environment** as the password of Administrator account.
    - Security alert: Click **Accept**

7. Wait for the prerequisites check to finish. All items showing a skipped status. And, then click **Configure device** to start the configuration.

8. In the **Basics** step, click **Edit network settings** and select **Management** if it is not already selected as a network interface, then click **Apply**. After that click **Next**.

    **Network settings:**

    - Interface: Management
    - Allocation: Static
    - IP address: 172.16.0.11
    - Subnet: 255.255.255.0
    - Gateway: 172.16.0.1

    **DNS server:**

    - Assignment: Custom
    - DNS: 172.16.0.2

    **Additional details:**

    - Remote desktop: Disabled
    - Connectivity: Public endpoint
    - Time zone: UTC
    - Time server: time.windows.com
    - Hostname: MACHINE01

9. In the **Arc agent setup** step, enter the following information then click **Next**. Do not use the **Log in to Azure** button in this tutorial.

    - Cloud type: Azure
    - Subscription: The subscription ID to create an Arc Machine resource of the machine. In this tutorial, enter the subscription ID that you specified in **1. Deploy Azure Local Lab environment**.
    - Resource group: The resource group name to create an Arc Machine resource of the machine. In this tutorial, enter the resource group name that you specified in **1. Deploy Azure Local Lab environment**.
    - Region: The region to create an Arc Machine resource of the machine such as **japaneast**. In this tutorial, enter the region that you specified in **1. Deploy Azure Local Lab environment**.
    - Tenant ID: Optional, but we recommend entering the tenant ID, especially if the user who registers the machine as an Arc Machine belongs multiple tenants.
    - Arc gateway ID: Specify the Arc gateway's resource ID if you use Arc gateway. Leave empty in this tutorial.

10. In the **Review and apply** step, review the configuration details and click **Done**.

11. In the **Configuration status** page, wait for the device code to be shown to register the machine as an Arc Machine. Enter the code and complete authentication on [https://login.microsoft.com/device](https://login.microsoft.com/device) from any device.

12. Repeat the above steps for all machines.

    > **Tip:** You can register multiple machines at the same time.

## 4. Deploy Azure Local instance via the Azure portal

This step covers [Step 6A: Deploy the system via Azure portal](https://learn.microsoft.com/azure/azure-local/deploy/deploy-via-portal).

To deploy a new Azure Local instance, search **Azure Local** in the Azure portal then click **Create instance**.

### 4.1 Basics tab

1. **Project details**

    - Subscription: Select a subscription to deploy Azure Local instance. In this tutorial, select the same subscription that you selected in **1. Deploy Azure Local Lab environment**.
    - Resource group: Select a resource group to deploy Azure Local instance. In this tutorial, select the same resource group that you selected in **1. Deploy Azure Local Lab environment**.

2. **Instance details**

    - Instance name: Specify the Azure Local instance resource name. e.g. **azloc1**
    - Region: Select a region for the Azure Local instance resource, such as **Japan East**.
    - Cluster options: Select **Standard** for this tutorial.
    - Storage options: Select **Storage Spaces Direct (S2D)** for this tutorial.

3. **Identity provider**

    - Identity provider for cluster: Select **Active Directory** for this tutorial.

4. **Select the machines to use and validate**

    1. Click **Add machines** to select the machines to deploy. In this tutorial, you can select 2 machines. Add all selectable machines. Click **Add** to begin installing the extension on Arc Machines. Wait for the extension installation to complete on all Arc Machines. It may take around 10 minutes.

    2. Click **Validate selected machines**. The validation should be successful.

    3. Select **Create a new Key Vault** and click **Create a new key vault** to create a new Key Vault for Azure Local deployment. Enter a valid Key Vault name that must be globally unique and use the default value for other fields. Then click **Create**.

    4. If a message **Insufficient permissions at resource group level. click here** is shown, click **Grant Key Vault permissions** to grant required permissions.

        > **Tip:** Azure Local deployment needs **Allow public access from all networks** setting on the newly create Key Vault. You should check the setting before go forward if your organization disabled/disallow the setting by policy. In some cases, the organization provides special tags to except the policy.

5. Click **Next: Configuration**.

### 4.2 Configuration tab

1. Select **New configuration** on Source.

2. Click **Next: Networking**.

### 4.3 Networking tab

1. **Choose whether to use a network switch for the storage network**

    - Storage connectivity: Select **Network switch for storage** for this tutorial.

2. **Group network traffic types by intent**

    - Networking pattern: Select **Custom configuration** for this tutorial. Azure Local Lab also supports other patterns.

3. **Provide intent details**

    - Intent 1
        1. Traffic types: Select **Management** for this tutorial.
        2. Intent name: Enter the intent name. e.g. **Management**
        3. Network adapter 1: Select **Management [Microsoft Hyper-V Network Adapter] (172.16.0.11)** for this tutorial.
        4. Click **Customize network settings** in Intent 1 and change **RDMA protocol** to **Disabled** then click **Save**. Use the default value except RDMA protocol. Azure Local Lab leverages nested virtualization and it does not support any RDMA protocols.

    - Intent 2
        1. Traffic types: Select **Compute** for this tutorial.
        2. Intent name: Enter the intent name. e.g. **Compute**
        3. Network adapter 1: Select **Compute [Microsoft Hyper-V Network Adapter] (10.0.0.11)** for this tutorial.
        4. Click **Customize network settings** in Intent 2 and change **RDMA protocol** to **Disabled** then click **Save**. Use the default value except RDMA protocol.

    - Intent 3
        1. Traffic types: Select **Storage** for this tutorial.
        2. Intent name: Enter the intent name. e.g. **Storage**
        3. Network adapter 1: Select **Storage1 [Microsoft Hyper-V Network Adapter] (169.254.xx.xx)** for this tutorial.
        4. Storage Network 1 VLAN ID: Use the default value **711**.
        5. Click **Select another adapter for this traffic** in Intent 3.
        6. Network adapter 2: Select **Storage2 [Microsoft Hyper-V Network Adapter] (169.254.xx.xx)** for this tutorial.
        7. Storage Network 2 VLAN ID: Use the default value **712**.
        8. Click **Customize network settings** in Intent 3 and change **RDMA protocol** to **Disabled** then click **Save**. Use the default value except RDMA protocol.

4. **Nodes and Instance IP assignment**

    - Nodes and Instance IPs assignments: Select **Manual** for this tutorial.

5. **Allocate IP addresses to the system and services**

    1. Enter the following values.

        - Starting IP: **172.16.0.21**
        - Ending IP: **172.16.0.26**
        - Subnet mask: **255.255.255.0**
        - Default gateway: **172.16.0.1**
        - DNS server: **172.16.0.2**

    2. Click **Validate Subnet**

6. Click **Next: Management**.

### 4.4 Management tab

1. **Specify a custom location name**

    - Custom location name: Enter the location resource name. e.g. **azloc1-location**

2. **Specify system witness settings**

    - Witness type: **Cloud witness** in this tutorial. If you have an odd number of machines, it will be **No witness**.
    - Azure storage account name: Click **Create new** and enter globally unique storage account name on **Storage account name**. Use the default value for other fields. Then click **Create**.

        > **Tip:** Azure Local deployment needs the following settings on the newly create Storage account. You should check the settings before go forward if your organization disabled/disallow the setting by policy. In some cases, the organization provides special tags to except the policy.
        > - Allow public access from all networks
        > - Allow storage account key access

3. **Specify Active Directory details**

    - Domain: Enter **lab.internal** in this tutorial.
    - OU: Enter **OU=AzureLocal,DC=lab,DC=internal** in this tutorial.

4. **Deployment account**

    - Username: Enter **lcmuser** in this tutorial.
    - Password: Enter the password that you specified in **1. Deploy Azure Local Lab environment** that entered as the password of Administrator account.
    - Confirm password: Enter the same password as Password.

5. **Local administrator**

    - Username: Enter **Administrator** in this tutorial.
    - Password: Enter the password that you specified in **1. Deploy Azure Local Lab environment** that entered as the password of Administrator account.
    - Confirm password: Enter the same password as Password.

6. Click **Next: Security**.

### 4.5 Security tab

1. **Set the security level of your system's infrastructure**

    - Security level: Select **Recommended security settings** in this tutorial.

2. Click **Next: Advanced**.

### 4.6 Advanced tab

1. **Create workload and infrastructure volumes**

    - Volumes: Select **Create one workload volume and storage path per machine, and one required infrastructure volume per system (Recommended)** in this tutorial.

2. Click **Next: Tags**.

### 4.7 Tags tab

Leave default for this tutorial. Click **Next: Validation**.

### 4.8 Validation tab

1. **Resource Creation**

    - The resource creation starts automatically when you open the Validation tab. It will take around 2 minutes.

2. **Validation progress**

    1. Click **Start validation** to start validation. The validation will take around 40 minutes.

3. Click **Next: Review + create**.

### 4.9 Review + create tab

1. Click **Create** to start Azure Local instance deployment. Azure Local deployment will take around 3.5 hours. You can check progress on **Deployments** in the Azure Local resource.
