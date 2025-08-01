packer {
  required_plugins {
    xenserver = {
      version = ">= v0.7.4"
      # This is not the true url but packer expects this format ¯\_(ツ)_/¯
      source = "github.com/vatesfr/xenserver"
    }
  }
}

# The ubuntu_version value determines what Ubuntu iso URL and sha256 hash we lookup. Updating
# this will allow a new version to be pulled in.
data "null" "ubuntu_version" {
  input = "24.04.2"
}

locals {
  timestamp      = regex_replace(timestamp(), "[- TZ:]", "")
  ubuntu_version = data.null.ubuntu_version.output

  # Update this map depending on the templates names available on your Xen server.
  ubuntu_template_name = {
    "24.04.2" = "Ubuntu Noble Numbat 24.04 (preview)"
  }
}

# TODO(ddelnano): Update this to use a local once https://github.com/hashicorp/packer/issues/11011
# is fixed.
data "http" "ubuntu_sha_and_release" {
  url = "https://releases.ubuntu.com/${data.null.ubuntu_version.output}/SHA256SUMS"
}

local "ubuntu_sha256" {
  expression = regex("([A-Za-z0-9]+)[\\s\\*]+ubuntu-.*server", data.http.ubuntu_sha_and_release.body)
}

variable "remote_host" {
  type        = string
  description = "The ip or fqdn of your XenServer. This will be pulled from the env var 'PKR_VAR_remote_host'"
  sensitive   = true
  default     = null
}

variable "remote_password" {
  type        = string
  description = "The password used to interact with your XenServer. This will be pulled from the env var 'PKR_VAR_remote_password'"
  sensitive   = true
  default     = null
}

variable "remote_username" {
  type        = string
  description = "The username used to interact with your XenServer. This will be pulled from the env var 'PKR_VAR_remote_username'"
  sensitive   = true
  default     = null
}

variable "sr_iso_name" {
  type        = string
  description = "The name of the SR packer will use to store the installation ISO"
  default     = null
}

variable "sr_name" {
  type        = string
  description = "The name of the SR packer will use to create the VM"
  default     = ""
}

variable "ssh_username" {
  type        = string
  description = "Guest OS user to connect to to validate the template creation"
  default     = null
}

variable "ssh_password" {
  type        = string
  description = "The password for the guest user to validate the template creation"
  sensitive   = true
  default     = null
}

source "xenserver-iso" "ubuntu-2404" {
  iso_checksum = "sha256:${local.ubuntu_sha256.0}"
  iso_url      = "https://releases.ubuntu.com/${local.ubuntu_version}/ubuntu-${local.ubuntu_version}-live-server-amd64.iso"

  sr_name         = var.sr_name
  sr_iso_name     = var.sr_iso_name
  remote_host     = var.remote_host
  remote_password = var.remote_password
  remote_username = var.remote_username

  clone_template  = local.ubuntu_template_name[data.null.ubuntu_version.output]
  vm_name         = "ubuntu-${data.null.ubuntu_version.output}-packer-gold"
  vm_description  = "Built at ${local.timestamp}"
  vm_tags         = ["packer", "template", "ubuntu"]
  vm_memory       = 2048
  disk_name       = "disk1"
  disk_size       = 16384
  vcpus_max       = 1
  vcpus_atstartup = 1
  firmware        = "uefi"

  network_names = [
    "vlan100/admin"
  ]

  boot_command = [
    "c<wait5>",
    "set gfxpayload=keep<enter>",
    "linux /casper/vmlinuz autoinstall ---<enter>",
    "initrd /casper/initrd<enter>",
    "boot<enter>"
  ]
  # We pass the initial cloud-init config as cd_files
  cd_files = [
    "packer/ubuntu/data/ubuntu-2404/meta-data",
    "packer/ubuntu/data/ubuntu-2404/user-data"
  ]

  # The xenserver plugin needs to SSH in to the new VM, so we give it
  # the information to do so
  ssh_username           = var.ssh_username
  ssh_password           = var.ssh_password
  ssh_wait_timeout       = "3600s"
  ssh_handshake_attempts = 10

  # tools are installed from cloud-init autoconfig at first boot
  tools_iso_name  = ""
  install_timeout = "30m"
  ip_getter       = "tools"

  # Don't download templates locally when done
  output_directory = null
  format = "none"
  # keep_vm: always, never or on_success.
  # This will configure whether packer will remove the VM (=template)
  # from the XCP host when done. So, on_success means that we keep the template
  # in the XCP library if the build is successful.
  keep_vm = "on_success"
}

build {
  sources = ["xenserver-iso.ubuntu-2404"]

  # Things to do on the new VM once it's past first reboot:

  # Wait for cloud-init to finish everything. We need to do this as a
  # packer provisioner to prevent packer-plugin-xenserver from shutting
  # the VM down before all cloud-init processing is complete.
  # Then reset cloud-init to be able to cleanly clone the template as fresh VMs
  # with new cloud-init configs.
  #
  # Note that this requires the initial guest user to call these sudo commands
  # password-less. See the user-data config for this.
  provisioner "shell" {
    inline = [
      "sudo cloud-init status --wait",
      "sudo cloud-init clean --logs --machine-id"
    ]
    pause_before = "30s"
    valid_exit_codes = [0, 2]
  }
}
