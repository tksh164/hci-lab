//
// Parameters
//

@description('''The location for the DSC extension resource.''')
param location string

@description('''The name of the parent virtual machine resource.''')
param parentVmResourceName string

@description('''The name of the DSC extension resource.''')
param extensionName string

@description('''The URI of the DSC zip package file.''')
param zipUri string

@description('''The DSC configuration script file name.''')
param scriptName string

@description('''The DSC configuration name.''')
param functionName string

//
// Resources
//

resource res_parentVm 'Microsoft.Compute/virtualMachines@2025-11-01' existing = {
  name: parentVmResourceName
}

resource res_dscExtension 'Microsoft.Compute/virtualMachines/extensions@2025-11-01' = {
  parent: res_parentVm
  name: extensionName
  location: location
  properties: {
    publisher: 'Microsoft.Powershell'
    type: 'DSC'
    typeHandlerVersion: '2.83'
    autoUpgradeMinorVersion: true
    suppressFailures: false
    settings: {
      wmfVersion: 'latest'
      configuration: {
        url: zipUri
        script: scriptName
        function: functionName
      }
      configurationArguments: {}
    }
    protectedSettings: {}
  }
}

//
// Outputs
//

output instanceView object = res_dscExtension.properties.instanceView
