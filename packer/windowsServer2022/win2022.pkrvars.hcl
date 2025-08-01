remote_host = "xcp-server-01.internal.domain"
remote_username = "root"
remote_password = "CHANGE_IT"
sr_name = "SR-PROD-1"
sr_iso_name = "SR-ISOS-NFS"

# TIP: Packer can fetch the install ISO from your local machine using python -m http or miniserve for instance 
iso = "http://127.0.0.1:8000/Win_Server_CORE_2022_64Bit_English_June2025.ISO"
iso_checksum = "sha256:f47ddc199a02f00655ff5ddd4e0a249419b7cd92f20eba021bbe0a9b1f4628f5"

template_name = "windows-server-2022-packer-gold"
template_description = "Packer Template for Windows Server 2022"
template_cpu = "2"
template_ram = "2048"   # in MB
template_disk = "20480" # in MB
template_networks = ["vlan100/admin"]
template_tags = ["windows", "packer", "template"]

# Temporary administrator account for configuration and update tasks
winrm_username = "administrator"
winrm_password = "S3cret!"
