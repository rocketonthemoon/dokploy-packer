packer {
  required_plugins {
    azure = {
      source  = "github.com/hashicorp/azure"
      version = ">=2.6.0"
    }
    ansible = {
      source  = "github.com/hashicorp/ansible"
      version = ">=1.1.6"
    }
  }
}

variable "subscription_id" {
  type        = string
  description = "Azure Subscription ID (az account show --query id)"
}

variable "vm_size" {
  type        = string
  description = "VM size"
  default     = "Standard_B2ats_v2"
}

variable "location" {
  type        = string
  description = "Location"
  default     = "polandcentral"
}

variable "image_version" {
  type        = string
  description = "Image version"
  default     = "1.0.0"
}

source "azure-arm" "dockploy" {
  use_azure_cli_auth = true
  subscription_id    = var.subscription_id
  os_type            = "Linux"

  # Base Image
  # if we use another image, we need to change the image_publisher, image_offer, image_sku, image_version and also 
  # potentially the ansible playbook to match the new image
  image_publisher = "Canonical"
  image_offer     = "ubuntu-26_04-lts"
  image_sku       = "server"
  image_version   = "latest"

  location = var.location
  vm_size  = var.vm_size


  # Target destination in Azure Compute Gallery
  shared_image_gallery_destination {
    resource_group      = "dockploy-rg"
    gallery_name        = "dockploy_image_gallery"
    image_name          = "dockploy_ubuntu_2604_lts"
    image_version       = var.image_version
    replication_regions = ["polandcentral"]
  }
}

build {
  sources = ["source.azure-arm.dockploy"]

  provisioner "shell" {
    inline = [
      "sudo apt-get update",
      "sudo apt-get install -y ansible"
    ]
  }

  provisioner "ansible-local" {
    playbook_dir  = "${path.root}/../ansible"
    playbook_file = "${path.root}/../ansible/playbook.yaml"
  }
}