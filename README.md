# Azure Sentinel SIEM Lab

A production-style Microsoft Sentinel deployment for hands-on security operations practice. Covers automated infrastructure provisioning, multi-source data ingestion, custom KQL threat detection, and automated incident response playbooks.

Built by **Khizar Khan** — Cybersecurity & IT Professional | [LinkedIn](https://www.linkedin.com/in/khizarkhan1999/) | [Portfolio](https://weareinsims.github.io)

---

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                  Azure Resource Group                   │
│                                                         │
│  ┌──────────────────────────────────────────────────┐  │
│  │         Log Analytics Workspace                  │  │
│  │                                                  │  │
│  │  Data Sources:                                   │  │
│  │  ├── Azure AD Sign-in & Audit Logs               │  │
│  │  ├── Azure Activity Logs                         │  │
│  │  └── Windows Security Events (via AMA + DCR)     │  │
│  │                                                  │  │
│  │  ┌────────────────────────────────────────────┐  │  │
│  │  │       Microsoft Sentinel                   │  │  │
│  │  │                                            │  │  │
│  │  │  Detection Rules (KQL):                    │  │  │
│  │  │  ├── Brute Force Login Attack              │  │  │
│  │  │  ├── Impossible Travel                     │  │  │
│  │  │  ├── Privilege Escalation                  │  │  │
│  │  │  └── Suspicious PowerShell Execution       │  │  │
│  │  │                                            │  │  │
│  │  │  Playbook (Logic App):                     │  │  │
│  │  │  └── Auto Incident Response                │  │  │
│  │  │      ├── Email notification (High/Med)     │  │  │
│  │  │      ├── Incident auto-assignment          │  │  │
│  │  │      └── Sentinel comment logging          │  │  │
│  │  └────────────────────────────────────────────┘  │  │
│  └──────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────┘
```

---

## Repository Structure

```
sentinel-siem-lab/
├── deploy/
│   ├── main.bicep                  # IaC - deploys workspace + Sentinel
│   ├── parameters.json             # Deployment parameters
│   └── deploy.ps1                  # One-click deployment script
├── connectors/
│   └── onboard-connectors.ps1      # Enables data connectors via REST API
├── detection-rules/
│   ├── brute-force-login.json      # KQL: 10+ failed logins in 1hr
│   ├── impossible-travel.json      # KQL: sign-in from 2 countries < 60min
│   ├── privilege-escalation.json   # KQL: user added to privileged group
│   └── suspicious-powershell.json  # KQL: obfuscation / download cradles
├── playbooks/
│   └── auto-incident-response.json # Logic App: auto-notify + assign incidents
└── docs/
    └── setup-guide.md              # Step-by-step deployment walkthrough
```

---

## Prerequisites

| Requirement | Details |
|---|---|
| Azure Subscription | Free tier works — estimated cost: ~$0–5/month |
| Azure CLI | [Install guide](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli) |
| PowerShell 7+ | [Install guide](https://learn.microsoft.com/en-us/powershell/scripting/install/installing-powershell) |
| Contributor role | On the target subscription or resource group |

---

## Quick Start

### 1. Clone the repository
```bash
git clone https://github.com/weareinsims/sentinel-siem-lab.git
cd sentinel-siem-lab
```

### 2. Login to Azure
```bash
az login
az account set --subscription "<your-subscription-id>"
```

### 3. Deploy the infrastructure
```powershell
cd deploy
.\deploy.ps1 -SubscriptionId "<your-subscription-id>"
```

This single command:
- Creates the resource group `rg-sentinel-siem-lab`
- Deploys a Log Analytics Workspace
- Enables Microsoft Sentinel
- Deploys all 4 detection rules

### 4. Onboard data connectors
```powershell
cd connectors
.\onboard-connectors.ps1 `
  -ResourceGroupName "rg-sentinel-siem-lab" `
  -WorkspaceName "sentinel-siem-lab-ws"
```

### 5. Deploy the incident response playbook
```bash
az deployment group create \
  --resource-group rg-sentinel-siem-lab \
  --template-file playbooks/auto-incident-response.json \
  --parameters NotificationEmail="your@email.com" \
               WorkspaceName="sentinel-siem-lab-ws" \
               ResourceGroupName="rg-sentinel-siem-lab"
```

---

## Detection Rules

### Brute Force Login Attack
**Severity:** High | **Tactics:** Credential Access, Initial Access

Detects 10+ failed login attempts from the same IP within 1 hour across:
- Windows Security Events (Event ID 4625)
- Azure AD Sign-in logs

```kql
SecurityEvent
| where EventID == 4625
| summarize FailedAttempts = count() by IpAddress, Computer
| where FailedAttempts >= 10
```

---

### Impossible Travel
**Severity:** Medium | **Tactics:** Initial Access, Credential Access

Detects successful Azure AD sign-ins from geographically distant countries within 60 minutes — a physical impossibility indicating credential compromise.

```kql
SigninLogs
| where ResultType == "0"
| sort by UserPrincipalName, TimeGenerated asc
| serialize
| extend PrevCountry = prev(CountryOrRegion, 1), TimeDiff = datetime_diff('minute', TimeGenerated, prev(TimeGenerated,1))
| where TimeDiff < 60 and CountryOrRegion != PrevCountry
```

---

### Privilege Escalation
**Severity:** High | **Tactics:** Privilege Escalation, Persistence

Fires when any user is added to Domain Admins, Enterprise Admins, Global Administrator, or other high-privilege groups in both on-prem AD and Azure AD.

**Monitored Event IDs:** 4728, 4732, 4756 (AD group membership changes)

---

### Suspicious PowerShell Execution
**Severity:** Medium | **Tactics:** Execution, Defense Evasion, Credential Access

Detects PowerShell script blocks (Event ID 4104) containing:
- Encoded commands (`-enc`, `-EncodedCommand`)
- Download cradles (`DownloadString`, `Invoke-WebRequest`)
- AMSI bypass attempts (`AmsiUtils`, `amsiInitFailed`)
- Credential dumping keywords (`mimikatz`, `sekurlsa`)

> Requires PowerShell Script Block Logging enabled via GPO.

---

## Automated Incident Response Playbook

The Logic App playbook triggers on every new Sentinel incident and:

| Severity | Action |
|---|---|
| High & Medium | Sends email notification to SOC team |
| High & Medium | Adds comment to Sentinel incident |
| High only | Auto-assigns incident and sets status to Active |

---

## Cost Estimate (Free Tier)

| Resource | SKU | Estimated Monthly Cost |
|---|---|---|
| Log Analytics Workspace | PerGB2018 (first 5GB/day free) | $0 |
| Microsoft Sentinel | First 10GB/day free (90 days) | $0 |
| Logic App (Playbook) | ~20 runs/month | < $0.05 |
| **Total** | | **~$0** |

> The Azure free account includes $200 credit for 30 days + 12 months of free services.

---

## Author

**Khizar Khan**
- Portfolio: [weareinsims.github.io](https://weareinsims.github.io)
- LinkedIn: [khizarkhan1999](https://www.linkedin.com/in/khizarkhan1999/)
- GitHub: [weareinsims](https://github.com/weareinsims)
