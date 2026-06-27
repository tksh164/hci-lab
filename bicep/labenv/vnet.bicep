@description('''The location for the resources.''')
param location string

@description('''The name of the virtual network.''')
param virtualNetworkName string

// Virtual network.
var virtualNetworkNameAddressPrefix string = '192.168.0.0/16'

// Default subnet.
var defaultSubnet object = {
  name: 'default'
  addressPrefix: '192.168.0.0/24'
}

// Network security group names.
var subnetNsgName object = {
  default: format('{0}-{1}-nsg', virtualNetworkName, toLower(defaultSubnet.name))
}

// Network security group for the default subnet.
resource res_subnetNsg 'Microsoft.Network/networkSecurityGroups@2024-07-01' = {
  name: subnetNsgName.default
  location: location
  properties: {
    securityRules: []
  }
}

// Virtual network.
resource res_vnet 'Microsoft.Network/virtualNetworks@2024-07-01' = {
  name: virtualNetworkName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        virtualNetworkNameAddressPrefix
      ]
    }
    subnets: [
      {
        name: defaultSubnet.name
        properties: {
          addressPrefix: defaultSubnet.addressPrefix
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
    ]
  }
}

output virtualNetworkId string = res_vnet.id
output subnetId object = {
  default: resourceId('Microsoft.Network/virtualNetworks/subnets', virtualNetworkName, defaultSubnet.name)
}
