import pulumi
import pulumi_xenorchestra as xoa

import utils.hooks as hooks
from utils.network import generate_xen_mac


config = pulumi.Config()


def metadata_apply(instance_id: str, mac_addr: str) -> str:
    """Generate meta-data content"""

    content = f"""#cloud-config
instance-id: {instance_id}

network:
  version: 2
  ethernets:
    admin:
      match:
        macaddress: "{mac_addr}"
      dhcp4: no
      dhcp6: no
      addresses:
        - 10.10.20.1/24
      routes:
        - to: 0.0.0.0/0
          via: 10.10.20.254
      nameservers:
        addresses:
          - 10.10.20.200
          - 1.1.1.1
"""
    return content


def userdata_apply(hostname: str, password: str) -> str:
    """Generate user-data content"""

    content = f"""#cloud-config
set_hostname: {hostname}
set_timezone: Europe/Paris

users:
  - name: Administrator
    passwd: "{password}"
"""
    return content


# Get secrets from the encrypted pulumi config
secret_admin_pwd = config.require_secret("defaultWindowsPassword_clear")

# Declare local configuration for this VM
vm_name = "pulumi-win2022.internal.domain"
# Hostname of the guest, will be truncated to 15 chars by Windows
hostname = "pulumi-w2022"

# Use the provider functions to get access to already existing resources in XO
pool = xoa.get_xoa_pool(name_label="XCP-Pool-1")
template = xoa.get_xoa_template(
    name_label="windows-server-2022-packer-gold", pool_id=pool.id
)
sr = xoa.get_xoa_storage_repository(name_label="SR-PROD-1")
vif = {
    "network": xoa.get_xoa_network(name_label="vlan100/admin"),
    "mac_address": generate_xen_mac(name=f"{vm_name}-vif-admin"),
}

# Do some plumbing between pulumi Inputs and Outputs to generate
# cloud-init configs.
metadata = pulumi.Output.all(instance_id=vm_name, mac_addr=vif["mac_address"]).apply(
    lambda args: metadata_apply(**args)
)
userdata = pulumi.Output.all(hostname=hostname, password=secret_admin_pwd).apply(
    lambda args: userdata_apply(**args)
)

# Instantiate the actual VM using everything above.
# Note the hook in ResourceOptions to be able to correctly set the
# memory settings on the created VM.
vm = xoa.Vm(
    resource_name=vm_name,
    name_label=vm_name,
    name_description="Windows Server 2022 example deployed with pulumi",
    tags=["pulumi", "windows2022"],
    cpus=4,
    memory_max=8 * 1024 * 1024 * 1024,
    template=template.id,
    cloud_config=userdata,
    cloud_network_config=metadata,
    destroy_cloud_config_vdi_after_boot=True,
    disks=[
        xoa.VmDiskArgs(name_label="disk1", size=30 * 1024 * 1024 * 1024, sr_id=sr.id),
    ],
    networks=[
        xoa.VmNetworkArgs(
            network_id=vif["network"].id,
            mac_address=vif["mac_address"],
        ),
    ],
    power_state="Running",
    hvm_boot_firmware="uefi",
    opts=pulumi.ResourceOptions(
        hooks=pulumi.ResourceHookBinding(
            after_create=[hooks.set_memory_and_restart],
        ),
    ),
)

# You can export outputs to get access to them when pulumi is done creating resources
# This will get you the XCP-ng UUID of the created VM
# and the generated mac_address of the VIF.
pulumi.export("vm_id", vm.id)
pulumi.export("vm_vif_mac_address", pulumi.Output.unsecret(vif["mac_address"]))
