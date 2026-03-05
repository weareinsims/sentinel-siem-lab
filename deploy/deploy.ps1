# ============================================================
# Azure Sentinel SIEM Lab - Deployment Script
# Author: Khizar Khan
# Description: Deploys the full Sentinel lab environment
#              including workspace, Sentinel, and detection rules
# Usage: .\deploy.ps1 -SubscriptionId "<your-sub-id>"
# ============================================================

param(
    [Parameter(Mandatory = $true)]
    [string]$SubscriptionId,

    [Parameter(Mandatory = $false)]
    [string]$ResourceGroupName = "rg-sentinel-siem-lab",

    [Parameter(Mandatory = $false)]
    [string]$Location = "canadacentral",

    [Parameter(Mandatory = $false)]
    [string]$WorkspaceName = "sentinel-siem-lab-ws"
)

$ErrorActionPreference = "Stop"
$ScriptRoot = $PSScriptRoot

Write-Host "`n================================================" -ForegroundColor Cyan
Write-Host "  Azure Sentinel SIEM Lab - Deployment" -ForegroundColor Cyan
Write-Host "================================================`n" -ForegroundColor Cyan

# ============================================================
# STEP 1: Verify Prerequisites
# ============================================================
Write-Host "[1/5] Checking prerequisites..." -ForegroundColor Yellow

if (-not (Get-Command "az" -ErrorAction SilentlyContinue)) {
    Write-Error "Azure CLI not found. Install from: https://aka.ms/installazurecliwindows"
    exit 1
}

$azVersion = (az version --query '"azure-cli"' -o tsv)
Write-Host "  Azure CLI version: $azVersion" -ForegroundColor Green

# ============================================================
# STEP 2: Authenticate and Set Subscription
# ============================================================
Write-Host "`n[2/5] Authenticating to Azure..." -ForegroundColor Yellow

$currentAccount = az account show --query "id" -o tsv 2>$null
if (-not $currentAccount) {
    Write-Host "  Launching Azure login..." -ForegroundColor White
    az login | Out-Null
}

az account set --subscription $SubscriptionId | Out-Null
$subName = az account show --query "name" -o tsv
Write-Host "  Subscription: $subName ($SubscriptionId)" -ForegroundColor Green

# ============================================================
# STEP 3: Create Resource Group
# ============================================================
Write-Host "`n[3/5] Creating resource group '$ResourceGroupName'..." -ForegroundColor Yellow

$rgExists = az group exists --name $ResourceGroupName
if ($rgExists -eq "true") {
    Write-Host "  Resource group already exists — skipping." -ForegroundColor DarkGray
} else {
    az group create --name $ResourceGroupName --location $Location | Out-Null
    Write-Host "  Created: $ResourceGroupName ($Location)" -ForegroundColor Green
}

# ============================================================
# STEP 4: Deploy Bicep Template
# ============================================================
Write-Host "`n[4/5] Deploying Sentinel workspace and solution..." -ForegroundColor Yellow

$deploymentName = "sentinel-lab-$(Get-Date -Format 'yyyyMMddHHmm')"
$bicepFile = Join-Path $ScriptRoot "main.bicep"
$paramsFile = Join-Path $ScriptRoot "parameters.json"

$deployResult = az deployment group create `
    --name $deploymentName `
    --resource-group $ResourceGroupName `
    --template-file $bicepFile `
    --parameters $paramsFile `
    --parameters workspaceName=$WorkspaceName location=$Location `
    --output json | ConvertFrom-Json

if ($LASTEXITCODE -ne 0) {
    Write-Error "Deployment failed. Check the Azure portal for details."
    exit 1
}

$workspaceId = $deployResult.properties.outputs.workspaceId.value
$portalUrl   = $deployResult.properties.outputs.sentinelPortalUrl.value

Write-Host "  Workspace deployed: $WorkspaceName" -ForegroundColor Green
Write-Host "  Workspace ID: $workspaceId" -ForegroundColor Green

# ============================================================
# STEP 5: Deploy Detection Rules
# ============================================================
Write-Host "`n[5/5] Deploying detection rules..." -ForegroundColor Yellow

$rulesPath = Join-Path (Split-Path $ScriptRoot) "detection-rules"
$ruleFiles = Get-ChildItem -Path $rulesPath -Filter "*.json"

foreach ($ruleFile in $ruleFiles) {
    Write-Host "  Deploying rule: $($ruleFile.BaseName)..." -ForegroundColor White

    $ruleJson = Get-Content $ruleFile.FullName -Raw

    az sentinel alert-rule create `
        --resource-group $ResourceGroupName `
        --workspace-name $WorkspaceName `
        --rule-id (New-Guid).ToString() `
        --kind "Scheduled" `
        --scheduled-properties $ruleJson `
        --output none 2>$null

    if ($LASTEXITCODE -eq 0) {
        Write-Host "    [OK] $($ruleFile.BaseName)" -ForegroundColor Green
    } else {
        Write-Host "    [WARN] Could not auto-deploy $($ruleFile.BaseName) - import manually via Sentinel portal" -ForegroundColor DarkYellow
    }
}

# ============================================================
# SUMMARY
# ============================================================
Write-Host "`n================================================" -ForegroundColor Cyan
Write-Host "  Deployment Complete!" -ForegroundColor Green
Write-Host "================================================" -ForegroundColor Cyan
Write-Host "  Resource Group : $ResourceGroupName"
Write-Host "  Workspace      : $WorkspaceName"
Write-Host "  Location       : $Location"
Write-Host "  Sentinel Portal: $portalUrl"
Write-Host "`n  Next steps:"
Write-Host "  1. Open the Sentinel portal link above"
Write-Host "  2. Run connectors\onboard-connectors.ps1 to connect data sources"
Write-Host "  3. Review detection rules under Analytics > Active rules"
Write-Host "================================================`n" -ForegroundColor Cyan
