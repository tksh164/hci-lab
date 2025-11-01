//
// Parameters
//

@description('''The administrator user name.''')
@minLength(1)
@maxLength(20)
param adminUserName string = 'AzureUser'

@description('''The administrator password. The password must have 3 of the following: 1 lower case character, 1 upper case character, 1 number, and 1 special character. And the password must be between 12 and 123 characters long.''')
@secure()
param adminPassword string

@description('''The name of the lab host virtual machine resource name. This value is not used for the virtual machine's computer name.''')
@minLength(1)
@maxLength(64)
param labHostVmName string = 'labenv-vm1'

@description('''The size of the lab host virtual machine.''')
@allowed([
  // Required VM size capabilities:
  // - Generation 2 VM support
  // - Premium storage support
  // - Accelerated networking support
  // - Nested virtualization support
  // - 32+ GB RAM
  // - No temp storage

  // Esv6 series
  'Standard_E4s_v6'
  'Standard_E8s_v6'
  'Standard_E16s_v6'
  'Standard_E20s_v6'
  'Standard_E32s_v6'
  'Standard_E48s_v6'
  'Standard_E64s_v6'
  'Standard_E96s_v6'
  // 'Standard_E128s_v6'
  // 'Standard_E192s_v6'

  // Edsv6 series
  // 'Standard_E4ds_v6'
  // 'Standard_E8ds_v6'
  // 'Standard_E16ds_v6'
  // 'Standard_E20ds_v6'
  // 'Standard_E32ds_v6'
  // 'Standard_E48ds_v6'
  // 'Standard_E64ds_v6'
  // 'Standard_E96ds_v6'
  // 'Standard_E128ds_v6'
  // 'Standard_E192ds_v6'

  // Esv5 series
  'Standard_E4s_v5'
  'Standard_E8s_v5'
  'Standard_E16s_v5'
  'Standard_E20s_v5'
  'Standard_E32s_v5'
  'Standard_E48s_v5'
  'Standard_E64s_v5'
  'Standard_E96s_v5'

  // Edsv5 series
  // 'Standard_E4ds_v5'
  // 'Standard_E8ds_v5'
  // 'Standard_E16ds_v5'
  // 'Standard_E20ds_v5'
  // 'Standard_E32ds_v5'
  // 'Standard_E48ds_v5'
  // 'Standard_E64ds_v5'
  // 'Standard_E96ds_v5'

  // Ebsv5 series
  'Standard_E4bs_v5'
  'Standard_E8bs_v5'
  'Standard_E16bs_v5'
  'Standard_E32bs_v5'
  'Standard_E48bs_v5'
  'Standard_E64bs_v5'

  // Ebdsv5 series
  // 'Standard_E4bds_v5'
  // 'Standard_E8bds_v5'
  // 'Standard_E16bds_v5'
  // 'Standard_E32bds_v5'
  // 'Standard_E48bds_v5'
  // 'Standard_E64bds_v5'

  // Easv6 series
  'Standard_E16as_v6'
  'Standard_E20as_v6'
  'Standard_E32as_v6'
  'Standard_E48as_v6'
  'Standard_E64as_v6'
  'Standard_E96as_v6'

  // Eadsv6 series
  // 'Standard_E16ads_v6'
  // 'Standard_E20ads_v6'
  // 'Standard_E32ads_v6'
  // 'Standard_E48ads_v6'
  // 'Standard_E64ads_v6'
  // 'Standard_E96ads_v6'

  // Easv5 series
  'Standard_E16as_v5'
  'Standard_E20as_v5'
  'Standard_E32as_v5'
  'Standard_E48as_v5'
  'Standard_E64as_v5'
  'Standard_E96as_v5'

  // Eadsv5 series
  // 'Standard_E16ads_v5'
  // 'Standard_E20ads_v5'
  // 'Standard_E32ads_v5'
  // 'Standard_E48ads_v5'
  // 'Standard_E64ads_v5'
  // 'Standard_E96ads_v5'

  // Dsv6 series
  'Standard_D8s_v6'
  'Standard_D16s_v6'
  'Standard_D32s_v6'
  'Standard_D48s_v6'
  'Standard_D64s_v6'
  'Standard_D96s_v6'

  // Ddsv6 series
  // 'Standard_D8ds_v6'
  // 'Standard_D16ds_v6'
  // 'Standard_D32ds_v6'
  // 'Standard_D48ds_v6'
  // 'Standard_D64ds_v6'
  // 'Standard_D96ds_v6'

  // Dsv5 series
  'Standard_D8s_v5'
  'Standard_D16s_v5'
  'Standard_D32s_v5'
  'Standard_D48s_v5'
  'Standard_D64s_v5'
  'Standard_D96s_v5'

  // Ddsv5 series
  // 'Standard_D8ds_v5'
  // 'Standard_D16ds_v5'
  // 'Standard_D32ds_v5'
  // 'Standard_D48ds_v5'
  // 'Standard_D64ds_v5'
  // 'Standard_D96ds_v5'

  // Dasv6 series
  'Standard_D32as_v6'
  'Standard_D48as_v6'
  'Standard_D64as_v6'
  'Standard_D96as_v6'

  // Dadsv6 series
  // 'Standard_D32ads_v6'
  // 'Standard_D48ads_v6'
  // 'Standard_D64ads_v6'
  // 'Standard_D96ads_v6'

  // Dasv5 series
  'Standard_D32as_v5'
  'Standard_D48as_v5'
  'Standard_D64as_v5'
  'Standard_D96as_v5'

  // Dadsv5 series
  // 'Standard_D32ads_v5'
  // 'Standard_D48ads_v5'
  // 'Standard_D64ads_v5'
  // 'Standard_D96ads_v5'

  // Dlsv6 series
  'Standard_D16ls_v6'
  'Standard_D32ls_v6'
  'Standard_D48ls_v6'
  'Standard_D64ls_v6'
  'Standard_D96ls_v6'

  // Dldsv6 series
  // 'Standard_D16lds_v6'
  // 'Standard_D32lds_v6'
  // 'Standard_D48lds_v6'
  // 'Standard_D64lds_v6'
  // 'Standard_D96lds_v6'

  // Dlsv5 series
  'Standard_D16ls_v5'
  'Standard_D32ls_v5'
  'Standard_D48ls_v5'
  'Standard_D64ls_v5'
  'Standard_D96ls_v5'

  // Dldsv5 series
  // 'Standard_D16lds_v5'
  // 'Standard_D32lds_v5'
  // 'Standard_D48lds_v5'
  // 'Standard_D64lds_v5'
  // 'Standard_D96lds_v5'

  // Dsv4 series
  'Standard_D8s_v4'
  'Standard_D16s_v4'
  'Standard_D32s_v4'
  'Standard_D48s_v4'
  'Standard_D64s_v4'

  // Ddsv4 series
  // 'Standard_D8ds_v4'
  // 'Standard_D16ds_v4'
  // 'Standard_D32ds_v4'
  // 'Standard_D48ds_v4'
  // 'Standard_D64ds_v4'

  // Fasv6 series
  'Standard_F8as_v6'
  'Standard_F16as_v6'
  'Standard_F32as_v6'
  'Standard_F48as_v6'
  'Standard_F64as_v6'

  // Falsv6 series
  'Standard_F16als_v6'
  'Standard_F32als_v6'
  'Standard_F48als_v6'
  'Standard_F64als_v6'

  // Fsv2 series
  'Standard_F16s_v2'
  'Standard_F32s_v2'
  'Standard_F48s_v2'
  'Standard_F64s_v2'
  'Standard_F72s_v2'

  // FX series
  'Standard_FX4mds'
  'Standard_FX12mds'
  'Standard_FX24mds'
  'Standard_FX36mds'
  'Standard_FX48mds'
])
param labHostVmSize string = 'Standard_E16s_v5'

