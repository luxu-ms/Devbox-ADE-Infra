@description('The name of Dev Center e.g. dc-devbox-test')
param devcenterName string = ''

@description('The name of Network Connection e.g. con-devbox-test')
param networkConnectionName string = ''

@description('The name of Dev Center project e.g. dcprj-devbox-test')
param projectName string = ''

@description('The subnet resource id if the user wants to use existing subnet')
param existingSubnetId string = ''

@description('Primary location for all resources e.g. eastus')
param location string = resourceGroup().location

@description('The name of the Virtual Network e.g. vnet-dcprj-devbox-test-eastus')
param vnetName string = 'vnet-${projectName}-${location}'

@description('the subnet name of Dev Box e.g. default')
param subnetName string = 'default'

@description('The vnet address prefixes of Dev Box e.g. 10.4.0.0/16')
param vnetAddressPrefixes string = '10.4.0.0/16'

@description('The subnet address prefixes of Dev Box e.g. 10.4.0.0/24')
param subnetAddressPrefixes string = '10.4.0.0/24'

@description('The user or group id that will be granted to Devcenter Dev Box User role')
param principalId string = ''

@description('The type of principal id: User, Group or ServicePrincipal')
param principalType string = 'User'

param keyvaultName string = ''
param keyvaultSecretName string = 'repo-pat-secret'

@description('The personal access token of Github/ADO repo')
@secure()
param keyvaultSecretValue string

param galleryName string = ''
param imageDefinitionName string = 'OpenAIImage'
param imageOffer string = 'windows-ent-cpc'
param imagePublisher string = 'microsoftwindowsdesktop'
param imageSku string = 'win11-22h2-ent-cpc-m365-test'

param catalogItemRootPath string = '/Environments'
param managedIdentityName string = ''

param repositoryUrl string = 'https://github.com/luxu-ms/azure-search-openai-demo.git'

param tags object = {}

var abbrs = loadJsonContent('./abbreviations.json')
var resourceToken = toLower(uniqueString(resourceGroup().id, location))
var ncName = !empty(networkConnectionName) ? networkConnectionName : '${abbrs.networkConnections}${resourceToken}'
var kvName = !empty(keyvaultName) ? keyvaultName : '${abbrs.keyvault}${resourceToken}'

module vnet 'core/vnet.bicep' = if(empty(existingSubnetId)) {
  name: 'vnet'
  params: {
    location: location
    tags: tags
    vnetAddressPrefixes: vnetAddressPrefixes
    vnetName: !empty(vnetName) ? vnetName : '${abbrs.networkVirtualNetworks}${resourceToken}'
    subnetAddressPrefixes: subnetAddressPrefixes
    subnetName: !empty(subnetName) ? subnetName : '${abbrs.networkVirtualNetworksSubnets}${resourceToken}'
  }
}

module keyvault 'core/security/keyvault.bicep' = {
  name: kvName
  params: {
    location: location
    name: kvName
    principalId: principalId
    tags: tags
  }
}

module keyvaultSecret 'core/security/keyvault-secret.bicep' = {
  name: 'keyvaultSecret'
  params: {
    keyVaultName: keyvault.name
    name: keyvaultSecretName
    secretValue: keyvaultSecretValue
  }
}

module devcenter 'core/devcenter.bicep' = {
  name: 'devcenter'
  params: {
    location: location
    tags: tags
    devcenterName: !empty(devcenterName) ? devcenterName : '${abbrs.devcenter}${resourceToken}'
    subnetId: !empty(existingSubnetId) ? existingSubnetId : vnet.outputs.subnetId
    networkConnectionName: ncName
    projectName: !empty(projectName) ? projectName : '${abbrs.devcenterProject}${resourceToken}'
    networkingResourceGroupName: '${abbrs.devcenterNetworkingResourceGroup}${ncName}-${location}'
    principalId: principalId
    principalType: principalType
    repositoryUrl: repositoryUrl
    secretIdentifier: keyvaultSecret.outputs.secretIdentifier
    galleryName: !empty(galleryName) ? galleryName : '${abbrs.computeGalleries}${resourceToken}'
    imageDefinitionName: imageDefinitionName
    imageOffer: imageOffer
    imagePublisher: imagePublisher
    imageSku: imageSku
    managedIdentityName: !empty(managedIdentityName) ? managedIdentityName : '${abbrs.managedIdentityUserAssignedIdentities}${resourceToken}'
    catalogItemRootPath: catalogItemRootPath
    keyvaultName: keyvault.outputs.name
  }
}

output vnetName string = empty(existingSubnetId) ? vnet.outputs.vnetName : ''
output subnetName string = empty(existingSubnetId) ? vnet.outputs.subnetName : ''

output devcetnerName string = devcenter.outputs.devcenterName
output projectName string = devcenter.outputs.projectName
output networkConnectionName string = devcenter.outputs.networkConnectionName
output definitions array = devcenter.outputs.definitions
output pools array = devcenter.outputs.poolNames
