import {
  osSymbol
  osImageIndex
  supportedOsLanguage
  vmAdminUserName
  vmResourceName
  supportedOsDiskType
  supportedDataDiskType
  supportedDataDiskSize
  supportedDataDiskCount
  supportedNodeMachineCount
  supportedVmSize
  labConfiguration
} from './types.bicep'

//
// Parameters
//

@description('''The administrator user name.''')
param adminUserName vmAdminUserName = 'AzureUser'

@description('''The administrator password. The password must be between 14 and 72 characters and have 4 of the following: 1 lower case character, 1 upper case character, 1 number, and 1 special character.''')
@secure()
param adminPassword string

@description('''The name of the lab host virtual machine resource name. This value is not used for the virtual machine's computer name.''')
param labHostVmName vmResourceName = 'labenv-vm1'

@description('''The size of the lab host virtual machine.''')
param labHostVmSize supportedVmSize = 'Standard_E16s_v5'

@description('''The storage type of the lab host virtual machine's OS disk.''')
param labHostVmOsDiskType supportedOsDiskType = 'StandardSSD_LRS'

@description('''The storage type of the lab host virtual machine's data disk.''')
param labHostVmDataDiskType supportedDataDiskType = 'StandardSSD_LRS'

@description('''The size of individual disk of the lab host virtual machine's data disks in GiB.''')
param labHostVmDataDiskSize supportedDataDiskSize = 64

@description('''The number of data disks on the lab host virtual machine.''')
param labHostVmDataDiskCount supportedDataDiskCount = 8

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
param labVmOsCulture supportedOsLanguage = 'en-us'

@description('''The time zone of the lab virtual machines.''')
param labVmOsTimeZone string = 'UTC'

@description('''By specifying True, operating system's updates will be installed during the deployment.''')
param shouldInstallUpdatesToLabVm bool = false

@description('''The operating system for the HCI node virtual machines.''')
param hciNodeOsSku osSymbol = 'azloc24h2_2606'

@description('''The image index of the operating system for the HCI node virtual machines.''')
param hciNodeOsImageIndex osImageIndex = 1

@description('''The number of HCI nodes to deploy.''')
param hciNodeCount supportedNodeMachineCount = 2

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
param repoBaseUri string = 'https://raw.githubusercontent.com/tksh164/hci-lab/main/templates/labenv/'

@description('''The value for generate unique values.''')
param salt string = utcNow()

//
// Variables
//

// General
var location = resourceGroup().location
var uniquenessFactor = substring(uniqueString(resourceGroup().id, salt), 0, 5)
var repoBaseUrlNormalized = endsWith(repoBaseUri, '/') ? repoBaseUri : '${repoBaseUri}/'

// DSC extension
var dscExtensionName = 'labenv-dsc-extension'
var dscBaseUrl = uri(repoBaseUrlNormalized, 'dsc/')  // Must end with "/".

// Custom script extensions
var customScriptExtensionName = 'labenv-customscript-extension'
var customScriptBaseUrl = uri(repoBaseUrlNormalized, 'customscripts/')  // Must end with "/".