@description('''The storage type of the lab host virtual machine's OS disk.''')
@allowed(['Premium_LRS', 'StandardSSD_LRS', 'Standard_LRS'])
param labHostVmOsDiskType string = 'StandardSSD_LRS'

@description('''The storage type of the lab host virtual machine's data disk.''')
@allowed(['Premium_LRS', 'StandardSSD_LRS'])
param labHostVmDataDiskType string = 'StandardSSD_LRS'

@description('''The size of individual disk of the lab host virtual machine's data disks in GiB.''')
@allowed([32, 64, 128, 256, 512, 1024])
param labHostVmDataDiskSize int = 64

@description('''The number of data disks on the lab host virtual machine.''')
@minValue(8)
@maxValue(32)
param labHostVmDataDiskCount int = 8

@description('''By specifying True, you confirm you have an eligible Windows Server license with Software Assurance or Windows Server subscription to apply this Azure Hybrid Benefit. You can read more about compliance here: http://go.microsoft.com/fwlink/?LinkId=859786''')
param hasEligibleWindowsServerLicense bool = false

@description('''By specifying True, will be deploy Azure Bastion Developer.''')
param shouldDeployBastionDeveloper bool = false

@description('''The tools to be installed on the lab host virtual machine. Use ';' to separate tool's symbol. Supported tool's symbols are windowsterminal, vscode.''')
param toolsToInstall string = ''

