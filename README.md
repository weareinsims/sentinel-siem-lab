# Azure Sentinel SIEM Lab

I built this lab to get hands-on with Microsoft Sentinel outside of work. The goal was to set up a real detection environment, write custom KQL rules, and automate incident response using Logic Apps. Everything here is deployable from scratch using the scripts in this repo.

**Khizar Khan** | [LinkedIn](https://www.linkedin.com/in/khizarkhan1999/) | [Portfolio](https://weareinsims.github.io)

---

## What's in here

```
sentinel-siem-lab/
├── deploy/
│   ├── main.bicep                  # deploys the Log Analytics workspace + Sentinel
│   ├── parameters.json             # deployment parameters
│   └── deploy.ps1                  # run this to set everything up
├── connectors/
│   └── onboard-connectors.ps1      # connects data sources to the workspace
├── detection-rules/
│   ├── brute-force-login.json      # fires on 10+ failed logins from same IP in 1hr
│   ├── impossible-travel.json      # catches sign-ins from 2 countries within 60 min
│   ├── privilege-escalation.json   # alerts when someone gets added to a privileged group
│   └── suspicious-powershell.json  # looks for encoded commands, download cradles, etc.
├── playbooks/
│   └── auto-incident-response.json # Logic App that emails on High/Medium incidents
└── screenshots/                    # screenshots of the live deployment
```

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
│  │  │      ├── Email on High/Medium incidents    │  │  │
│  │  │      └── Auto-assign High severity         │  │  │
│  │  └────────────────────────────────────────────┘  │  │
│  └──────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────┘
```

---

## Setup

**What you need:**
- Azure subscription (free tier is fine, costs basically nothing)
- Azure CLI installed
- PowerShell 7+
- Contributor access on the subscription

**Step 1 - Clone the repo**
```bash
git clone https://github.com/weareinsims/sentinel-siem-lab.git
cd sentinel-siem-lab
```

**Step 2 - Login to Azure**
```bash
az login
az account set --subscription "<your-subscription-id>"
```

**Step 3 - Deploy the infrastructure**
```powershell
cd deploy
.\deploy.ps1 -SubscriptionId "<your-subscription-id>"
```

This creates the resource group, deploys the Log Analytics workspace, enables Sentinel, and loads the detection rules.

**Step 4 - Connect data sources**
```powershell
cd connectors
.\onboard-connectors.ps1 -ResourceGroupName "rg-sentinel-siem-lab" -WorkspaceName "sentinel-siem-lab-ws"
```

**Step 5 - Deploy the playbook**
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

### Brute Force Login
**Severity:** High | **MITRE:** T1110, T1110.001

Triggers when the same IP has 10 or more failed logins within an hour. Checks both Windows Security Events (Event ID 4625) and Azure AD sign-in logs so it works across hybrid environments.

```kql
SecurityEvent
| where EventID == 4625
| summarize FailedAttempts = count() by IpAddress, Computer
| where FailedAttempts >= 10
```

---

### Impossible Travel
**Severity:** Medium | **MITRE:** T1078, T1078.004

Looks for successful Azure AD logins from two different countries within 60 minutes. If someone signs in from Canada and then the UK 20 minutes later, something is wrong.

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
**Severity:** High | **MITRE:** T1078.002, T1098

Fires when a user gets added to a privileged group like Domain Admins, Enterprise Admins, or Global Administrator. Covers both on-prem AD (Event IDs 4728, 4732, 4756) and Azure AD role assignments.

---

### Suspicious PowerShell
**Severity:** Medium | **MITRE:** T1059.001, T1027, T1562.001

Monitors PowerShell script block logs (Event ID 4104) for stuff that shows up in real attacks: encoded commands, download cradles, AMSI bypass strings, mimikatz keywords. Requires Script Block Logging enabled via GPO.

---

## Incident Response Playbook

Logic App that runs automatically when Sentinel creates a new incident.

| Severity | What happens |
|---|---|
| High or Medium | Sends an email to the SOC inbox |
| High only | Sets incident to Active and assigns it |

---

## Cost

Ran this on the Azure free tier. Total cost was basically $0.

| Resource | Monthly cost |
|---|---|
| Log Analytics Workspace | $0 (first 5GB/day free) |
| Microsoft Sentinel | $0 (first 10GB/day free for 90 days) |
| Logic App | under $0.05 |

---

## Author

**Khizar Khan**
- Portfolio: [weareinsims.github.io](https://weareinsims.github.io)
- LinkedIn: [khizarkhan1999](https://www.linkedin.com/in/khizarkhan1999/)
- GitHub: [weareinsims](https://github.com/weareinsims)
