//@description('''The location for the resources.''')
param location string

//@description('''The name of the virtual network.''')
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

resource subnetNsg 'Microsoft.Network/networkSecurityGroups@2024-07-01' = {
  name: subnetNsgName.default
  location: location
  properties: {
    securityRules: []
  }
}
