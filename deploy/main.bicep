// ============================================================
// Azure Sentinel SIEM Lab - Main Deployment Template
// Author: Khizar Khan
// Description: Deploys Log Analytics Workspace + Microsoft
//              Sentinel in a single resource group
// ============================================================

@description('Name of the Log Analytics Workspace')
param workspaceName string = 'sentinel-siem-lab-ws'

@description('Azure region for all resources')
param location string = resourceGroup().location

@description('Retention period in days (free tier: 90 days max)')
@minValue(30)
@maxValue(90)
param retentionDays int = 90

@description('SKU for Log Analytics Workspace')
@allowed(['PerGB2018', 'Free'])
param workspaceSku string = 'PerGB2018'

@description('Tags applied to all resources')
param tags object = {
  project: 'sentinel-siem-lab'
  owner: 'khizar-khan'
  environment: 'lab'
}

// ============================================================
// LOG ANALYTICS WORKSPACE
// ============================================================
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: workspaceName
  location: location
  tags: tags
  properties: {
    sku: {
      name: workspaceSku
    }
    retentionInDays: retentionDays
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// ============================================================
// MICROSOFT SENTINEL (SecurityInsights Solution)
// ============================================================
resource sentinel 'Microsoft.OperationsManagement/solutions@2015-11-01-preview' = {
  name: 'SecurityInsights(${workspaceName})'
  location: location
  tags: tags
  plan: {
    name: 'SecurityInsights(${workspaceName})'
    publisher: 'Microsoft'
    product: 'OMSGallery/SecurityInsights'
    promotionCode: ''
  }
  properties: {
    workspaceResourceId: logAnalyticsWorkspace.id
  }
}

// ============================================================
// SENTINEL ONBOARDING (enables Sentinel on the workspace)
// ============================================================
resource sentinelOnboarding 'Microsoft.SecurityInsights/onboardingStates@2022-11-01' = {
  name: 'default'
  scope: logAnalyticsWorkspace
  properties: {}
  dependsOn: [sentinel]
}

// ============================================================
// OUTPUTS
// ============================================================
output workspaceId string = logAnalyticsWorkspace.id
output workspaceName string = logAnalyticsWorkspace.name
output workspaceResourceGroup string = resourceGroup().name
output sentinelPortalUrl string = 'https://portal.azure.com/#blade/Microsoft_Azure_Security_Insights/MainMenuBlade/0/id/%2Fsubscriptions%2F${subscription().subscriptionId}%2FresourceGroups%2F${resourceGroup().name}%2Fproviders%2FMicrosoft.OperationalInsights%2Fworkspaces%2F${workspaceName}'
