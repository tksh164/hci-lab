//
// Parameters
//

@description('''The location for the resources.''')
param location string

@description('''The name of the virtual network.''')
param virtualNetworkName string

//
// Variables
//

var subnetName = 'default'

//
// Resources
//

// Network security group for the default subnet.
resource res_subnetNsg 'Microsoft.Network/networkSecurityGroups@2025-07-01' = {
  name: format('{0}-{1}-nsg', virtualNetworkName, toLower(subnetName))
  location: location
  properties: {
    securityRules: []
  }
}

// Virtual network.
resource res_vnet 'Microsoft.Network/virtualNetworks@2025-07-01' = {
  name: virtualNetworkName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        '192.168.0.0/16'
      ]
    }
  }
}

// Subnet
resource res_subnet 'Microsoft.Network/virtualNetworks/subnets@2025-07-01' = {
  parent: res_vnet
  name: subnetName
  properties: {
    addressPrefix: '192.168.0.0/24'
    networkSecurityGroup: {
      id: res_subnetNsg.id
    }
    serviceEndpoints: [
      {
        service: 'Microsoft.KeyVault'
        locations: [
          '*'
        ]
      }
      {
        service: 'Microsoft.Storage'
        locations: [
          '*'
        ]
      }
    ]
  }
}

//
// Outputs
//

output virtualNetworkId string = res_vnet.id
output subnetId string = res_subnet.id
