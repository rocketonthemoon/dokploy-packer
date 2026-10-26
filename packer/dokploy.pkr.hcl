packer {
  required_plugins {
    azure = {
      source  = "github.com/hashicorp/azure"
      version = ">=2.6.0"
    }
  }
}

variable "subscription_id" {
    type = string
    description = "Azure Subscription ID (az account show --query id)"
}

variable "vm_size" {
    type = string
    description = "VM size"
    default = "Standard_B2als_v2"
}

variable "location" {
    type = string
    description = "Location"
    default = "polandcentral"
}

source "azure-arm" "dockploy" {
    use_azure_cli_auth                = true
    subscription_id                   = var.subscription_id
    os_type                           = "Linux"

    # Base Image
    image_publisher                   = "Canonical"
    image_offer                       = "ubuntu-26_04-lts"
    image_sku                         = "server"
    image_version                     = "latest"

    location                          = var.location
    vm_size                           = var.vm_size

    # Temporary resource group for snapshot disk
    managed_image_resource_group_name = "dockploy-rg"

    # Target destination in Azure Compute Gallery
    shared_image_gallery_destination {
        resource_group      = "dockploy-rg"
        gallery_name        = "dockploy-image-gallery"
        image_name          = "dockploy-ubuntu-2604-lts"
        image_version       = "1.0.0"
        replication_regions = ["polandcentral"]
    }
}

build {
    sources = ["source.azure-arm.dockploy"]

    provisioner "ansible-local" {
        playbook_file = "./ansible/playbook.yaml"
    }
}