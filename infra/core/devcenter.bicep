param devcenterName string
param networkConnectionName string
param networkingResourceGroupName string
param subnetId string
param projectName string
param principalId string
param secretIdentifier string
param adeCatalogRepositoryUrl string
param adeCatalogRepositoryBranch string
param adeCatalogItemRootPath string
param location string = resourceGroup().location
param managedIdentityName string
param galleryName string
param imageDefinitionName string
param imageTemplateName string

@allowed([
  'Group'
  'ServicePrincipal'
  'User'
])
param principalType string = 'User'
param catalogName string
param devboxDefnitionName string
param devboxPoolName string
param devboxStorageSize string

param guidId string

// DevCenter Dev Box User role 
var DEVCENTER_DEVBOX_USER_ROLE = '45d50f46-0b78-4001-a660-4198cbe8cd05'

// ADE Deployment Envirnment User role
var DEPLOYMENT_ENVIRONMENTS_USER_ROLE = '18e40d4e-8d2e-438d-97e1-9528336e149c'

var OWNER_ROLE = '8e3af657-a8ff-443c-a75c-2fe8c4bcb635'
var CONTRIBUTOR_ROLE = 'b24988ac-6180-42a0-ab88-20f7382dd24c'
var READER_ROLE = 'acdd72a7-3385-48ef-bd42-f606fba81ae7'
// Used when Dev Center associate with Azure Compute Gallery
var WINDOWS365_PRINCIPALID = '8eec7c09-06ae-48e9-aafd-9fb31a5d5175'

var devceterSettings = loadJsonContent('./devcenter-settings.json')

var queryTemplateProgress = take('${imageDefinitionName}-${guidId}-query',64)

var storage = {
  '256': 'ssd_256gb'
  '512': 'ssd_512gb'
  '1024': 'ssd_1024gb'
}

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

resource computeGallery 'Microsoft.Compute/galleries@2022-03-03' existing = {
  name: galleryName
}

resource contirbutorGalleryRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subscription().id, resourceGroup().id, managedIdentity.id, CONTRIBUTOR_ROLE)
  scope: computeGallery
  properties: {
    principalId: managedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: resourceId('Microsoft.Authorization/roleDefinitions', CONTRIBUTOR_ROLE)
  }
}

resource readGalleryRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subscription().id, resourceGroup().id, WINDOWS365_PRINCIPALID, READER_ROLE)
  scope: computeGallery
  properties: {
    principalId: WINDOWS365_PRINCIPALID
    principalType: 'ServicePrincipal'
    roleDefinitionId: resourceId('Microsoft.Authorization/roleDefinitions', READER_ROLE)
  }
}

resource devcenterGallery 'Microsoft.DevCenter/devcenters/galleries@2023-01-01-preview' = {
  name: galleryName
  parent: devcenter
  properties: {
    galleryResourceId: computeGallery.id
  }
  dependsOn: [
    readGalleryRole
    contirbutorGalleryRole
  ]
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

resource dcGalleryImage 'Microsoft.DevCenter/devcenters/galleries/images@2022-11-11-preview' existing = {
  name: imageDefinitionName
  parent: devcenterGallery
}

resource imageTemplateBuild 'Microsoft.Resources/deploymentScripts@2020-10-01' = {
  name: queryTemplateProgress
  location: location
  kind: 'AzurePowerShell'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${managedIdentity.id}': {}
    }
  }
  properties: {
    azPowerShellVersion: '8.3'
    scriptContent: 'Connect-AzAccount -Identity; \'Az.ImageBuilder\', \'Az.ManagedServiceIdentity\' | ForEach-Object {Install-Module -Name $_ -AllowPrerelease -Force}; $status=\'Started\'; while ($status -ne \'Succeeded\' -and $status -ne \'Failed\' -and $status -ne \'Cancelled\') { Start-Sleep -Seconds 30;$status = (Get-AzImageBuilderTemplate -ImageTemplateName ${imageTemplateName} -ResourceGroupName ${resourceGroup().name}).LastRunStatusRunState}'
    timeout: 'PT2H'
    cleanupPreference: 'OnSuccess'
    retentionInterval: 'P1D'
  }
}

resource customizedImageDevboxDefinitions 'Microsoft.DevCenter/devcenters/devboxdefinitions@2022-11-11-preview' = {
  parent: devcenter
  name: devboxDefnitionName
  location: location
  properties: {
    imageReference: {
      id: dcGalleryImage.id
    }
    sku: {
      name: 'general_i_8c32gb${devboxStorageSize}ssd_v2'
    }
    osStorageType: storage[devboxStorageSize]
  }
  dependsOn: [
    attachedNetworks
    imageTemplateBuild
  ]
}

resource project 'Microsoft.DevCenter/projects@2022-11-11-preview' = {
  name: projectName
  location: location
  properties: {
    devCenterId: devcenter.id
  }

  dependsOn: [
    customizedImageDevboxDefinitions
  ]
}

resource devboxPool 'Microsoft.DevCenter/projects/pools@2023-04-01' =  {
  parent: project
  name: devboxPoolName
  location: location
  properties: {
    devBoxDefinitionName: devboxDefnitionName
    networkConnectionName: networkConnection.name
    licenseType: 'Windows_Client'
    localAdministrator: 'Enabled'
  }
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

resource catalogs 'Microsoft.DevCenter/devcenters/catalogs@2023-01-01-preview' = {
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

output devboxDefinitionName string = customizedImageDevboxDefinitions.name

output networkConnectionName string = networkConnection.name

output projectName string = project.name

output poolName string = devboxPool.name
