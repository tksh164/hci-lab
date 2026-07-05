//
// Parameters
//

@description('''The location for the custom script extension resource.''')
param location string

@description('''The name of the parent virtual machine resource.''')
param parentVmResourceName string

@description('''The name of the custom script extension resource.''')
param extensionName string

@description('''The URI of custom scripts.''')
@minLength(1)
param fileUris array

@description('''The command-line to execute the custom script.''')
param commandToExecute string

//
// Resources
//

resource parentVm 'Microsoft.Compute/virtualMachines@2025-11-01' existing = {
  name: parentVmResourceName
}

resource res_customScriptExtension 'Microsoft.Compute/virtualMachines/extensions@2025-11-01' = {
  parent: parentVm
  name: extensionName
  location: location
  properties: {
    publisher: 'Microsoft.Compute'
    type: 'CustomScriptExtension'
    typeHandlerVersion: '1.10'
    autoUpgradeMinorVersion: true
    suppressFailures: false
    settings: {}
    protectedSettings: {
      fileUris: fileUris
      commandToExecute: commandToExecute
    }
  }
}

//
// Outputs
//

output instanceView object = res_customScriptExtension.properties.instanceView
