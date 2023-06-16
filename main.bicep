
var vnetAddressPrefixes = '10.4.0.0/16'
var subnetAddressPrefixes = '10.4.0.0/24'

@description('The user or group id that will be granted to Devcenter Dev Box User role')
param principalId string = ''

@description('The type of principal id: User, Group or ServicePrincipal')
param principalType string = 'User'

@description('Primary location for all resources e.g. eastus')
param location string = resourceGroup().location

var abbrs = loadJsonContent('./abbreviations.json')
var resourceToken = toLower(uniqueString(resourceGroup().id, location))
var ncName = '${abbrs.networkConnections}${resourceToken}'

module vnet 'core/vnet.bicep' = {
  name: 'vnet'
  params: {
    location: location
    vnetAddressPrefixes: vnetAddressPrefixes
    vnetName: '${abbrs.networkVirtualNetworks}${resourceToken}'
    subnetAddressPrefixes: subnetAddressPrefixes
    subnetName: '${abbrs.networkVirtualNetworksSubnets}${resourceToken}'
  }
}

module devcenter 'core/devcenter.bicep' = {
  name: 'devcenter'
  params: {
    location: location
    devcenterName: '${abbrs.devcenter}${resourceToken}'
    subnetId: vnet.outputs.subnetId
    networkConnectionName: ncName
    projectName: '${abbrs.devcenterProject}${resourceToken}'
    networkingResourceGroupName: '${abbrs.devcenterNetworkingResourceGroup}${ncName}-${location}'
    principalId: principalId
    principalType: principalType
  }
}

output vnetName string = vnet.outputs.vnetName
output subnetName string = vnet.outputs.subnetName
output devcetnerName string = devcenter.outputs.devcenterName
output projectName string = devcenter.outputs.projectName
output networkConnectionName string = devcenter.outputs.networkConnectionName
output definitions array = devcenter.outputs.definitions
output pools array = devcenter.outputs.poolNames
