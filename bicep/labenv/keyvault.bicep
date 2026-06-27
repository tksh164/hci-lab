@description('''The location for the Key Vault resource.''')
param location string

@description('''The Key Vault name.''')
param keyVaultName string

@description('''The subnet ID that has the host VM. This subnet ID will be set to the key vault's firewall rules as an allowed subnet.''')
param hostVmSubnetId string

@description('''The secret's name for the lab host's administrator password.''')
param secretNameForLabHostAdminPassword string

@description('''The lab host's administrator password.''')
@secure()
param labHostAdminPassword string

resource res_keyVault 'Microsoft.KeyVault/vaults@2026-02-01' = {
  name: keyVaultName
  location: location
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: tenant().tenantId
    enableSoftDelete: false
    enabledForDeployment: false
    enabledForTemplateDeployment: false
    enabledForDiskEncryption: false
    enableRbacAuthorization: true
    accessPolicies: []
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Deny'
      ipRules: []
      virtualNetworkRules: [
        {
          id: hostVmSubnetId
          ignoreMissingVnetServiceEndpoint: false
        }
      ]
    }
  }
  tags: {
    SecurityControl: 'Ignore' // Security control exemption
  }
}

// Store the lab host's admin password to the Key Vault.
resource res_labHostAdminPasswordSecret 'Microsoft.KeyVault/vaults/secrets@2026-02-01' = {
  parent: res_keyVault
  name: secretNameForLabHostAdminPassword
  properties: {
    value: labHostAdminPassword
  }
}

output keyVaultId string = res_keyVault.id
