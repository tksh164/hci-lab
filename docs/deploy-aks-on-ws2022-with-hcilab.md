# Deploy AKs on Windows Server 2022 with HCI Lab

## Create a new management cluster

### Create a virtual network setting for the management cluster

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

```powershell
$params = @{
    TenantId                = 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx'
    SubscriptionId          = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
    ResourceGroupName       = 'aksws2022-rg'
    UseDeviceAuthentication = $true
    Verbose                 = $true
}
Set-AksHciRegistration @params
```

### Deploy your management cluster

```powershell
Install-AksHci -Verbose
```

## Create a new workload cluster

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
