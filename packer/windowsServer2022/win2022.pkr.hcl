packer {
  required_plugins {
    xenserver = {
      version = ">= v0.7.4"
      source  = "github.com/ddelnano/xenserver"
    }
    windows-update = {
      version = "0.16.10"
      source  = "github.com/rgl/windows-update"
    }
  }
}

variable "remote_host" {
  type        = string
  description = "The ip or fqdn of your XCP-ng server. It must be the pool master !"
  sensitive   = true
}

variable "remote_username" {
  type        = string
  description = "The username used to interact with your XCP-ng server."
  sensitive   = true
}

variable "remote_password" {
  type        = string
  description = "The password used to interact with your XCP-ng server."
  sensitive   = true
}

variable "sr_iso_name" {
  type        = string
  description = "The ISO-SR that packer will use to store the install media."
}

variable "sr_name" {
  type        = string
  description = "The name of the SR to packer will use to create VMs and store the final template."
}

variable "iso" {
  type        = string
  description = "The local/http path to your install iso."
}

variable "iso_checksum" {
  type        = string
  description = "The checksum of the iso file, format sha256:{CSUM}"
}

variable "template_name" {
  type        = string
  description = "Name of the VM and final template."
}

variable "template_description" {
  type        = string
  description = "Description of the VM and final template."
}

variable "template_cpu" {
  type        = string
  description = "Template vCPU count."
}

variable "template_ram" {
  type        = string
  description = "Template RAM in MB."
}

variable "template_disk" {
  type        = string
  description = "Template disk size in MB."
}

variable "template_networks" {
  type        = list(string)
  description = "List of network names to attach to the VM."
}

variable "template_tags" {
  type        = list(string)
  description = "Tags to associate to the template."
}


variable "winrm_username" {
  type        = string
  description = "Winrm username."
}

variable "winrm_password" {
  type        = string
  description = "Winrm password."
  sensitive   = true
}

source "xenserver-iso" "win2022" {
  iso_checksum = var.iso_checksum
  iso_url      = var.iso

  sr_iso_name    = var.sr_iso_name
  sr_name        = var.sr_name

  # We don't need this. Tools will be installed via script.
  tools_iso_name = ""

  remote_host     = var.remote_host
  remote_password = var.remote_password
  remote_username = var.remote_username

  ip_getter = "tools"

  # Depending on how fast or slow your VM boots, this can be a bit finicky.
  boot_wait = "1s"
  boot_command = [
    "<enter><wait><enter><wait>",
    "<enter><wait><enter><wait>",
    "<enter><wait><enter><wait>",
    "<enter><wait><enter><wait>",
  ]

  cd_files = [
    "packer/windowsServer2022/setup/autounattend.xml",
    "packer/windowsServer2022/setup/setup.ps1"
  ]

  # Viridian must be true
  platform_args = {
    viridian         = true
    nx               = true
    pae              = true
    apic             = true
    timeoffset       = 0
    acpi             = true
    cores-per-socket = 1
  }

  clone_template  = "Windows Server 2022 (64-bit)"
  firmware        = "uefi"
  vm_name         = var.template_name
  vm_description  = var.template_description
  vcpus_max       = var.template_cpu
  vcpus_atstartup = var.template_cpu
  vm_memory       = var.template_ram
  network_names   = var.template_networks
  disk_size       = var.template_disk
  disk_name       = "${var.template_name}-disk"
  vm_tags         = var.template_tags

  communicator   = "winrm"
  ssh_username   = "N/A" # this is hard coded into the packer plugin so it must be set to anything
  winrm_username = var.winrm_username
  winrm_password = var.winrm_password

  # Keep the final template on xcp-ng and don't download it locally  
  keep_vm          = "on_success"
  output_directory = null
  format           = "none"
}

build {
  sources = ["xenserver-iso.win2022"]

  # You can apply windows updates when creating the template by enabling the provisioner
  # Go take a coffee or two ... or ten, because this will take a while ...
  #provisioner "windows-update" {
  #}

  # Run sysprep as a last step before templating. We tell sysprep that we will use the specified Unattend.xml
  # on first boot when we will provision VMs using the template.
  provisioner "windows-shell" {
    inline = ["C:\\Windows\\System32\\Sysprep\\sysprep.exe /generalize /oobe '/unattend:C:\\Program Files\\Cloudbase Solutions\\Cloudbase-Init\\conf\\Unattend.xml'"]
  }
}