@description('''By specifying True, will be auto-shutdown configured to the lab host virtual machine.''')
param shouldEnabledAutoshutdown bool = false

@description('''The auto-shutdown time.''')
param autoshutdownTime string = '22:00'

@description('''The time zone for auto-shutdown time.''')
param autoshutdownTimeZone string = 'UTC'

@description('''The operating system's culture of the lab virtual machines. This affects such as language and input method of the operating system.''')
@allowed(['en-us', 'ja-jp'])
param labVmOsCulture string = 'en-us'

@description('''The time zone of the lab virtual machines.''')
param labVmOsTimeZone string = 'UTC'

@description('''By specifying True, operating system's updates will be installed during the deployment.''')
param shouldInstallUpdatesToLabVm bool = false

@description('''The operating system for the HCI node virtual machines.''')
@allowed([
  'azloc24h2_2509' // Azure Local 24H2 2509
  'azloc24h2_2508' // Azure Local 24H2 2508
  'azloc24h2_2507' // Azure Local 24H2 2507
  'azloc24h2_2506' // Azure Local 24H2 2506
  'azloc24h2_2505' // Azure Local 24H2 2505
  'azloc24h2_2504' // Azure Local 24H2 2504
  'ashci23h2' // Azure Stack HCI 23H2 / Azure Local 23H2 2503
  'ashci22h2' // Azure Stack HCI 22H2
  'ashci21h2' // Azure Stack HCI 21H2
  'ashci20h2' // Azure Stack HCI 20H2
  'ws2025' // Windows Server 2025
  'ws2022' // Windows Server 2022
])
param hciNodeOsSku string = 'azloc24h2_2509'

@description('''The image index of the operating system for the HCI node virtual machines.''')
@allowed([
  1 // For Azure Stack HCI
  //3   // For Windows Server Datacenter Server Core
  4 // For Windows Server Datacenter with Desktop Experience
])
param hciNodeOsImageIndex int = 1

@description('''The number of HCI nodes to deploy.''')
@minValue(2)
@maxValue(8)
param hciNodeCount int = 2

@description('''By specifying True, the HCI nodes join to the AD DS domain during the deployment.''')
param shouldHciNodeJoinToAddsDomain bool = false

@description('''The Active Directory Domain Services domain FQDN.''')
param addsDomainFqdn string = 'lab.internal'

