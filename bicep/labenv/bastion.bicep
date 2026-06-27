@description('''The location for the custom script extension resource.''')
param location string

@description('''The name of the Bastion.''')
param bastionName string

@description('''The resource ID of the virtual network.''')
param virtualNetworkId string

resource res_bastionHost 'Microsoft.Network/bastionHosts@2024-07-01' = {
  name: bastionName
  location: location
  sku: {
    name: 'Developer'
  }
  properties: {
    virtualNetwork: {
      id: virtualNetworkId
    }
  }
}
