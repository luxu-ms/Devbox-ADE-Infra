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

@description('The name of Dev Box pool')
param devboxPoolName string = 'customization-pool'

@description('The name of ADE key vault')
param adeKeyvaultName string = ''

@description('The name of ADE key vault secret for catalog to access the repo')
param adeKeyvaultSecretName string = 'repo-pat-secret'

@description('The personal access token of Github/ADO repo')
@secure()
param adeKeyvaultSecretValue string

@description('The name of catalog')
param adeCatalogName string = 'test-catalog'

@description('The catalog repository URL of ADE templates')
param adeCatalogRepositoryUrl string = 'https://github.com/luxu-ms/deployment-environments.git'

@description('The catalog repository branch of ADE templates')
param adeCatalogRepositoryBranch string = 'main'

@description('The root path of catalog repository including ADE templates')
param adeCatalogItemRootPath string = '/Environments'

@description('The name of catalog')
param customizedCatalogName string = 'customization-catalog'

@description('The catalog repository URL of ADE templates')
param customizedCatalogRepositoryUrl string = 'https://github.com/luxu-ms/devbox-customization-openai.git'

@description('The catalog repository branch of ADE templates')
param customizedCatalogRepositoryBranch string = 'main'

@description('The root path of catalog repository including ADE templates')
param customizedCatalogItemRootPath string = ''

param customizationNameInDevBoxYaml string = 'devbox-customization'

@description('Primary location for all resources e.g. eastus')
param location string = resourceGroup().location

var abbrs = loadJsonContent('./abbreviations.json')
var resourceToken = toLower(uniqueString(resourceGroup().id, location))
var ncName = !empty(networkConnectionName) ? networkConnectionName : '${abbrs.networkConnections}${resourceToken}'
var kvName = !empty(adeKeyvaultName) ? adeKeyvaultName : '${abbrs.keyvault}${resourceToken}'
var idName = !empty(userIdentityName) ? userIdentityName : '${abbrs.managedIdentityUserAssignedIdentities}${resourceToken}'
var dcName = !empty(devcenterName) ? devcenterName : '${abbrs.devcenter}${resourceToken}'
var prjName = !empty(projectName) ? projectName : '${abbrs.devcenterProject}${resourceToken}'

module vnet 'core/vnet.bicep' = if(empty(existingSubnetId)) {
  name: 'vnet'
  params: {
    location: location
    vnetAddressPrefixes: networkVnetAddressPrefixes
    vnetName: !empty(networkVnetName) ? networkVnetName : '${abbrs.networkVirtualNetworks}${resourceToken}'
    subnetAddressPrefixes: networkSubnetAddressPrefixes
    subnetName: !empty(networkSubnetName) ? networkSubnetName : '${abbrs.networkVirtualNetworksSubnets}${resourceToken}'
  }
}

resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2022-01-31-preview' = {
  name: idName
  location: location
}


module devcenter 'core/devcenter.bicep' = {
  name: dcName
  params: {
    location: location
    devcenterName: dcName
    subnetId: !empty(existingSubnetId) ? existingSubnetId : vnet.outputs.subnetId
    networkConnectionName: ncName
    projectName: prjName
    networkingResourceGroupName: '${abbrs.devcenterNetworkingResourceGroup}${ncName}-${location}'
    principalId: userPrincipalId
    principalType: userPrincipalType
    secretIdentifier: keyvaultSecret.outputs.secretIdentifier
    managedIdentityName: idName
    devboxPoolName: devboxPoolName
    catalogName: adeCatalogName
    adeCatalogRepositoryUrl: adeCatalogRepositoryUrl
    adeCatalogItemRootPath: adeCatalogItemRootPath
    adeCatalogRepositoryBranch: adeCatalogRepositoryBranch
    customizedCatalogItemRootPath:customizedCatalogItemRootPath
    customizedCatalogName: customizedCatalogName
    customizedCatalogRepositoryBranch:customizedCatalogRepositoryBranch
    customizedCatalogRepositoryUrl: customizedCatalogRepositoryUrl
    customizationNameInDevBoxYaml: customizationNameInDevBoxYaml
  }
}

module keyvault 'core/security/keyvault.bicep' = {
  name: kvName
  params: {
    location: location
    name: kvName
    principalId: userPrincipalId
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

module keyvaultAccess 'core/security/keyvault-access.bicep' = {
  name: 'keyvaultAccess'
  params: {
    keyVaultName: keyvault.outputs.name
    principalId: managedIdentity.properties.principalId
  }
}

output devcetnerName string = devcenter.outputs.devcenterName
output projectName string = devcenter.outputs.projectName
output networkConnectionName string = devcenter.outputs.networkConnectionName
output vnetName string = empty(existingSubnetId) ? vnet.outputs.vnetName : ''
output subnetName string = empty(existingSubnetId) ? vnet.outputs.subnetName : ''
output poolName string = devcenter.outputs.poolName
