# Deploy AKs on Windows Server 2022 with HCI Lab

This document describes deployment steps to deploy AKS on Windows Server 2022 using HCI Lab.

## 1. Deploy HCI Lab

**Basics tab**

- **Project details**
    - **Subscription:** Select a subscription to use deploy your HCI Lab.
    - **Resource group:** Select a resource group to use deploy your HCI Lab.

- **Instance details**
    - **Region:** Select a region to deploy your HCI Lab resources.
    - **Lab host VM name:** Specify your HCI Lab host VM's name.
    - **Size:** Select a your lab host VM size. Recommend the default VM size or larger VM sizes.

- **Administrator account**
    - **Username:** Specify the user name for your HCI Lab host VM. Also, this user name will be used for Hyper-V VMs in your HCI Lab environment.
    - **Password:** Specify the password for your HCI Lab host VM. Also, this password will be used for Hyper-V VMs in your HCI Lab environment.
    - **Confirm password:** Re-enter the password for confirmation.

- **Azure Hybrid Benefit**
    - You can apply Azure Hybrid Benefit if you have an eligible Windows Server license with Software Assurance or Windows Server subscription.

**Lab host details tab**

- **Disks**
    - **OS disk type:** Select the lab host VM's OS disk type. Recommend to use the default value.
    - **Data disk type:** Select the lab host VM's data disk type. Recommend to use the default value.

- **Data volume**
    - **Data volume capacity:** Select the data volume capacity. All assets in your lab stored on this volume. Recommend the default volume size or larger.

- **Apps**
    - **Visual Studio Code:** Select this if you want to install Visual Studio Code on your HCI lab host VM.

- **Auto-shutdown**
    - **Auto-shutdown:** Enable this if you want to use auto-shutdown feature.

**Lab environment tab**

- **Common configuration**
    - **Culture:** Select a culture for Hyper-V VMs in your HCI Lab environment. The culture represents the UI language, locale and input method.
    - **Time zone:** Select a time zone for Hyper-V VMs in your HCI Lab environment.
    - **Operating system's updates:** Select this if you want to install updates to Hyper-VMs in your HCI Lab environment. The operating system's updates installation will increase the deployment time.

- **HCI node**
    - **Operating system:** Select **Windows Server 2022 Datacenter Evaluation (Desktop Experience)**.
    - **Node count:** Select how many nodes you want for your HCI cluster.
    - **Join to the AD domain:** Select **Join**.

- **Active Directory Domain Services**

    - **AD domain FQDN:** The Active Directory domain FQDN in your HCI Lab environment. Leave default for this tutorial.

**Advanced tab**

You can skip this tab because there are no necessary settings for this case. Click the **Next** button.

**Review + create tab**

Click the **Create** button to start your HCI Lab deployment.

## 2. Register resource providers

You have to register resource providers before your management cluster registration. You can do this on Azure Cloud Shell.

```powershell
$providerNamespaces = @(
    'Microsoft.Kubernetes',
    'Microsoft.KubernetesConfiguration',
    'Microsoft.ExtendedLocation'
)
$providerNamespaces |% { Register-AzResourceProvider -ProviderNamespace $_ }
Get-AzResourceProvider -ProviderNamespace $providerNamespaces | ft ProviderNamespace, RegistrationState
```

## 3. RBAC