@description('''By specifying True, automatically create an HCI cluster during the deployment.''')
param shouldCreateHciCluster bool = false

@description('''The cluster name (cluster name object/CNO) for the HCI cluster.''')
param hciClusterName string = 'hciclus'

@description('''By specifying True, it means the deployment is Azure Local.''')
param isAzureLocalDeployment bool = false

@description('''By specifying True, the Azure Local AD objects will be created during the deployment.''')
param shouldPrepareAddsForAzureLocal bool = false

@description('''The Active Directory organizational Unit (OU) path to place the Azure Local related objects.''')
param addsOrgUnitPathForAzureLocal string = 'OU=AzureLocal,DC=lab,DC=internal'

@description('''The user name of the Lifecycle Manager (LCM) deployment user account.''')
param lcmUserName string = 'lcmuser'

@description('''By specifying True, the Configurator App for Azure Local will be installed during the deployment.''')
param shouldInstallConfigAppForAzureLocal bool = false

@description('''The base URI of template's repository. The value must end with '/'.''')
param repoBaseUri string = 'https://raw.githubusercontent.com/tksh164/hci-lab/main/template/'

@description('''The value for generate unique values.''')
param salt string = utcNow()

//
// Variables
//

// General
var location = resourceGroup().location
var uniquePart = substring(uniqueString(resourceGroup().id, salt), 0, 5)
var repoBaseUriWithSlash = endsWith(repoBaseUri, '/') ? repoBaseUri : '${repoBaseUri}/'
var deploymentApiVersion = '2025-04-01'

// Virtual network
var virtualNetwork = {
  deploymentName: 'deploy-vnet'
  apiVersion: deploymentApiVersion
  linkedTemplateUri: uri(repoBaseUriWithSlash, 'linkedtemplates/vnet.json')
  name: 'labenv-vnet'
}

// Bastion
var bastion = {
  deploymentName: 'deploy-bastion'
  apiVersion: deploymentApiVersion
  linkedTemplateUri: uri(repoBaseUriWithSlash, 'linkedtemplates/bastion.json')
  name: 'labenv-bastion'
}

// Lab host virtual machine
var hostVm = {
  deploymentName: 'deploy-host-vm'
  apiVersion: deploymentApiVersion
  linkedTemplateUri: uri(repoBaseUriWithSlash, 'linkedtemplates/hostvm.json')
}

// Key Vault
var keyVault = {
  deploymentName: 'deploy-key-vault'
  apiVersion: deploymentApiVersion
  linkedTemplateUri: uri(repoBaseUriWithSlash, 'linkedtemplates/keyvault.json')
  name: format('labenv-{0}-kv', toLower(uniquePart))
}

// Key Vault RBAC
var keyVaultRbac = {
  deploymentName: 'assign-key-vault-rbac-with-host-vm-managed-id'
  apiVersion: deploymentApiVersion
  linkedTemplateUri: uri(repoBaseUriWithSlash, 'linkedtemplates/keyvault-rbac.json')
}

// Storage account for witness
var witnessStorageAccount = {
  deploymentName: 'deploy-storage-account-witness'
  apiVersion: deploymentApiVersion
  linkedTemplateUri: uri(repoBaseUriWithSlash, 'linkedtemplates/cloudwitness.json')
  namePrefix: 'labenvwitness'
}

// DSC extension
var dscLinkedTemplateUri = uri(repoBaseUriWithSlash, 'linkedtemplates/dsc.json')
var dscExtensionName = 'hci-lab-dsc-extension'
var dscBaseUriWithSlash = uri(repoBaseUriWithSlash, 'dsc/') // Must end with "/".
var dsc = {
  installRolesFeatures: {
    deploymentName: 'install-roles-and-features-on-host-vm'
    apiVersion: deploymentApiVersion
    zipUri: uri(dscBaseUriWithSlash, 'install-roles-and-features.zip')
    scriptName: 'install-roles-and-features.ps1'
    functionName: 'install-roles-and-features'
  }
  rebootHostVm: {
    deploymentName: 'reboot-host-vm'
    apiVersion: deploymentApiVersion
    zipUri: uri(dscBaseUriWithSlash, 'reboot.zip')
    scriptName: 'reboot.ps1'
    functionName: 'reboot'
  }
}

