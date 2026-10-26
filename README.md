# CyberShield Infrastructure

Bake and deploy a custom **Ubuntu 26.04 LTS** image pre-configured with **Docker**, **Dokploy**, and **UFW** on Azure using **Packer** and **Ansible**.

---

## 1. Azure Login

```powershell
# Login to Azure
az login

# Get your Subscription ID
az account show --query id -o tsv
```

---

## 2. One-Time Azure Setup

```powershell
# 1. Create Resource Group
az group create --name dockploy-rg --location <YOUR_LOCATION>

# 2. Create Azure Compute Gallery
az sig create \
  --resource-group dockploy-rg \
  --gallery-name dockploy_image_gallery \
  --location <YOUR_LOCATION>

# 3. Create Image Definition
az sig image-definition create \
  --resource-group dockploy-rg \
  --gallery-name dockploy_image_gallery \
  --gallery-image-definition dockploy_ubuntu_2604_lts \
  --publisher Custom \
  --offer Ubuntu \
  --sku 26-04-lts \
  --os-type Linux \
  --hyper-v-generation V2 \
  --location <YOUR_LOCATION>
```

---

## 3. Build Image with Packer

```powershell
cd packer

# 1. Initialize Packer plugins
packer init .

# 2. Format Packer file
packer fmt .

# 3. Validate configuration
packer validate -var-file="variables.pkrvars.hcl" .

# 4. Build image
packer build -var-file="variables.pkrvars.hcl" .
```

---

> [!NOTE]
> **About `vm_size`:**
> - The `vm_size` specified in the Packer template is only used for the temporary build VM while baking the image.
> - You can choose any suitable VM size when deploying the final VM in Step 4 based on your workload requirements.

## 4. Deploy VM from Built Image

```powershell
# Launch VM from Azure Compute Gallery (latest version)
az vm create \
  --resource-group dockploy-rg \
  --name dockploy-vm \
  --image "/subscriptions/$(az account show --query id -o tsv)/resourceGroups/dockploy-rg/providers/Microsoft.Compute/galleries/dockploy_image_gallery/images/dockploy_ubuntu_2604_lts/versions/latest" \
  --size <YOUR_VM_SIZE> \
  --admin-username azureuser \
  --generate-ssh-keys \
  --public-ip-sku Standard

# Open Dokploy port (3000) on Azure Network Security Group
az vm open-port --resource-group dockploy-rg --name dockploy-vm --port 3000 --priority 1001
az vm open-port --resource-group dockploy-rg --name dockploy-vm --port 80 --priority 1002
az vm open-port --resource-group dockploy-rg --name dockploy-vm --port 443 --priority 1003
```

---

## 5. Initialize Dokploy on the VM

Get your VM's public IP:
```bash
az vm list-ip-addresses --resource-group dockploy-rg --name dockploy-vm --output table
```

SSH into the VM and re-initialize Dokploy (since images are pre-baked, this takes <10s):
```bash
ssh azureuser@<VM_PUBLIC_IP>

# Initialize Dokploy with VM's local IP
curl -sSL https://dokploy.com/install.sh | bash
```

---

## 6. Access Dokploy Dashboard

Open in your browser:
```text
http://<VM_PUBLIC_IP>:3000
```

---

## 7. Cost Management

```bash
# Stop VM (pauses compute billing):
az vm deallocate --resource-group dockploy-rg --name dockploy-vm

# Start VM:
az vm start --resource-group dockploy-rg --name dockploy-vm

# Delete everything when done:
az group delete --name dockploy-rg --yes --no-wait
```
