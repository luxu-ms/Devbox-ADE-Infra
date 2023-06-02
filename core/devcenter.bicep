param devcenterName string
param networkConnectionName string
param networkingResourceGroupName string
param subnetId string
param projectName string
param principalId string
param secretIdentifier string
param repositoryUrl string
param repositoryBranch string = 'main'
param catalogItemRootPath string
param location string = resourceGroup().location
param managedIdentityName string
param keyvaultName string
param galleryName string
param imageDefinitionName string
param imageOffer string
param imagePublisher string
param imageSku string
param tags object = {}

@allowed([
  'Group'
  'ServicePrincipal'
  'User'
])
param principalType string = 'User'

param catalogName string = 'test-catalog'

// DevCenter Dev Box User role definition id
var devboxRoleDefinitionId = '45d50f46-0b78-4001-a660-4198cbe8cd05'
var adeRoledefinitioinId = '18e40d4e-8d2e-438d-97e1-9528336e149c'
var ownerRoleDefinitioinId = '8e3af657-a8ff-443c-a75c-2fe8c4bcb635'

var devceterSettings = loadJsonContent('./devcenter-settings.json')

var image = {
  'win11-ent-base': 'microsoftwindowsdesktop_windows-ent-cpc_win11-21h2-ent-cpc-os'
  'win11-ent-m365': 'microsoftwindowsdesktop_windows-ent-cpc_win11-21h2-ent-cpc-m365'
  'win11-ent-vs2022': 'microsoftvisualstudio_visualstudioplustools_vs-2022-ent-general-win11-m365-gen2'
}

var compute = {
  '8-vcpu-32gb-mem': 'general_a_8c32gb_v1'
}

var storage = {
  '256gb': 'ssd_256gb'
  '512gb': 'ssd_512gb'
  '1024gb': 'ssd_1024gb'
}

resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2022-01-31-preview' = {
  name: managedIdentityName
  location: location
  tags: tags
}

module keyvaultAccess 'security/keyvault-access.bicep' = {
  name: 'keyvaultAccess'
  params: {
    keyVaultName: keyvaultName
    principalId: managedIdentity.properties.principalId
  }
}

resource computeGallery 'Microsoft.Compute/galleries@2022-03-03' = {
  name: galleryName
  location: location
  tags: tags
}

resource imageDefinition 'Microsoft.Compute/galleries/images@2022-03-03' = {
  parent: computeGallery
  name: imageDefinitionName
  location: location
  properties: {
    hyperVGeneration: 'V2'
    architecture: 'x64'
    features: [
      {
          name: 'SecurityType'
          value: 'TrustedLaunch'
      }
    ]
    identifier: {
      offer: imageOffer
      publisher: imagePublisher
      sku: imageSku
    }
    osState: 'Generalized'
    osType: 'Windows'
  }
}

resource devcenter 'Microsoft.DevCenter/devcenters@2023-01-01-preview' = {
  name: devcenterName
  location: location
  tags: tags
  identity: {
    type:  'UserAssigned'
     userAssignedIdentities: {
      '${managedIdentity.id}': {}
     }
  }
}

module assignRole 'security/role.bicep' = {
  name: 'assignOwner'
  params: {
    principalId: managedIdentity.properties.principalId
    roleDefinitionId: ownerRoleDefinitioinId
  }
}

resource envTypes 'Microsoft.DevCenter/devcenters/environmentTypes@2023-01-01-preview' = [for env in devceterSettings.envMapping: {
  parent: devcenter
  name: env.name
}]

resource catalogs 'Microsoft.DevCenter/devcenters/catalogs@2023-01-01-preview' = {
  parent: devcenter
  name: catalogName
  properties: {
     gitHub: {
       branch: repositoryBranch
       path: catalogItemRootPath
       secretIdentifier: secretIdentifier
       uri: repositoryUrl
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
  tags: tags
}

resource attachedNetworks 'Microsoft.DevCenter/devcenters/attachednetworks@2023-01-01-preview' = {
  parent: devcenter
  name: networkConnection.name
  properties: {
    networkConnectionId: networkConnection.id
  }
}

resource devboxDefinitions 'Microsoft.DevCenter/devcenters/devboxdefinitions@2022-11-11-preview' = [for definition in devceterSettings.definitions: {
  parent: devcenter
  name: definition.name
  location: location
  properties: {
    imageReference: {
      id: '${devcenter.id}/galleries/default/images/${image[definition.image]}'
    }
    sku: {
      name: compute[definition.compute]
    }
    osStorageType: storage[definition.storage]
  }
  dependsOn: [
    attachedNetworks
  ]
}]

resource project 'Microsoft.DevCenter/projects@2022-11-11-preview' = {
  name: projectName
  location: location
  properties: {
    devCenterId: devcenter.id
  }
  resource pools 'pools' = [for pool in devceterSettings.pools: {
    name: pool.name
    location: location
    properties: {
      devBoxDefinitionName: pool.definition
      networkConnectionName: networkConnection.name
      licenseType: 'Windows_Client'
      localAdministrator: pool.administrator
      
    }
  }]
  dependsOn: [
    devboxDefinitions
  ]
  tags: tags
}

resource projectEnvironmentTypes 'Microsoft.DevCenter/projects/environmentTypes@2023-01-01-preview' = [ for env in devceterSettings.envMapping: {
  name: env.name
  parent: project
  properties: {
    status: 'Enabled'
    creatorRoleAssignment: {
      roles: {
      '${ownerRoleDefinitioinId}': {}
      }
    }
    deploymentTargetId: !empty(env.deploymentTargetId) ? '/subscriptions/${env.deploymentTargetId}' : subscription().id
    userRoleAssignments: {
      '${managedIdentity.properties.principalId}': {
        roles: {
          '${ownerRoleDefinitioinId}': {}
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

resource devboxRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = if(!empty(principalId)) {
  name: guid(subscription().id, resourceGroup().id, principalId, devboxRoleDefinitionId)
  scope: project
  properties: {
    principalId: principalId
    principalType: principalType
    roleDefinitionId: resourceId('Microsoft.Authorization/roleDefinitions', devboxRoleDefinitionId)
  }
}

resource adeRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = if(!empty(principalId)) {
  name: guid(subscription().id, resourceGroup().id, principalId, adeRoledefinitioinId)
  scope: project
  properties: {
    principalId: principalId
    principalType: principalType
    roleDefinitionId: resourceId('Microsoft.Authorization/roleDefinitions', adeRoledefinitioinId)
  }
}

output devcenterName string = devcenter.name

output definitions array = [for (definition, i) in devceterSettings.definitions: {
  name: devboxDefinitions[i].name
}]

output networkConnectionName string = networkConnection.name

output projectName string = project.name

output poolNames array = [for (pool, i) in devceterSettings.pools: {
  name: project::pools[i].name
}]