// Configuration parameters
var labConfig labConfiguration = {
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
    vmName: 'machine{0:00}'  // vmNameOffset + ZeroBasedNodeIndex
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
        ipAddress: '172.16.0.{0}'  // ipAddressOffset + ZeroBasedNodeIndex
        prefixLength: 24
        defaultGateway: '172.16.0.1'
        dnsServerAddresses: ['172.16.0.2']
      }
      compute: {
        name: 'Compute'
        ipAddress: '10.0.0.{0}'  // ipAddressOffset + ZeroBasedNodeIndex
        prefixLength: 16
      }
      storage1: {
        name: 'Storage1'
        vlanId: 711
        ipAddress: '172.20.1.{0}'  // ipAddressOffset + ZeroBasedNodeIndex
        prefixLength: 24
      }
      storage2: {
        name: 'Storage2'
        vlanId: 712
        ipAddress: '172.20.2.{0}'  // ipAddressOffset + ZeroBasedNodeIndex
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
    name: format('labenv-{0}-kv', toLower(uniquenessFactor))
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
module mod_vnet './vnet.bicep' = {
  name: 'deploy-vnet'
  params: {
    location: location
    virtualNetworkName: 'labenv-vnet'
  }
}

// Bastion
module mod_bastion './bastion.bicep' = if (shouldDeployBastionDeveloper) {
  name: 'deploy-bastion'
  params: {
    location: location
    bastionName: 'labenv-bastion'
    virtualNetworkId: mod_vnet.outputs.virtualNetworkId
  }
}

// Lab host virtual machine.
module mod_labHostVm './hostvm.bicep' = {
  name: 'deploy-host-vm'
  params: {
    location: location
    subnetId: mod_vnet.outputs.subnetId.default
    vmName: labHostVmName
    adminUserName: adminUserName
    adminPassword: adminPassword
    vmSize: labHostVmSize
    osDiskType: labHostVmOsDiskType
    dataDiskType: labHostVmDataDiskType
    dataDiskSize: labHostVmDataDiskSize
    dataDiskCount: labHostVmDataDiskCount
    hasEligibleWindowsServerLicense: hasEligibleWindowsServerLicense
    base64EncodedLabConfig: base64(string(labConfig))
    shouldEnabledAutoshutdown: shouldEnabledAutoshutdown
    autoshutdownTime: autoshutdownTime
    autoshutdownTimeZone: autoshutdownTimeZone
    uniqueString: uniquenessFactor
  }
}

// Key Vault
module mod_keyVault './keyvault.bicep' = {
  name: 'deploy-key-vault'
  params: {
    location: location
    keyVaultName: labConfig.keyVault.name
    hostVmSubnetId: mod_vnet.outputs.subnetId.default
    secretNameForLabHostAdminPassword: labConfig.keyVault.secretName.adminPassword
    labHostAdminPassword: adminPassword
  }
}

// Key Vault RBAC
module mod_keyVaultRbac './keyvault-rbac.bicep' = {
  name: 'assign-key-vault-rbac-with-host-vm-managed-id'
  params: {
    keyVaultName: labConfig.keyVault.name
    servicePrincipalId: mod_labHostVm.outputs.principalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4633458b-17de-408a-b874-0445c86b69e6')  // Key Vault Secrets User
  }
}

// Storage account for the witness.
module mod_witnessStorageAccount './cloudwitness.bicep' = if (!isAzureLocalDeployment) {
  name: 'deploy-storage-account-witness'
  params: {
    location: location
    storageAccountNamePrefix: 'labenvwitness'
    uniqueString: uniquenessFactor
    hostVmSubnetId: mod_vnet.outputs.subnetId.default
    keyVaultName: labConfig.keyVault.name
    secretNameForStorageAccountName: labConfig.keyVault.secretName.cloudWitnessStorageAccountName
    secretNameForStorageAccountKey: labConfig.keyVault.secretName.cloudWitnessStorageAccountKey
  }
}

// Install roles and features.
module mod_installRolesFeatures './dsc.bicep' = {
  name: 'install-roles-and-features-on-host-vm'
  dependsOn: [
    mod_labHostVm
  ]
  params: {
    location: location
    parentVmResourceName: labHostVmName
    extensionName: dscExtensionName
    zipUri: uri(dscBaseUrl, 'install-roles-and-features.zip')
    scriptName: 'install-roles-and-features.ps1'
    functionName: 'install-roles-and-features'
  }
}

// Configure the lab host.
module mod_configureHostVm './customscript.bicep' = {
  name: 'configure-host-vm'
  dependsOn: [
    mod_keyVaultRbac
    mod_installRolesFeatures
  ]
  params: {
    location: location
    parentVmResourceName: labHostVmName
    extensionName: customScriptExtensionName
    fileUris: [
      uri(customScriptBaseUrl, 'configure-lab-host.ps1')
      uri(customScriptBaseUrl, 'common.psm1')
    ]
    commandToExecute: 'powershell.exe -ExecutionPolicy Unrestricted -File .\\configure-lab-host.ps1'
  }
}

// Download ISO files and updates.
module mod_downloadMaterials './customscript.bicep' = {
  name: 'download-materials'
  dependsOn: [
    mod_configureHostVm
  ]
  params: {
    location: location
    parentVmResourceName: labHostVmName
    extensionName: customScriptExtensionName
    fileUris: [
      uri(customScriptBaseUrl, 'download-materials.ps1')
      uri(customScriptBaseUrl, 'materials.json')
      uri(customScriptBaseUrl, 'common.psm1')
    ]
    commandToExecute: 'powershell.exe -ExecutionPolicy Unrestricted -File .\\download-materials.ps1'
  }
}

// Create base virtual hard disks.
module mod_createBaseVhd './customscript.bicep' = {
  name: 'create-base-vhd'
  dependsOn: [
    mod_downloadMaterials
  ]
  params: {
    location: location
    parentVmResourceName: labHostVmName
    extensionName: customScriptExtensionName
    fileUris: [
      uri(customScriptBaseUrl, 'create-base-vhd.ps1')
      uri(customScriptBaseUrl, 'create-base-vhd-job.ps1')
      uri(customScriptBaseUrl, 'common.psm1')
    ]
    commandToExecute: 'powershell.exe -ExecutionPolicy Unrestricted -File .\\create-base-vhd.ps1'
  }
}

// Reboot the lab host.
module mod_rebootHostVm './dsc.bicep' = {
  name: 'reboot-host-vm'
  dependsOn: [
    mod_createBaseVhd
  ]
  params: {
    location: location
    parentVmResourceName: labHostVmName
    extensionName: dscExtensionName
    zipUri: uri(dscBaseUrl, 'reboot.zip')
    scriptName: 'reboot.ps1'
    functionName: 'reboot'
  }
}

// Create VMs.
module mod_createVm './customscript.bicep' = {
  name: 'create-lab-vms'
  dependsOn: [
    mod_rebootHostVm
  ]
  params: {
    location: location
    parentVmResourceName: labHostVmName
    extensionName: customScriptExtensionName
    fileUris: [
      uri(customScriptBaseUrl, 'create-vm.ps1')
      uri(customScriptBaseUrl, 'create-vm-job-addsdc.ps1')
      uri(customScriptBaseUrl, 'create-vm-job-wac.ps1')
      uri(customScriptBaseUrl, 'create-vm-job-hcinode.ps1')
      uri(customScriptBaseUrl, 'common.psm1')
    ]
    commandToExecute: 'powershell.exe -ExecutionPolicy Unrestricted -File .\\create-vm.ps1'
  }
}

// Create an HCI cluster.
module mod_hciCluster './customscript.bicep' = if (labConfig.hciCluster.shouldCreateCluster) {
  name: 'create-hci-cluster'
  dependsOn: [
    mod_witnessStorageAccount
    mod_createVm
  ]
  params: {
    location: location
    parentVmResourceName: labHostVmName
    extensionName: customScriptExtensionName
    fileUris: [
      uri(customScriptBaseUrl, 'create-hci-cluster.ps1')
      uri(customScriptBaseUrl, 'create-hci-cluster-test-cat-en-us.psd1')
      uri(customScriptBaseUrl, 'create-hci-cluster-test-cat-ja-jp.psd1')
      uri(customScriptBaseUrl, 'common.psm1')
    ]
    commandToExecute: 'powershell.exe -ExecutionPolicy Unrestricted -File .\\create-hci-cluster.ps1'
  }
}

//
// Outputs
//

output adminUserName string = adminUserName
output vmPublicIpFqdn string = mod_labHostVm.outputs.fqdn