// Custom script extensions
var customScriptLinkedTemplateUri = uri(repoBaseUriWithSlash, 'linkedtemplates/customscript.json')
var customScriptExtensionName = 'hci-lab-customscript-extension'
var customScriptBaseUriWithSlash = uri(repoBaseUriWithSlash, 'customscripts/') // Must end with "/".
var customScript = {
  configureHostVm: {
    deploymentName: 'configure-host-vm'
    apiVersion: deploymentApiVersion
    fileUris: [
      uri(customScriptBaseUriWithSlash, 'configure-lab-host.ps1')
      uri(customScriptBaseUriWithSlash, 'common.psm1')
    ]
    commandToExecute: 'powershell.exe -ExecutionPolicy Unrestricted -File .\\configure-lab-host.ps1'
  }
  downloadIsoUpdates: {
    deploymentName: 'download-materials'
    apiVersion: deploymentApiVersion
    fileUris: [
      uri(customScriptBaseUriWithSlash, 'download-iso-updates.ps1')
      uri(customScriptBaseUriWithSlash, 'download-iso-updates-asset-urls.psd1')
      uri(customScriptBaseUriWithSlash, 'common.psm1')
    ]
    commandToExecute: 'powershell.exe -ExecutionPolicy Unrestricted -File .\\download-iso-updates.ps1'
  }
  createBaseVhd: {
    deploymentName: 'create-base-vhd'
    apiVersion: deploymentApiVersion
    fileUris: [
      uri(customScriptBaseUriWithSlash, 'create-base-vhd.ps1')
      uri(customScriptBaseUriWithSlash, 'create-base-vhd-job.ps1')
      uri(customScriptBaseUriWithSlash, 'common.psm1')
    ]
    commandToExecute: 'powershell.exe -ExecutionPolicy Unrestricted -File .\\create-base-vhd.ps1'
  }
  createVm: {
    deploymentName: 'create-lab-vms'
    apiVersion: deploymentApiVersion
    fileUris: [
      uri(customScriptBaseUriWithSlash, 'create-vm.ps1')
      uri(customScriptBaseUriWithSlash, 'create-vm-job-addsdc.ps1')
      uri(customScriptBaseUriWithSlash, 'create-vm-job-wac.ps1')
      uri(customScriptBaseUriWithSlash, 'create-vm-job-hcinode.ps1')
      uri(customScriptBaseUriWithSlash, 'common.psm1')
    ]
    commandToExecute: 'powershell.exe -ExecutionPolicy Unrestricted -File .\\create-vm.ps1'
  }
  createHciCluster: {
    deploymentName: 'create-hci-cluster'
    apiVersion: deploymentApiVersion
    fileUris: [
      uri(customScriptBaseUriWithSlash, 'create-hci-cluster.ps1')
      uri(customScriptBaseUriWithSlash, 'create-hci-cluster-test-cat-en-us.psd1')
      uri(customScriptBaseUriWithSlash, 'create-hci-cluster-test-cat-ja-jp.psd1')
      uri(customScriptBaseUriWithSlash, 'common.psm1')
    ]
    commandToExecute: 'powershell.exe -ExecutionPolicy Unrestricted -File .\\create-hci-cluster.ps1'
  }
}

