@description('''The location for the storage account resource.''')
param location string

@description('''The prefix of the storage account name for Cloud Witness.''')
param storageAccountNamePrefix string

@description('''The string for uniqueness of the storage account name.''')
param uniqueString string

@description('''The subnet ID that has the host VM. This subnet ID will be set to the storage account's firewall rules as an allowed subnet.''')
param hostVmSubnetId string

@description('''The Key Vault name to store the storage account key.''')
param keyVaultName string

@description('''The secret's name of the storage account name in the Key Vault.''')
param secretNameForStorageAccountName string

@description('''The secret's name of the storage account key in the Key Vault.''')
param secretNameForStorageAccountKey string

var storageAccountName = '${toLower(storageAccountNamePrefix)}${toLower(uniqueString)}'

// Storage account for Cloud Witness.
resource res_storageAccount 'Microsoft.Storage/storageAccounts@2022-09-01' = {
  name: storageAccountName
  location: location
  kind: 'StorageV2'
  sku: {
    name: 'Standard_LRS'
  }
  properties: {
    accessTier: 'Hot'
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    allowSharedKeyAccess: true
    allowCrossTenantReplication: true
    defaultToOAuthAuthentication: false
    allowBlobPublicAccess: false
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Deny'
      ipRules: []
      virtualNetworkRules: [
        {
          id: hostVmSubnetId
          action: 'Allow'
        }
      ]
    }
    dnsEndpointType: 'Standard'
    encryption: {
      keySource: 'Microsoft.Storage'
      services: {
        blob: {
          enabled: true
        }
        file: {
          enabled: true
        }
        table: {
          enabled: true
        }
        queue: {
          enabled: true
        }
      }
      requireInfrastructureEncryption: false
    }
  }
  tags: {
    SecurityControl: 'Ignore' // Security control exemption
  }
}

resource res_blobService 'Microsoft.Storage/storageAccounts/blobServices@2022-09-01' = {
  parent: res_storageAccount
  name: 'default'
  properties: {
    restorePolicy: {
      enabled: false
    }
    deleteRetentionPolicy: {
      enabled: false
    }
    containerDeleteRetentionPolicy: {
      enabled: false
    }
    changeFeed: {
      enabled: false
    }
    isVersioningEnabled: false
  }
}

resource res_fileService 'Microsoft.Storage/storageAccounts/fileServices@2022-09-01' = {
  parent: res_storageAccount
  name: 'default'
  properties: {
    shareDeleteRetentionPolicy: {
      enabled: false
    }
  }
}

resource res_keyVault 'Microsoft.KeyVault/vaults@2022-11-01' existing = {
  name: keyVaultName
}

// Store the storage account name and key to the Key Vault.
resource res_storageAccountNameSecret 'Microsoft.KeyVault/vaults/secrets@2022-11-01' = {
  parent: res_keyVault
  name: secretNameForStorageAccountName
  properties: {
    value: storageAccountName
  }
}

resource res_storageAccountKeySecret 'Microsoft.KeyVault/vaults/secrets@2022-11-01' = {
  parent: res_keyVault
  name: secretNameForStorageAccountKey
  properties: {
    value: res_storageAccount.listKeys('2022-09-01').keys[0].value
  }
}

output storageAccountId string = res_storageAccount.id
output storageAccountName string = storageAccountName
