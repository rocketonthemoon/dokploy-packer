# Dokploy Swarm Cluster (Packer + Azure Compute Gallery)

Bake and deploy a hardened **Ubuntu 26.04 LTS** Azure VM image pre-loaded with **Docker**, **UFW firewall**, and pre-cached container images (**Dokploy**, **Traefik v3.6.25**, and **Postgres 16**) for near-instant deployment without runtime downloads.

---

## 1. Azure Login

```bash
az login
az account show --query id -o tsv
```

---

## 2. One-Time Azure Setup

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
  --sku 26_04-lts \
  --os-type Linux \
  --hyper-v-generation V2 \
  --location <YOUR_LOCATION>
```

---

## 3. Bake Image with Packer

```bash
cd packer

packer init .
packer fmt .
packer validate -var-file="variables.pkrvars.hcl" .
packer build -var-file="variables.pkrvars.hcl" .
```

---

## 4. Deploy Primary Manager VM

```bash
# 1. Deploy VM from Azure Compute Gallery (latest version)
az vm create \
  --resource-group dockploy-rg \
  --name dockploy-vm \
  --image "/subscriptions/$(az account show --query id -o tsv)/resourceGroups/dockploy-rg/providers/Microsoft.Compute/galleries/dockploy_image_gallery/images/dockploy_ubuntu_2604_lts" \
  --vnet-name dockploy-vnet \
  --subnet default \
  --size <YOUR_VM_SIZE> \
  --admin-username azureuser \
  --generate-ssh-keys \
  --public-ip-sku Standard

# 2. Open HTTP, HTTPS, and Dokploy dashboard ports in one command
az vm open-port --resource-group dockploy-rg --name dockploy-vm --port 80,443,3000 --priority 1001
```

---

## 5. Initialize & Access Dokploy

```bash
# 1. Get VM Public IP
az vm list-ip-addresses --resource-group dockploy-rg --name dockploy-vm --output table

# 2. SSH and initialize Dokploy (starts in < 5s since images are pre-cached)
ssh azureuser@<VM_PUBLIC_IP>
curl -sSL https://dokploy.com/install.sh | bash
```

Open your browser at:
```text
http://<VM_PUBLIC_IP>:3000
```

---

## 6. (Optional) Cluster Worker VMs

Workers run application containers while the primary manager hosts the Dokploy UI.

### Step 1: Deploy Worker VM
```bash
az vm create \
  --resource-group dockploy-rg \
  --name dockploy-worker-1 \
  --image "/subscriptions/$(az account show --query id -o tsv)/resourceGroups/dockploy-rg/providers/Microsoft.Compute/galleries/dockploy_image_gallery/images/dockploy_ubuntu_2604_lts" \
  --vnet-name dockploy-vnet \
  --subnet default \
  --size <YOUR_VM_SIZE> \
  --admin-username azureuser \
  --generate-ssh-keys \
  --public-ip-sku Standard
```

### Step 2: Join Cluster
1. On the **Manager VM**, generate the join token:
   ```bash
   docker swarm join-token worker
   ```
2. SSH into **`dockploy-worker-1`** and run the printed command:
   ```bash
   docker swarm join --token <TOKEN> <MANAGER_PRIVATE_IP>:2377
   ```
3. Verify on Manager:
   ```bash
   docker node ls
   ```

### Step 3: Scale Services
In your `docker-compose.prod.yml`:
```yaml
services:
  backend:
    deploy:
      replicas: 3
```
Or dynamically via terminal:
```bash
docker service scale <stack_name>_backend=3
```

---

## 7. (Optional) Auto-Scaling (2-Tier Overview)

* **Tier 1 (Containers):** Deploy a lightweight Swarm auto scaler container in your compose file to monitor CPU/memory via `/var/run/docker.sock` and scale container replicas dynamically.
* **Tier 2 (Infrastructure VMs):** Deploy an **Azure Virtual Machine Scale Set (VMSS)** using your gallery image and an auto-join script (`--custom-data join-swarm.sh`). Azure automatically spins up worker VMs when cluster CPU > 75% and terminates them when idle.

```bash
# Example VMSS Creation
az vmss create \
  --resource-group dockploy-rg \
  --name dockploy-worker-vmss \
  --image "/subscriptions/$(az account show --query id -o tsv)/resourceGroups/dockploy-rg/providers/Microsoft.Compute/galleries/dockploy_image_gallery/images/dockploy_ubuntu_2604_lts" \
  --vnet-name dockploy-vnet \
  --subnet default \
  --vm-sku <YOUR_VM_SIZE> \
  --instance-count 1 \
  --custom-data join-swarm.sh \
  --admin-username azureuser \
  --generate-ssh-keys
```

---

## 8. Cost Management

```bash
# Stop VM (pauses compute billing, keeps disk safe):
az vm deallocate --resource-group dockploy-rg --name dockploy-vm

# Start VM back up:
az vm start --resource-group dockploy-rg --name dockploy-vm

# Delete all resources and destroy environment:
az group delete --name dockploy-rg --yes --no-wait
```