// Configuration parameters
var labConfig = {
  labHost: {
    storage: {
      poolName: 'hcilabpool'
      driveLetter: 'V'
      volumeLabel: 'HCI Lab Data'
    }
    folderPath: {
      log: 'C:\\temp\\hcilab-logs'
      temp: 'V:\\temp'
      updates: 'V:\\temp\\updates'
      vhd: 'V:\\vhd'
      vm: 'V:\\vm'
    }
    vSwitch: {
      nat: {
        name: 'HciLabNAT'
      }
    }
    netNat: [
      {
        name: 'ManagementNAT'
        InternalAddressPrefix: '172.16.0.0/24'
        hostInternalIPAddress: '172.16.0.1'
        hostInternalPrefixLength: 24
      }
      {
        name: 'ComputeNAT'
        InternalAddressPrefix: '10.0.0.0/16'
        hostInternalIPAddress: '10.0.0.1'
        hostInternalPrefixLength: 16
      }
    ]
    toolsToInstall: toolsToInstall
  }
  guestOS: {
    culture: labVmOsCulture
    timeZone: labVmOsTimeZone
    shouldInstallUpdates: shouldInstallUpdatesToLabVm
  }
  addsDomain: {
    fqdn: addsDomainFqdn
  }
  addsDC: {
    vmName: 'addsdc'
    maximumRamBytes: 2147483648
    netAdapters: {
      management: {
        name: 'Management'
        ipAddress: '172.16.0.2'
        prefixLength: 24
        defaultGateway: '172.16.0.1'
        dnsServerAddresses: ['168.63.129.16']
      }
    }
    shouldPrepareAddsForAzureLocal: shouldPrepareAddsForAzureLocal
    orgUnitForAzureLocal: addsOrgUnitPathForAzureLocal
    lcmUserName: lcmUserName
  }
  wac: {
    vmName: 'workbox'
    maximumRamBytes: 6442450944
    netAdapters: {
      management: {
        name: 'Management'
        ipAddress: '172.16.0.3'
        prefixLength: 24
        defaultGateway: '172.16.0.1'
        dnsServerAddresses: ['172.16.0.2']
      }
    }
    shouldInstallConfigAppForAzureLocal: shouldInstallConfigAppForAzureLocal
  }
  hciNode: {
    vmName: 'machine{0:00}' // vmNameOffset + ZeroBasedNodeIndex
    vmNameOffset: 1
    operatingSystem: {
      sku: hciNodeOsSku
      imageIndex: hciNodeOsImageIndex
    }
    nodeCount: hciNodeCount
    shouldJoinToAddsDomain: shouldHciNodeJoinToAddsDomain
    isAzureLocalDeployment: isAzureLocalDeployment
    dataDiskSizeBytes: 1099511627776
    ipAddressOffset: 11
    netAdapters: {
      management: {
        name: 'Management'
        ipAddress: '172.16.0.{0}' // ipAddressOffset + ZeroBasedNodeIndex
        prefixLength: 24
        defaultGateway: '172.16.0.1'
        dnsServerAddresses: ['172.16.0.2']
      }
      compute: {
        name: 'Compute'
        ipAddress: '10.0.0.{0}' // ipAddressOffset + ZeroBasedNodeIndex
        prefixLength: 16
      }
      storage1: {
        name: 'Storage1'
        vlanId: 711
        ipAddress: '172.20.1.{0}' // ipAddressOffset + ZeroBasedNodeIndex
        prefixLength: 24
      }
      storage2: {
        name: 'Storage2'
        vlanId: 712
        ipAddress: '172.20.2.{0}' // ipAddressOffset + ZeroBasedNodeIndex
        prefixLength: 24
      }
    }
  }
  hciCluster: {
    shouldCreateCluster: shouldHciNodeJoinToAddsDomain && shouldCreateHciCluster
    name: hciClusterName
    ipAddress: '172.16.0.200'
  }
  keyVault: {
    name: keyVault.name
    secretName: {
      adminPassword: 'AdminPassword'
      cloudWitnessStorageAccountName: 'CloudWitnessStorageAccountName'
      cloudWitnessStorageAccountKey: 'CloudWitnessStorageAccountKey'
    }
  }
}

