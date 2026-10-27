# Dokploy Cluster with Azure Image Gallery Images (Packer + Ansible)

Bake and deploy a hardened **Ubuntu 26.04 LTS** Azure VM image pre-loaded with **Docker**, **UFW firewall**, and pre-cached container images (**Dokploy**, **Traefik v3.6.25**, and **Postgres 16**) for near-instant deployment without runtime image downloads.

---

## 1. Azure Login

```bash
# Login to Azure
az login

# Get your active Subscription ID
az account show --query id -o tsv
```

---

## 2. One-Time Azure Setup

Create your base resource group, image gallery, and image definition:

```bash
# 1. Create Resource Group
az group create --name dockploy-rg --location <YOUR_LOCATION>

# 2. Create Azure Compute Gallery
az sig create \
  --resource-group dockploy-rg \
  --gallery-name dockploy_image_gallery \
  --location <YOUR_LOCATION>

# 3. Create Image Definition inside Gallery
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

```bash
cd packer

# 1. Initialize required plugins
packer init .

# 2. Format configuration file
packer fmt .

# 3. Validate template and variables
packer validate -var-file="variables.pkrvars.hcl" .

# 4. Build image into Azure Compute Gallery
packer build -var-file="variables.pkrvars.hcl" .
```

> [!NOTE]
> **About `vm_size`:**
> - The `vm_size` in your Packer template is only used for the temporary build VM during baking.
> - You can choose any suitable VM size (e.g., `Standard_B2als_v2`, `Standard_B2ats_v2`, etc.) when deploying your final VMs in Step 4.

---

## 4. Deploy Primary Manager VM

```bash
# 1. Deploy VM from Azure Compute Gallery (latest version)
az vm create \
  --resource-group dockploy-rg \
  --name dockploy-vm \
  --image "/subscriptions/$(az account show --query id -o tsv)/resourceGroups/dockploy-rg/providers/Microsoft.Compute/galleries/dockploy_image_gallery/images/dockploy_ubuntu_2604_lts/versions/latest" \
  --size <YOUR_VM_SIZE> \
  --admin-username azureuser \
  --generate-ssh-keys \
  --public-ip-sku Standard

# 2. Open HTTP, HTTPS, and Dokploy dashboard ports in Azure NSG
az vm open-port --resource-group dockploy-rg --name dockploy-vm --port 3000 --priority 1001
az vm open-port --resource-group dockploy-rg --name dockploy-vm --port 80   --priority 1002
az vm open-port --resource-group dockploy-rg --name dockploy-vm --port 443  --priority 1003
```

---

## 5. Initialize Dokploy on Primary VM

Get your VM's public IP:
```bash
az vm list-ip-addresses --resource-group dockploy-rg --name dockploy-vm --output table
```

SSH into the VM and initialize Dokploy (since dependencies are pre-baked, this takes <10s):
```bash
ssh azureuser@<VM_PUBLIC_IP>

# Initialize Dokploy with VM's local IP
curl -sSL https://dokploy.com/install.sh | bash
```

---

## 6. Access Dokploy Dashboard

Open your browser and navigate to:
```text
http://<VM_PUBLIC_IP>:3000
```
Follow the onboarding wizard to create your initial admin account.

---

## 7. (Optional) Cluster Additional Worker VMs

To scale container workloads across multiple servers, you can add worker nodes. Worker nodes execute container tasks; only the primary Manager node hosts the Dokploy Web UI.

### Step 1: Deploy a Worker VM

**Option A: Using the Custom Baked Image (Recommended — Docker & UFW pre-configured)**
```bash
az vm create \
  --resource-group dockploy-rg \
  --name dockploy-worker-1 \
  --image "/subscriptions/$(az account show --query id -o tsv)/resourceGroups/dockploy-rg/providers/Microsoft.Compute/galleries/dockploy_image_gallery/images/dockploy_ubuntu_2604_lts/versions/latest" \
  --size <YOUR_VM_SIZE> \
  --admin-username azureuser \
  --generate-ssh-keys \
  --public-ip-sku Standard
```

**Option B: Using ANY Standard Linux VM (e.g. Ubuntu 24.04)**
```bash
az vm create \
  --resource-group dockploy-rg \
  --name dockploy-worker-1 \
  --image Ubuntu2404 \
  --size <YOUR_VM_SIZE> \
  --admin-username azureuser \
  --generate-ssh-keys \
  --public-ip-sku Standard
```
*(If using Option B, install Docker on it: `sudo apt-get update && sudo apt-get install -y docker.io`).*

### Step 2: Join the Worker to the Cluster

> [!IMPORTANT]
> **Do NOT run `install.sh` on worker nodes.** Worker nodes only join the existing cluster.

1. Open your Dokploy Dashboard on the primary manager $\rightarrow$ **Cluster / Nodes** tab.
2. Copy the **Worker Join Command**:
   ```bash
   docker swarm join --token <WORKER_TOKEN> <MANAGER_PRIVATE_IP>:2377
   ```
3. SSH into `dockploy-worker-1` and run the join command.
4. The worker will appear in your Dokploy Web UI and start accepting container tasks!

---

## 8. Cost Management

```bash
# Stop VM (pauses compute billing; keeps disk & configurations safe):
az vm deallocate --resource-group dockploy-rg --name dockploy-vm

# Start VM back up (ready in ~30 seconds):
az vm start --resource-group dockploy-rg --name dockploy-vm

# Delete all resources and destroy environment when finished:
az group delete --name dockploy-rg --yes --no-wait
```
