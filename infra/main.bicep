@description('Primary location for all resources e.g. eastus')
param location string = resourceGroup().location

@description('The name of Dev Center e.g. dc-devbox-test')
param devcenterName string = ''

@description('The name of Dev Center project e.g. dcprj-devbox-test')
param projectName string = ''

@description('The name of Network Connection e.g. con-devbox-test')
param networkConnectionName string = ''

@description('The name of Dev Center user identity')
param userIdentityName string = ''

@description('The subnet resource id if the user wants to use existing subnet')
param existingSubnetId string = ''

@description('The name of the Virtual Network e.g. vnet-dcprj-devbox-test-eastus')
param networkVnetName string = ''

@description('the subnet name of Dev Box e.g. default')
param networkSubnetName string = 'default'

@description('The vnet address prefixes of Dev Box e.g. 10.4.0.0/16')
param networkVnetAddressPrefixes string = '10.4.0.0/16'

@description('The subnet address prefixes of Dev Box e.g. 10.4.0.0/24')
param networkSubnetAddressPrefixes string = '10.4.0.0/24'

@description('The user or group id that will be granted to Devcenter Dev Box User and Deployment Environments User role')
param userPrincipalId string = ''

@description('The type of principal id: User or Group')
@allowed([
  'Group'
  'User'
])
param userPrincipalType string = 'User'

@description('The name of Azure Compute Gallery')
param imageGalleryName string = ''

@description('The name of Azure Compute Gallery image definition')
param imageDefinitionName string = 'OpenAIImage'

@description('The name of image template for customized image')
param imageTemplateName string = 'OpenAIImageTemplate'

@description('The name of image offer')
param imageOffer string = 'visualstudioplustools'

@description('The name of image publisher')
param imagePublisher string = 'microsoftvisualstudio'

@description('The name of image sku')
param imageSku string = 'vs-2022-ent-general-win11-m365-gen2'

param adeKeyvaultName string = ''
param adeKeyvaultSecretName string = 'repo-pat-secret'

@description('The personal access token of Github/ADO repo')
@secure()
param adeKeyvaultSecretValue string

@description('The catalog repository URL of ADE templates')
param adeCatalogRepositoryUrl string = 'https://github.com/luxu-ms/deployment-environments.git'

@description('The root path of catalog repository including ADE templates')
param adeCatalogItemRootPath string = '/Environments'

param tags object = {}
param guidId string = newGuid()

var abbrs = loadJsonContent('./abbreviations.json')
var resourceToken = toLower(uniqueString(resourceGroup().id, location))
var ncName = !empty(networkConnectionName) ? networkConnectionName : '${abbrs.networkConnections}${resourceToken}'
var kvName = !empty(adeKeyvaultName) ? adeKeyvaultName : '${abbrs.keyvault}${resourceToken}'
var galName = !empty(imageGalleryName) ? imageGalleryName : '${abbrs.computeGalleries}${resourceToken}'
var idName = !empty(userIdentityName) ? userIdentityName : '${abbrs.managedIdentityUserAssignedIdentities}${resourceToken}'

module vnet 'core/vnet.bicep' = if(empty(existingSubnetId)) {
  name: 'vnet'
  params: {
    location: location
    tags: tags
    vnetAddressPrefixes: networkVnetAddressPrefixes
    vnetName: !empty(networkVnetName) ? networkVnetName : '${abbrs.networkVirtualNetworks}${resourceToken}'
    subnetAddressPrefixes: networkSubnetAddressPrefixes
    subnetName: !empty(networkSubnetName) ? networkSubnetName : '${abbrs.networkVirtualNetworksSubnets}${resourceToken}'
  }
}

module keyvault 'core/security/keyvault.bicep' = {
  name: kvName
  params: {
    location: location
    name: kvName
    principalId: userPrincipalId
    tags: tags
  }
}

module keyvaultSecret 'core/security/keyvault-secret.bicep' = {
  name: 'keyvaultSecret'
  params: {
    keyVaultName: keyvault.outputs.name
    name: adeKeyvaultSecretName
    secretValue: adeKeyvaultSecretValue
  }
}

resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2022-01-31-preview' = {
  name: idName
  location: location
  tags: tags
}

module keyvaultAccess 'core/security/keyvault-access.bicep' = {
  name: 'keyvaultAccess'
  params: {
    keyVaultName: keyvault.outputs.name
    principalId: managedIdentity.properties.principalId
  }
}

module gallery 'core/gallery.bicep' = {
  name: galName
  params: {
    galleryName: galName
    location: location
    tags: tags
    imageDefinitionName: imageDefinitionName
    imageOffer: imageOffer
    imagePublisher: imagePublisher
    imageSku: imageSku
    imageTemplateName: imageTemplateName
    templateIdentityName: '${abbrs.managedIdentityUserAssignedIdentities}tpl-${resourceToken}'
    guidId: guidId
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
    principalId: userPrincipalId
    principalType: userPrincipalType
    repositoryUrl: adeCatalogRepositoryUrl
    secretIdentifier: keyvaultSecret.outputs.secretIdentifier
    galleryName: gallery.outputs.name
    managedIdentityName: idName
    catalogItemRootPath: adeCatalogItemRootPath
    imageDefinitionName: imageDefinitionName
    imageTemplateName: imageTemplateName
    guidId: guidId
  }
}

output devcetnerName string = devcenter.outputs.devcenterName
output projectName string = devcenter.outputs.projectName
output networkConnectionName string = devcenter.outputs.networkConnectionName
output vnetName string = empty(existingSubnetId) ? vnet.outputs.vnetName : ''
output subnetName string = empty(existingSubnetId) ? vnet.outputs.subnetName : ''
output builtinImageDevboxDefinitions array = devcenter.outputs.builtinImageDevboxDefinitions
output customizedImageDevboxDefinitions string = devcenter.outputs.customizedImageDevboxDefinitions
output pools array = devcenter.outputs.poolNames