//
// Resources
//

// Virtual network
resource res_vnet 'Microsoft.Resources/deployments@2025-04-01' = {
  name: virtualNetwork.deploymentName
  properties: {
    mode: 'Incremental'
    templateLink: {
      uri: virtualNetwork.linkedTemplateUri
      contentVersion: '1.0.0.0'
    }
    parameters: {
      location: {
        value: location
      }
      virtualNetworkName: {
        value: virtualNetwork.name
      }
    }
  }
}

// module vnet './vnet.bicep' = {
//   name: virtualNetwork.deploymentName
//   params: {
//     location: location
//     virtualNetworkName: virtualNetwork.name
//   }
// }

// Bastion
resource res_bastion 'Microsoft.Resources/deployments@2025-04-01' = if (shouldDeployBastionDeveloper) {
  name: bastion.deploymentName
  dependsOn: [
    res_vnet
  ]
  properties: {
    mode: 'Incremental'
    templateLink: {
      uri: bastion.linkedTemplateUri
      contentVersion: '1.0.0.0'
    }
    parameters: {
      location: {
        value: location
      }
      bastionName: {
        value: bastion.name
      }
      virtualNetworkId: {
        value: res_vnet.properties.outputs.virtualNetworkId.value
      }
    }
  }
}

// Lab host virtual machine.
resource res_labHostVm 'Microsoft.Resources/deployments@2025-04-01' = {
  name: hostVm.deploymentName
  dependsOn: [
    res_vnet
  ]
  properties: {
    mode: 'Incremental'
    templateLink: {
      uri: hostVm.linkedTemplateUri
      contentVersion: '1.0.0.0'
    }
    parameters: {
      location: {
        value: location
      }
      subnetId: {
        value: res_vnet.properties.outputs.subnetId.value.default
      }
      vmName: {
        value: labHostVmName
      }
      adminUserName: {
        value: adminUserName
      }
      adminPassword: {
        value: adminPassword
      }
      vmSize: {
        value: labHostVmSize
      }
      osDiskType: {
        value: labHostVmOsDiskType
      }
      dataDiskType: {
        value: labHostVmDataDiskType
      }
      dataDiskSize: {
        value: labHostVmDataDiskSize
      }
      dataDiskCount: {
        value: labHostVmDataDiskCount
      }
      hasEligibleWindowsServerLicense: {
        value: hasEligibleWindowsServerLicense
      }
      base64EncodedLabConfig: {
        value: base64(string(labConfig))
      }
      shouldEnabledAutoshutdown: {
        value: shouldEnabledAutoshutdown
      }
      autoshutdownTime: {
        value: autoshutdownTime
      }
      autoshutdownTimeZone: {
        value: autoshutdownTimeZone
      }
      uniqueString: {
        value: uniquePart
      }
    }
  }
}

// Key Vault
resource res_keyVault 'Microsoft.Resources/deployments@2025-04-01' = {
  name: keyVault.deploymentName
  dependsOn: [
    res_vnet
  ]
  properties: {
    mode: 'Incremental'
    templateLink: {
      uri: keyVault.linkedTemplateUri
      contentVersion: '1.0.0.0'
    }
    parameters: {
      location: {
        value: location
      }
      keyVaultName: {
        value: keyVault.name
      }
      hostVmSubnetId: {
        value: res_vnet.properties.outputs.subnetId.value.default
      }
      secretNameForLabHostAdminPassword: {
        value: labConfig.keyVault.secretName.adminPassword
      }
      labHostAdminPassword: {
        value: adminPassword
      }
    }
  }
}

