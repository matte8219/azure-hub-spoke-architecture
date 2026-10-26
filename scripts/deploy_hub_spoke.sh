#!/bin/bash
# Azure Hub-and-Spoke Deployment Script

# 1. Variables
RESOURCE_GROUP="rg-portfolio-hubspoke"
LOCATION="northeurope"

# 2. Create Resource Group
az group create --name $RESOURCE_GROUP --location $LOCATION

# 3. Create Hub VNet and Subnet
az network vnet create \
  --resource-group $RESOURCE_GROUP \
  --name vnet-hub \
  --address-prefix 10.0.0.0/16 \
  --subnet-name snet-gateway \
  --subnet-prefix 10.0.1.0/24

# 4. Create Spoke VNet and Subnet
az network vnet create \
  --resource-group $RESOURCE_GROUP \
  --name vnet-spoke \
  --address-prefix 10.1.0.0/16 \
  --subnet-name snet-workload \
  --subnet-prefix 10.1.1.0/24

# 5. Peer Hub to Spoke
az network vnet peering create \
  --resource-group $RESOURCE_GROUP \
  --name peer-hub-to-spoke \
  --vnet-name vnet-hub \
  --remote-vnet vnet-spoke \
  --allow-vnet-access

# 6. Peer Spoke to Hub
az network vnet peering create \
  --resource-group $RESOURCE_GROUP \
  --name peer-spoke-to-hub \
  --vnet-name vnet-spoke \
  --remote-vnet vnet-hub \
  --allow-vnet-access

# 7. Create Isolated Spoke VM
az vm create \
  --resource-group $RESOURCE_GROUP \
  --name vm-spoke-web \
  --vnet-name vnet-spoke \
  --subnet snet-workload \
  --image Ubuntu2204 \
  --size Standard_D2als_v6 \
  --admin-username azureuser \
  --generate-ssh-keys \
  --public-ip-address ""

# 8. Open Port 80 on VM Network Security Group
az vm open-port \
  --resource-group $RESOURCE_GROUP \
  --name vm-spoke-web \
  --port 80 \
  --priority 100

# 9. Install Backend Web Server via Run Command (No Outbound Internet Workaround)
az vm run-command invoke \
  --resource-group $RESOURCE_GROUP \
  --name vm-spoke-web \
  --command-id RunShellScript \
  --scripts "echo '<h1>Welcome to my secure Hub and Spoke Architecture!</h1>' > index.html && sudo nohup python3 -m http.server 80 &"

# 10. Get VM Private IP for Application Gateway Backend Pool
PRIVATE_IP=$(az vm show --resource-group $RESOURCE_GROUP --name vm-spoke-web --show-details --query privateIps --output tsv)

# 11. Create Public IP for Application Gateway
az network public-ip create \
  --resource-group $RESOURCE_GROUP \
  --name pip-appgw \
  --sku Standard

# 12. Create Application Gateway (Priority 100 specified for API requirement)
az network application-gateway create \
  --name appgw-portfolio \
  --resource-group $RESOURCE_GROUP \
  --vnet-name vnet-hub \
  --subnet snet-gateway \
  --capacity 1 \
  --sku Standard_v2 \
  --public-ip-address pip-appgw \
  --priority 100 \
  --servers $PRIVATE_IP
