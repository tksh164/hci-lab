# Deploy AKs on Windows Server 2022 with HCI Lab

This document describes deployment steps to deploy AKS on Windows Server 2022 using HCI Lab.

## 1. Deploy HCI Lab

### Basics tab

- **Project details**
    - Subscription:
    - Resource group:

- **Instance details**
    - Region:
    - Lab host VM name:
    - Size:

- **Administrator account**
    - Username:
    - Password:
    - Confirm password:

- **Azure Hybrid Benefit**
    - You can apply Azure Hybrid Benefit if you have an eligible Windows Server license with Software Assurance or Windows Server subscription.

### Lab host details tab

- **Disks**
    - OS disk type:
    - Data disk type:

- **Data volume**
    - Data volume capacity:

- **Apps**
    - Windows Terminal:
    - Visual Studio Code:

- **Auto-shutdown**
    - Auto-shutdown:

### Lab environment tab

- **Common configuration**
    - Culture
    - Time zone
    - Operating system's updates

- **HCI node**
    - Operating system: Select **Windows Server 2022 Datacenter Evaluation (Desktop Experience)**.
    - Node count: Select how many nodes you want for your HCI cluster.
    - Join to the AD domain: Select **Join**.

- **HCI cluster**

- **Active Directory Domain Services**

    - AD domain FQDN

### Advanced tab

You can skip this tab because there are no necessary settings for this case. Click the **Next** button.

### Review + create tab

Click the **Create** button to start your HCI Lab deployment.

## Register resource providers

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

## RBAC

TODO:

## 2. Connect to your HCI Lab host using RDP connection

## 3. Install prerequisites

### Install the AksHci PowerShell module

Install the AksHci PowerShell module to all HCI nodes. You can do this at once from the HCI Lab host using PowerShell Direct.

```powershell
$cred = Get-Credential -UserName 'HCI\Administrator' -Message 'Enter domain administrator password.'
$vmName = 'hcinode01', 'hcinode02'
Invoke-Command -VMName $vmName -Credential $cred -ScriptBlock {
    Install-Module -Name 'AksHci' -Repository 'PSGallery' -AcceptLicense -Force -Verbose
}
```

### Initialize HCI nodes

Initialize HCI nodes. You can do this at once from the HCI Lab host using PowerShell Direct.

```powershell
$cred = Get-Credential -UserName 'HCI\Administrator' -Message 'Enter domain administrator password.'
$vmName = 'hcinode01', 'hcinode02'
Invoke-Command -VMName $vmName -Credential $cred -ScriptBlock {
    Initialize-AksHciNode
}
```

## 2. Create a new management cluster

First of all, you need to deploy a new management cluster. It's AKS itself, some times it called an AKS host. You should do this on one of the HCI nodes.

### Create a virtual network setting for your management cluster

Create a virtual network setting for your AKS deployment using [New-AksHciNetworkSetting](https://learn.microsoft.com/en-us/azure/aks/hybrid/reference/ps/new-akshcinetworksetting).

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

### Set an AKS configuration

Set AKS configuration for your AKS deployment using [Set-AksHciConfig](https://learn.microsoft.com/en-us/azure/aks/hybrid/reference/ps/set-akshciconfig). The configuration will be saved on your volume.

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

### Register an Azure Arc-enabled Kubernetes resource for your management cluster

You need to register your management cluster to Azure as an Azure Arc connected Kubernetes. In this step, set the registration information for the registration using [Set-AksHciRegistration](https://learn.microsoft.com/en-us/azure/aks/hybrid/reference/ps/set-akshciregistration).

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

### Deploy your management cluster

Start a task to deploy your management cluster using [Install-AksHci](https://learn.microsoft.com/en-us/azure/aks/hybrid/reference/ps/install-akshci).

```powershell
Install-AksHci -Verbose
```

### Get your management cluster configuration

```powershell
Get-AksHciConfig
```


## Create a new workload cluster

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

## List workload clusters

```powershell
```

## Deploy an application to your workload cluster

```powershell
Get-AksHciCredential -Name 'akswc1'
```

## Delete your workload cluster

```powershell
Remove-AksHciCluster -Name 'akswc1'
```

## Delete your management cluster

```powershell
Uninstall-AksHci
```

## Troubleshooting

### Connect to AKS node in your AKS cluster

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