You must have sufficient permissions in your Azure environment. See [the details about the permissions](https://learn.microsoft.com/azure/aks/aksarc/system-requirements?tabs=allow-table#azure-requirements) to deploy AKS on Windows Server 2022.

## 4. Connect to your HCI Lab host using RDP connection

After completing the deployment, you need to allow Remote Desktop access to your lab host Azure VM from your local machine. It can be by [enabling JIT VM access](https://learn.microsoft.com/azure/defender-for-cloud/just-in-time-access-usage) or [adding an inbound security rule in the Network Security Group](https://learn.microsoft.com/azure/virtual-network/tutorial-filter-network-traffic#create-security-rules). The recommended way is using JIT VM access.

Next, connect to your lab host Azure VM using your favorite Remote Desktop client. To connect, use the credentials that you specified at deployment.

## 5. Install prerequisites

### 5.1. Install the AksHci PowerShell module

Install the AksHci PowerShell module to all HCI nodes. You can do this at once **from the HCI Lab host** using PowerShell Direct.

```powershell
$cred = Get-Credential -UserName 'HCI\Administrator' -Message 'Enter domain administrator password.'
$vmName = 'hcinode01', 'hcinode02'
Invoke-Command -VMName $vmName -Credential $cred -ScriptBlock {
    Install-Module -Name 'AksHci' -Repository 'PSGallery' -AcceptLicense -Force -Verbose
}
Invoke-Command -VMName $vmName -Credential $cred -ScriptBlock {
    Get-Module -Name 'AksHci' -ListAvailable
}
```

You will get the following output as the result.

```powershell
    Directory: C:\Program Files\WindowsPowerShell\Modules

ModuleType Version    Name   ExportedCommands                            PSComputerName
---------- -------    ----   ----------------                            --------------
Script     1.2.16     AksHci {New-AksHciStorageContainer, Enable-AksH... hcinode01
Script     1.2.16     AksHci {New-AksHciStorageContainer, Enable-AksH... hcinode02
```

### 5.2. Initialize HCI nodes

Initialize HCI nodes. You can do this at once **from the HCI Lab host** using PowerShell Direct.

```powershell
$cred = Get-Credential -UserName 'HCI\Administrator' -Message 'Enter domain administrator password.'
$vmName = 'hcinode01', 'hcinode02'
Invoke-Command -VMName $vmName -Credential $cred -ScriptBlock {
    Initialize-AksHciNode
}
```

You will see the following messages the same number of times as the number of your HCI nodes.

```
WinRM service is already running on this machine.
WinRM is already set up for remote management on this computer.
```

## 6. Create a new management cluster

First of all, you need to deploy a new management cluster. It's AKS itself, some times it called an AKS host. **You should do this on one of the HCI nodes**.

### 6.1. Signin to the one of your HCI nodes

Sign-in to the one of your HCI nodes with `HCI\Administrator` and the password for that account.

### 6.2. Create a virtual network setting for your management cluster

Create a virtual network setting for your AKS deployment using [New-AksHciNetworkSetting](https://learn.microsoft.com/azure/aks/hybrid/reference/ps/new-akshcinetworksetting).

```powershell
$VerbosePreference = 'Continue'
$params = @{
    Name               = 'akshci-main-network'
    VSwitchName        = 'ComputeSwitch'
    Gateway            = '10.0.0.1'
    DnsServers         = '172.16.0.2'
    IpAddressPrefix    = '10.0.0.0/16'
    K8sNodeIpPoolStart = '10.0.0.11'
    K8sNodeIpPoolEnd   = '10.0.0.40'
    VipPoolStart       = '10.0.0.41'
    VipPoolEnd         = '10.0.0.250'
}
$vnet = New-AksHciNetworkSetting @params
```

The `$vnet` has the following values after execute the above.

```powershell
PS C:\> $vnet

Name               : akshci-main-network
VswitchName        : ComputeSwitch
IpAddressPrefix    : 10.0.0.0/16
Gateway            : 10.0.0.1
DnsServers         : {172.16.0.2}
MacPoolName        : MocMacPool
Vlanid             : 0
VipPoolStart       : 10.0.0.41
VipPoolEnd         : 10.0.0.250
K8snodeIPPoolStart : 10.0.0.11
K8snodeIPPoolEnd   : 10.0.0.40
```

### 6.3. Set an AKS configuration

Set AKS configuration for your AKS deployment using [Set-AksHciConfig](https://learn.microsoft.com/azure/aks/hybrid/reference/ps/set-akshciconfig). The configuration will be saved on your volume.

```powershell
$clusterRoleName = 'akshci-mgmt-cluster-{0}' -f (Get-Date).ToString('yyMMdd-HHmm')
$baseDir         = 'C:\ClusterStorage\HciVol\akshci'
$params = @{
    ImageDir            = Join-Path -Path $baseDir -ChildPath 'Images'
    WorkingDir          = Join-Path -Path $baseDir -ChildPath 'WorkingDir'
    CloudConfigLocation = Join-Path -Path $baseDir -ChildPath 'Config'
    SkipHostLimitChecks = $false
    ClusterRoleName     = $clusterRoleName
    CloudServiceCidr    = '172.16.0.51/24'
    VNet                = $vnet
    KvaName             = $clusterRoleName
    ControlplaneVmSize  = 'Standard_A4_v2'
    Verbose             = $true
}
Set-AksHciConfig @params
```

### 6.4. Register an Azure Arc-enabled Kubernetes resource for your management cluster

You need to register your management cluster to Azure as an Azure Arc connected Kubernetes. In this step, set the registration information for the registration using [Set-AksHciRegistration](https://learn.microsoft.com/azure/aks/hybrid/reference/ps/set-akshciregistration).

```powershell
$params = @{
    TenantId                = 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx'
    SubscriptionId          = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
    ResourceGroupName       = 'aksws2022-rg'  # The resource group name that put an Arc-enabled Kubernetes resource of your management cluster.
    UseDeviceAuthentication = $true
    Verbose                 = $true
}
Set-AksHciRegistration @params
```

### 6.5. Deploy your management cluster

Start a task to deploy your management cluster using [Install-AksHci](https://learn.microsoft.com/azure/aks/hybrid/reference/ps/install-akshci).

```powershell
Install-AksHci -Verbose
```

### 6.6. Confirm your management cluster configuration

```powershell
PS C:\> $config = Get-AksHciConfig

PS C:\> $config

Name                           Value
----                           -----
Moc                            {defaultVipPoolName, proxyServerHTTP, manifestCache, cloudAgentPort...}
AksHci                         {catalog, cachedLatestAksHciVersion, offsiteTransferCompleted, ring...}
Kva                            {catalog, controlplaneVmSize, containerRegistryServer, identity...}

# AKS-HCI
PS C:\> $config.AksHci

Name                           Value
----                           -----
catalog                        aks-hci-stable-catalogs-ext
cachedLatestAksHciVersion      1.0.24.11029
offsiteTransferCompleted       False
ring                           stable
cachedLatestPSVersion          1.2.16
skipUpdates                    False
concurrentDownloads            1
proxyServerNoProxy
proxyServerCertFile
caCertRotationThreshold        90
proxyServerHTTPS
installState                   Installed
version                        1.0.24.11029
cachedMinAksHciVersion         1.0.14.10929
deploymentId                   ef7d5be9-a260-4575-b503-7bb938ca42d6
mocInstalledByAksHci           True
workingDir                     C:\ClusterStorage\HciVol\akshci\WorkingDir
commands                       {}
proxyServerPassword
offlineDownload                False
useStagingShare                False
proxyServerUsername
proxyServerHTTP
manifestCache                  C:\ClusterStorage\HciVol\akshci\WorkingDir\aks-hci-stable-catalogs-ext.json
useHTTPSForDownloads           False
stagingShare
moduleVersion                  1.2.16
enableOptionalDiagnosticData   False
latestVersionsCachedOn         12/20/2024 1:59:13 AM
skipCleanOnFailure             False
installationPackageDir         C:\ClusterStorage\HciVol\akshci\WorkingDir\1.0.24.11029

# KVA
PS C:\> $config.Kva

Name                           Value
----                           -----
catalog                        aks-hci-stable-catalogs-ext
controlplaneVmSize             Standard_A4_v2
containerRegistryServer        ecpacr.azurecr.io
identity                       bmFtZTogYWtzaGNpLW1nbXQtY2x1c3Rlci0yNDEyMjAtMDE0Mwp0b2tlbjogZXlKaGJHY2lPaUpTVXpJMU5pSXNJbXRwWkNJNklqazROalEzTVdWaFlUazJPVEV4WlRaaU4yTTVPV0kyTkdJeE5HTTNOVEJoTjJabU16aGp...
kubeconfig                     C:\ClusterStorage\HciVol\akshci\WorkingDir\1.0.24.11029\kubeconfig-mgmt
offsiteTransferCompleted       False
ring                           stable
workingDir                     C:\ClusterStorage\HciVol\akshci\WorkingDir
k8snodeippoolend               10.0.0.40
containerRegistryUser
imageDir                       C:\ClusterStorage\HciVol\akshci\Images
skipUpdates                    False
vlanid                         0
proxyServerNoProxy
version                        1.0.24.11029
proxyServerCertFile
vnetvippoolstart               10.0.0.41
# *** snip ***

# MOC
PS C:\> $config.Moc

Name                           Value
----                           -----
defaultVipPoolName
proxyServerHTTP
manifestCache                  C:\ClusterStorage\HciVol\akshci\WorkingDir\aks-hci-stable-catalogs-ext.json
cloudAgentPort                 55000
installState                   Installed
imageDir                       C:\ClusterStorage\HciVol\akshci\Images
useUpdatedFailoverClusterCr... False
offsiteTransferCompleted       False
proxyServerNoProxy
accessFileDirPath              C:\ClusterStorage\HciVol\akshci\WorkingDir\CloudCfg
isolateImageDir                False
ring                           stable
skipHostAgentInstall           True
skipUpdates                    False
nodeAgentPort                  45000
cloudConfigLocation            C:\ClusterStorage\HciVol\akshci\Config
networkControllerLnetRef
isolateAutoConfiguredContai...
cloudServiceCidr               172.16.0.51/24
proxyServerCertFile
proxyServerUsername
gateway                        10.0.0.1
# *** snip ***
```

## 7. Create a new workload cluster

Create a new workload cluster. You can create multiple workload clusters and use those to run your workloads.

```powershell
$params = @{
    Name                  = 'akswc1'
    ControlplaneVmSize    = 'Standard_A4_v2'
    ControlPlaneNodeCount = 1
    LoadBalancerVmSize    = 'Standard_A2_v2'
    NodePoolName          = 'nodepool1'
    OSType                = 'Linux'
    NodeVmSize            = 'Standard_A2_v2'
    NodeCount             = 2
    Verbose               = $true
}
New-AksHciCluster @params
```

## 8. (Optional) Connect your workload cluster to Arc-enabled Kubernetes

You can connect your cluster to Arc-enabled Kubernetes optionally using [Enable-AksHciArcConnection](https://learn.microsoft.com/azure/aks/aksarc/reference/ps/enable-akshciarcconnection). The following example connects your Kubernetes cluster to Arc using the subscription and resource group details you passed in [Set-AksHciRegistration](https://learn.microsoft.com/azure/aks/hybrid/reference/ps/set-akshciregistration).

```powershell
Enable-AksHciArcConnection -Name 'akswc1'
```

## Common operations

### List workload clusters

<!-- TODO: Fill here out later. -->

```powershell
PS C:\> Get-AksHciCluster

Status                : {ProvisioningState, Details}
ProvisioningState     : Deployed
KubernetesVersion     : v1.29.4
PackageVersion        : v1.29.4
NodePools             : nodepool1
WindowsNodeCount      : 0
Windows2022NodeCount  : 0
LinuxNodeCount        : 2
ControlPlaneNodeCount : 1
ControlPlaneVmSize    : Standard_A4_v2
AutoScalerEnabled     : False
AutoScalerProfile     :
LoadBalancer          : {VMSize, Count, Sku}
ImageName             : Linux_k8s_1.0.24.11029
Name                  : akswc1

Status                : {ProvisioningState, Details}
ProvisioningState     : Deployed
KubernetesVersion     : v1.29.4
PackageVersion        : v1.29.4
NodePools             : nodepool2
WindowsNodeCount      : 0
Windows2022NodeCount  : 0
LinuxNodeCount        : 2
ControlPlaneNodeCount : 1
ControlPlaneVmSize    : Standard_A4_v2
AutoScalerEnabled     : False
AutoScalerProfile     :
LoadBalancer          : {VMSize, Count, Sku}
ImageName             : Linux_k8s_1.0.24.11029
Name                  : akswc2
```

### Get a credential for connect to your workload cluster

<!-- TODO: Fill here out later. -->

```powershell
Get-AksHciCredential -Name 'akswc1'
```

### Delete your workload cluster

<!-- TODO: Fill here out later. -->

```powershell
Remove-AksHciCluster -Name 'akswc1'
```

### Delete your management cluster

<!-- TODO: Fill here out later. -->

```powershell
Uninstall-AksHci
```

### Connect to AKS node in your AKS cluster

<!-- TODO: Fill here out later. -->

```powershell
PS C:\> kubectl get node -o wide
NAME              STATUS   ROLES           AGE     VERSION   INTERNAL-IP   EXTERNAL-IP   OS-IMAGE            KERNEL-VERSION     CONTAINER-RUNTIME
moc-ld8m2h02ctd   Ready    control-plane   5d20h   v1.28.5   10.0.0.13     <none>        CBL-Mariner/Linux   5.15.153.1-2.cm2   containerd://1.6.26
moc-lfyz2fx9bvx   Ready    <none>          3d19h   v1.28.5   10.0.0.15     <none>        CBL-Mariner/Linux   5.15.153.1-2.cm2   containerd://1.6.26
moc-lml3wnueug3   Ready    <none>          5d20h   v1.28.5   10.0.0.14     <none>        CBL-Mariner/Linux   5.15.153.1-2.cm2   containerd://1.6.26
```

```powershell
$sshPrivateKeyPath = (Get-AksHciConfig).Moc.sshPrivateKey
ssh.exe clouduser@10.0.0.13 -i $sshPrivateKeyPath
```

<!-- ### Deploy an application to your workload cluster -->
