param devcenterName string
param networkConnectionName string
param networkingResourceGroupName string
param subnetId string
param projectName string
param principalId string
@secure()
param secretIdentifier string
param adeCatalogRepositoryUrl string
param adeCatalogRepositoryBranch string
param adeCatalogItemRootPath string
param location string = resourceGroup().location
param managedIdentityName string

param customizedCatalogName string
param customizedCatalogRepositoryUrl string
param customizedCatalogRepositoryBranch string
param customizedCatalogItemRootPath string
param customizationNameInDevBoxYaml string

@allowed([
  'Group'
  'ServicePrincipal'
  'User'
])
param principalType string = 'User'
param catalogName string
param devboxPoolName string

// DevCenter Dev Box User role 
var DEVCENTER_DEVBOX_USER_ROLE = '45d50f46-0b78-4001-a660-4198cbe8cd05'

// ADE Deployment Envirnment User role
var DEPLOYMENT_ENVIRONMENTS_USER_ROLE = '18e40d4e-8d2e-438d-97e1-9528336e149c'

var OWNER_ROLE = '8e3af657-a8ff-443c-a75c-2fe8c4bcb635'

var devceterSettings = loadJsonContent('./devcenter-settings.json')

resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2022-01-31-preview' existing = {
  name: managedIdentityName
}

resource devcenter 'Microsoft.DevCenter/devcenters@2023-01-01-preview' = {
  name: devcenterName
  location: location
  identity: {
    type:  'UserAssigned'
     userAssignedIdentities: {
      '${managedIdentity.id}': {}
     }
  }
}

resource networkConnection 'Microsoft.DevCenter/networkConnections@2023-01-01-preview' = {
  name: networkConnectionName
  location: location
  properties: {
    domainJoinType: 'AzureADJoin'
    subnetId: subnetId
    networkingResourceGroupName: networkingResourceGroupName
  }
}

resource attachedNetworks 'Microsoft.DevCenter/devcenters/attachednetworks@2023-01-01-preview' = {
  parent: devcenter
  name: networkConnection.name
  properties: {
    networkConnectionId: networkConnection.id
  }
}

resource project 'Microsoft.DevCenter/projects@2022-11-11-preview' = {
  name: projectName
  location: location
  properties: {
    devCenterId: devcenter.id
  }
}

resource devboxPool 'Microsoft.DevCenter/projects/pools@2023-06-01-preview' =  {
  parent: project
  name: devboxPoolName
  location: location
  properties: {
    devBoxDefinitionName: '${customizedCatalogName}\\${customizationNameInDevBoxYaml}' 
    networkConnectionName: networkConnection.name
    licenseType: 'Windows_Client'
    localAdministrator: 'Enabled'
  }
  dependsOn:[
    customizedCatalog
  ]
}

resource devboxRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = if(!empty(principalId)) {
  name: guid(subscription().id, resourceGroup().id, principalId, DEVCENTER_DEVBOX_USER_ROLE)
  scope: project
  properties: {
    principalId: principalId
    principalType: principalType
    roleDefinitionId: resourceId('Microsoft.Authorization/roleDefinitions', DEVCENTER_DEVBOX_USER_ROLE)
  }
}

// Dev Center need this managed identity with owner permission on subscription level
module assignRole 'security/role.bicep' = {
  name: 'assignOwner'
  scope: subscription()
  params: {
    principalId: managedIdentity.properties.principalId
    roleDefinitionId: OWNER_ROLE
    principalType: 'ServicePrincipal'
  }
}

resource envTypes 'Microsoft.DevCenter/devcenters/environmentTypes@2023-01-01-preview' = [for env in devceterSettings.envMapping: {
  parent: devcenter
  name: env.name
}]

resource adeCatalog 'Microsoft.DevCenter/devcenters/catalogs@2023-01-01-preview' = {
  parent: devcenter
  name: catalogName
  properties: {
     gitHub: {
       branch: adeCatalogRepositoryBranch
       path: adeCatalogItemRootPath
       secretIdentifier: secretIdentifier
       uri: adeCatalogRepositoryUrl
     }
  }
}

resource customizedCatalog 'Microsoft.DevCenter/devcenters/catalogs@2023-01-01-preview' = {
  parent: devcenter
  name: customizedCatalogName
  properties: {
     gitHub: {
       branch: customizedCatalogRepositoryBranch
       path: customizedCatalogItemRootPath
       secretIdentifier: secretIdentifier
       uri: customizedCatalogRepositoryUrl
     }
  }
}

resource projectEnvironmentTypes 'Microsoft.DevCenter/projects/environmentTypes@2023-01-01-preview' = [ for env in devceterSettings.envMapping: {
  name: env.name
  parent: project
  properties: {
    status: 'Enabled'
    creatorRoleAssignment: {
      roles: {
      '${OWNER_ROLE}': {}
      }
    }
    deploymentTargetId: !empty(env.deploymentTargetId) ? '/subscriptions/${env.deploymentTargetId}' : subscription().id
    userRoleAssignments: {
      '${managedIdentity.properties.principalId}': {
        roles: {
          '${OWNER_ROLE}': {}
        }
      }
    }
  }
  identity: {
    type:  'UserAssigned'
    userAssignedIdentities: {
      '${managedIdentity.id}': {}
    }
  }
}]

resource adeRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = if(!empty(principalId)) {
  name: guid(subscription().id, resourceGroup().id, principalId, DEPLOYMENT_ENVIRONMENTS_USER_ROLE)
  scope: project
  properties: {
    principalId: principalId
    principalType: principalType
    roleDefinitionId: resourceId('Microsoft.Authorization/roleDefinitions', DEPLOYMENT_ENVIRONMENTS_USER_ROLE)
  }
}

output devcenterName string = devcenter.name

output networkConnectionName string = networkConnection.name

output projectName string = project.name

output poolName string = devboxPool.name