// Key Vault RBAC
resource res_keyVaultRbac 'Microsoft.Resources/deployments@2025-04-01' = {
  name: keyVaultRbac.deploymentName
  dependsOn: [
    res_labHostVm
    res_keyVault
  ]
  properties: {
    mode: 'Incremental'
    templateLink: {
      uri: keyVaultRbac.linkedTemplateUri
      contentVersion: '1.0.0.0'
    }
    parameters: {
      keyVaultName: {
        value: keyVault.name
      }
      servicePrincipalId: {
        value: res_labHostVm.properties.outputs.principalId.value
      }
      roleDefinitionId: {
        value: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4633458b-17de-408a-b874-0445c86b69e6') // Key Vault Secrets User
      }
    }
  }
}

// Storage account for the witness.
resource res_witnessStorageAccount 'Microsoft.Resources/deployments@2025-04-01' = if (!isAzureLocalDeployment) {
  name: witnessStorageAccount.deploymentName
  dependsOn: [
    res_vnet
    res_keyVault
  ]
  properties: {
    mode: 'Incremental'
    templateLink: {
      uri: witnessStorageAccount.linkedTemplateUri
      contentVersion: '1.0.0.0'
    }
    parameters: {
      location: {
        value: location
      }
      storageAccountNamePrefix: {
        value: witnessStorageAccount.namePrefix
      }
      uniqueString: {
        value: uniquePart
      }
      hostVmSubnetId: {
        value: res_vnet.properties.outputs.subnetId.value.default
      }
      keyVaultName: {
        value: keyVault.name
      }
      secretNameForStorageAccountName: {
        value: labConfig.keyVault.secretName.cloudWitnessStorageAccountName
      }
      secretNameForStorageAccountKey: {
        value: labConfig.keyVault.secretName.cloudWitnessStorageAccountKey
      }
    }
  }
}

// Install roles and features.
resource res_installRolesFeatures 'Microsoft.Resources/deployments@2025-04-01' = {
  name: dsc.installRolesFeatures.deploymentName
  dependsOn: [
    res_labHostVm
  ]
  properties: {
    mode: 'Incremental'
    templateLink: {
      uri: dscLinkedTemplateUri
      contentVersion: '1.0.0.0'
    }
    parameters: {
      location: {
        value: location
      }
      parentVmResourceName: {
        value: labHostVmName
      }
      extensionName: {
        value: dscExtensionName
      }
      zipUri: {
        value: dsc.installRolesFeatures.zipUri
      }
      scriptName: {
        value: dsc.installRolesFeatures.scriptName
      }
      functionName: {
        value: dsc.installRolesFeatures.functionName
      }
    }
  }
}

// Configure the lab host.
resource res_configureHostVm 'Microsoft.Resources/deployments@2025-04-01' = {
  name: customScript.configureHostVm.deploymentName
  dependsOn: [
    res_keyVaultRbac
    res_installRolesFeatures
  ]
  properties: {
    mode: 'Incremental'
    templateLink: {
      uri: customScriptLinkedTemplateUri
      contentVersion: '1.0.0.0'
    }
    parameters: {
      location: {
        value: location
      }
      parentVmResourceName: {
        value: labHostVmName
      }
      extensionName: {
        value: customScriptExtensionName
      }
      fileUris: {
        value: customScript.configureHostVm.fileUris
      }
      commandToExecute: {
        value: customScript.configureHostVm.commandToExecute
      }
    }
  }
}

// Download ISO files and updates.
resource res_downloadIsoUpdates 'Microsoft.Resources/deployments@2025-04-01' = {
  name: customScript.downloadIsoUpdates.deploymentName
  dependsOn: [
    res_configureHostVm
  ]
  properties: {
    mode: 'Incremental'
    templateLink: {
      uri: customScriptLinkedTemplateUri
      contentVersion: '1.0.0.0'
    }
    parameters: {
      location: {
        value: location
      }
      parentVmResourceName: {
        value: labHostVmName
      }
      extensionName: {
        value: customScriptExtensionName
      }
      fileUris: {
        value: customScript.downloadIsoUpdates.fileUris
      }
      commandToExecute: {
        value: customScript.downloadIsoUpdates.commandToExecute
      }
    }
  }
}
