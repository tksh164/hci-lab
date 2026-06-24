@description('The location for the custom script extension resource.')
param location string

@description('The resource ID of the subnet to deploy the virtual machine.')
param subnetId string

@description('The lab host virtual machine name.')
param vmName string

@description('The administrator user name.')
param adminUserName string

@description('The administrator password. The password must have 3 of the following: 1 lower case character, 1 upper case character, 1 number, and 1 special character. And the password must be between 12 and 123 characters long.')
@secure()
param adminPassword string

@description('The lab host virtual machine size.')
param vmSize string

@description('The storage type of the lab host virtual machine\'s OS disk.')
param osDiskType string

@description('The storage type of the lab host virtual machine\'s data disk.')
param dataDiskType string

@description('The size of individual disk of the lab host virtual machine\'s data disks in GiB.')
param dataDiskSize int

@description('The number of data disks on the lab host virtual machine.')
@minValue(8)
@maxValue(32)
param dataDiskCount int

@description('By specifying True, you confirm you have an eligible Windows Server license with Software Assurance or Windows Server subscription to apply this Azure Hybrid Benefit. You can read more about compliance here: http://go.microsoft.com/fwlink/?LinkId=859786')
param hasEligibleWindowsServerLicense bool

@description('THe base64 encode user data for the lab host virtual machine.')
param base64EncodedLabConfig string

@description('By specifying True, will be auto-shutdown configured to the lab host virtual machine.')
param shouldEnabledAutoshutdown bool

@description('The auto-shutdown time.')
param autoshutdownTime string

@description('The time zone for auto-shutdown time.')
param autoshutdownTimeZone string

@description('The string for uniqueness of resource names.')
param uniqueString string

// Public IP address.
var publicIpAddressName = '${vmName}-ip1'
var dnsNameForPublicIP = toLower('${take(resourceGroup().name, 27)}-${take(vmName, 27)}-${toLower(uniqueString)}')

// Network interface.
var networkInterfaceName = '${vmName}-nic1'
var privateIPAddress = '192.168.0.4'

// Virtual machine.
var computerName = 'labenv'

// Public IP address.
resource publicIpAddress 'Microsoft.Network/publicIpAddresses@2024-07-01' = {
  name: publicIpAddressName
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
    dnsSettings: {
      domainNameLabel: dnsNameForPublicIP
    }
  }
}

// Network interface.
resource networkInterface 'Microsoft.Network/networkInterfaces@2024-07-01' = {
  name: networkInterfaceName
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          subnet: {
            id: subnetId
          }
          privateIPAllocationMethod: 'Static'
          privateIPAddress: privateIPAddress
          publicIPAddress: {
            id: publicIpAddress.id
          }
        }
      }
    ]
    enableAcceleratedNetworking: true
  }
}

// Virtual machine.
resource virtualMachine 'Microsoft.Compute/virtualMachines@2024-11-01' = {
  name: vmName
  location: location
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    osProfile: {
      computerName: computerName
      adminUsername: adminUserName
      adminPassword: adminPassword
      windowsConfiguration: {
        provisionVMAgent: true
        enableAutomaticUpdates: true
        patchSettings: {
          enableHotpatching: true
          patchMode: 'AutomaticByPlatform'
          automaticByPlatformSettings: {
            rebootSetting: 'Never'
          }
          assessmentMode: 'ImageDefault'
        }
      }
    }
    licenseType: hasEligibleWindowsServerLicense ? 'Windows_Server' : 'None'
    networkProfile: {
      networkInterfaces: [
        {
          id: networkInterface.id
        }
      ]
    }
    storageProfile: {
      osDisk: {
        name: '${vmName}-osdisk'
        managedDisk: {
          storageAccountType: osDiskType
        }
        createOption: 'FromImage'
        caching: 'ReadWrite'
        deleteOption: 'Delete'
      }
      imageReference: {
        publisher: 'MicrosoftWindowsServer'
        offer: 'WindowsServer'
        sku: '2025-datacenter-azure-edition-smalldisk'
        version: 'latest'
      }
      dataDisks: [
        for i in range(0, dataDiskCount): {
          name: format('{0}-datadisk{1:00}', vmName, i)
          lun: i
          managedDisk: {
            storageAccountType: dataDiskType
          }
          diskSizeGB: dataDiskSize
          createOption: 'Empty'
          caching: 'ReadWrite'
          deleteOption: 'Delete'
        }
      ]
    }
    diagnosticsProfile: {
      bootDiagnostics: {
        enabled: true
      }
    }
    userData: base64EncodedLabConfig
  }
  identity: {
    type: 'SystemAssigned'
  }
}

// Auto-shutdown schedule.
resource autoshutdownSchedule 'Microsoft.DevTestLab/schedules@2018-09-15' = if (shouldEnabledAutoshutdown) {
  name: 'shutdown-computevm-${vmName}'
  location: location
  properties: {
    status: shouldEnabledAutoshutdown ? 'Enabled' : 'Disabled'
    taskType: 'ComputeVmShutdownTask'
    dailyRecurrence: {
      time: autoshutdownTime
    }
    timeZoneId: autoshutdownTimeZone
    targetResourceId: virtualMachine.id
  }
}

output fqdn string = publicIpAddress.properties.dnsSettings.fqdn
output principalId string = virtualMachine.identity.principalId
