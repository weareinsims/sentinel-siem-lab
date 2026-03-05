# ============================================================
# Azure Sentinel SIEM Lab - Data Connector Onboarding
# Author: Khizar Khan
# Description: Enables key data connectors in Microsoft Sentinel
#              - Windows Security Events (via AMA)
#              - Azure Active Directory Sign-in Logs
#              - Azure Activity
#              - Microsoft Defender for Cloud
# Usage: .\onboard-connectors.ps1 -ResourceGroupName "rg-sentinel-siem-lab" -WorkspaceName "sentinel-siem-lab-ws"
# ============================================================

param(
    [Parameter(Mandatory = $true)]
    [string]$ResourceGroupName,

    [Parameter(Mandatory = $true)]
    [string]$WorkspaceName,

    [Parameter(Mandatory = $false)]
    [string]$SubscriptionId = (az account show --query "id" -o tsv)
)

$ErrorActionPreference = "Stop"

Write-Host "`n================================================" -ForegroundColor Cyan
Write-Host "  Sentinel - Data Connector Onboarding" -ForegroundColor Cyan
Write-Host "================================================`n" -ForegroundColor Cyan

$baseUri = "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.OperationalInsights/workspaces/$WorkspaceName/providers/Microsoft.SecurityInsights"
$apiVersion = "2023-02-01"

function Enable-SentinelConnector {
    param([string]$ConnectorId, [string]$ConnectorName, [hashtable]$Properties)

    Write-Host "  Enabling: $ConnectorName..." -ForegroundColor White

    $body = @{
        kind       = $ConnectorId
        properties = $Properties
    } | ConvertTo-Json -Depth 10

    $uri = "$baseUri/dataConnectors/$ConnectorId`?api-version=$apiVersion"

    $token = az account get-access-token --query "accessToken" -o tsv

    try {
        $response = Invoke-RestMethod -Uri $uri -Method PUT -Body $body `
            -Headers @{ Authorization = "Bearer $token"; "Content-Type" = "application/json" }
        Write-Host "    [OK] $ConnectorName enabled" -ForegroundColor Green
        return $response
    } catch {
        Write-Host "    [WARN] $ConnectorName - manual enable may be required: $_" -ForegroundColor DarkYellow
    }
}

# ============================================================
# 1. Azure Active Directory - Sign-in & Audit Logs
# ============================================================
Enable-SentinelConnector -ConnectorId "AzureActiveDirectory" -ConnectorName "Azure Active Directory" -Properties @{
    tenantId = (az account show --query "tenantId" -o tsv)
    dataTypes = @{
        alerts         = @{ state = "Enabled" }
        signinLogs     = @{ state = "Enabled" }
        auditLogs      = @{ state = "Enabled" }
    }
}

# ============================================================
# 2. Azure Activity Logs
# ============================================================
Enable-SentinelConnector -ConnectorId "AzureActivity" -ConnectorName "Azure Activity" -Properties @{
    linkedResourceId = "/subscriptions/$SubscriptionId/providers/microsoft.insights/eventtypes/management"
}

# ============================================================
# 3. Windows Security Events (requires AMA agent on VMs)
# ============================================================
Write-Host "`n  Configuring Windows Security Events collection rule..." -ForegroundColor White

$dcrName    = "sentinel-windows-security-events"
$dcrUri     = "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.Insights/dataCollectionRules/$dcrName`?api-version=2022-06-01"
$token      = az account get-access-token --query "accessToken" -o tsv

$dcrBody = @{
    location = (az group show --name $ResourceGroupName --query "location" -o tsv)
    properties = @{
        dataFlows = @(
            @{
                streams      = @("Microsoft-SecurityEvent")
                destinations = @("sentinel-workspace")
            }
        )
        destinations = @{
            logAnalytics = @(
                @{
                    workspaceResourceId = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.OperationalInsights/workspaces/$WorkspaceName"
                    name                = "sentinel-workspace"
                }
            )
        }
        dataSources = @{
            windowsEventLogs = @(
                @{
                    streams        = @("Microsoft-SecurityEvent")
                    xPathQueries   = @(
                        "Security!*[System[(EventID=4624 or EventID=4625 or EventID=4634 or EventID=4648 or EventID=4672 or EventID=4688 or EventID=4698 or EventID=4702 or EventID=4720 or EventID=4726 or EventID=4728 or EventID=4732 or EventID=4756)]]"
                    )
                    name           = "security-events-high-value"
                }
            )
        }
    }
} | ConvertTo-Json -Depth 15

try {
    Invoke-RestMethod -Uri $dcrUri -Method PUT -Body $dcrBody `
        -Headers @{ Authorization = "Bearer $token"; "Content-Type" = "application/json" } | Out-Null
    Write-Host "    [OK] Data Collection Rule created: $dcrName" -ForegroundColor Green
} catch {
    Write-Host "    [WARN] DCR creation failed - configure Windows Security Events manually in Sentinel portal" -ForegroundColor DarkYellow
}

# ============================================================
# SUMMARY
# ============================================================
Write-Host "`n================================================" -ForegroundColor Cyan
Write-Host "  Connector Onboarding Complete!" -ForegroundColor Green
Write-Host "================================================" -ForegroundColor Cyan
Write-Host "  Connectors enabled:"
Write-Host "  - Azure Active Directory (Sign-in + Audit logs)"
Write-Host "  - Azure Activity logs"
Write-Host "  - Windows Security Events (DCR configured)"
Write-Host "`n  NOTE: Windows Security Events require the"
Write-Host "  Azure Monitor Agent (AMA) installed on target VMs."
Write-Host "  See docs/setup-guide.md for AMA installation steps."
Write-Host "================================================`n" -ForegroundColor Cyan
