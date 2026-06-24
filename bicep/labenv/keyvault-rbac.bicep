@description('The Key Vault resource name.')
param keyVaultName string

@description('The service principal ID for the role assignment.')
param servicePrincipalId string

@description('The role definition ID for the role assignment.')
param roleDefinitionId string

resource keyVault 'Microsoft.KeyVault/vaults@2026-02-01' existing = {
  name: keyVaultName
}

resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(servicePrincipalId)
  scope: keyVault
  properties: {
    roleDefinitionId: roleDefinitionId
    principalType: 'ServicePrincipal'
    principalId: servicePrincipalId
  }
}
