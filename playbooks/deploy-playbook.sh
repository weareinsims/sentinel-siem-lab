#!/bin/bash
az deployment group create \
  --resource-group rg-sentinel-siem-lab \
  --template-file /home/khizar/sentinel-siem-lab/playbooks/auto-incident-response.json \
  --parameters NotificationEmail=khizarazakhan@gmail.com \
  --parameters WorkspaceName=sentinel-siem-lab-ws \
  --parameters ResourceGroupName=rg-sentinel-siem-lab
