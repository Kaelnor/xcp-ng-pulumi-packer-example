import pulumi
import pulumi_xenorchestra as xoa


config = pulumi.Config()


def metadata_apply(instance_id: str, hostname: str) -> str:
    """Generate meta-data content"""

    content = f"""#cloud-config
instance-id: {instance_id}
local-hostname: {hostname}
network:
  version: 2
  renderer: networkd
  ethernets:
    enX0:
      dhcp4: no
      dhcp6: no
      addresses:
        - 10.10.20.2/24
      routes:
        - to: default
          via: 10.10.20.254
      nameservers:
        addresses:
          - 8.8.8.8
          - 1.1.1.1
"""
    return content


def userdata_apply(hostname: str, domain: str, hashed_password: str) -> str:
    """Generate user-data content"""

    content = f"""#cloud-config
hostname: {hostname}
fqdn: {hostname}.{domain}
create_hostname_file: true
manage_etc_hosts: localhost

disable_root: true
ssh_pwauth: false
ssh_deletekeys: true

users:
- name: initialuser
  groups: sudo,adm,dip,lxd,plugdev,cdrom
  shell: /bin/bash
  hashed_passwd: "{hashed_password}"
  lock_passwd: false

keyboard:
  layout: us

package_update: true
package_upgrade: true

random_seed:
  file: /dev/urandom
  command: ["pollinate", "--server=https://entropy.ubuntu.com/"]
  command_required: false

timezone: Europe/Paris
"""
    return content


# Get secrets from the encrypted pulumi config
# You can generate a hash with mkpasswd --method=yescrypt
hashed_user_pwd = config.require_secret("defaultLinuxPassword_yescrypt")

# Declare local configuration for this VM
hostname = "pulumi-ubuntu2404"
domain = "internal.domain"
vm_name = f"{hostname}.{domain}"

# Use the provider functions to get access to already existing resources in XO
pool = xoa.get_xoa_pool(name_label="XCP-Pool-1")
template = xoa.get_xoa_template(
    name_label="ubuntu-24.04.2-packer-gold", pool_id=pool.id
)
sr = xoa.get_xoa_storage_repository(name_label="SR-PROD-1")
vif_network = xoa.get_xoa_network(name_label="vlan100/admin")

# Do some plumbing between pulumi Inputs and Outputs to generate
# cloud-init configs.
# Here metadata doesn't use any pulumi Output, only local vars
# to this file so we can build it directly.
metadata = metadata_apply(hostname=hostname, instance_id=vm_name)
userdata = pulumi.Output.all(
    hostname=hostname, domain=domain, hashed_password=hashed_user_pwd
).apply(lambda args: userdata_apply(**args))


# Instantiate the actual VM using everything above.
vm = xoa.Vm(
    resource_name=vm_name,
    name_label=vm_name,
    name_description="Ubuntu 24.04 example deployed with pulumi",
    tags=["pulumi", "ubuntu"],
    cpus=2,
    memory_min=4 * 1024 * 1024 * 1024,
    memory_max=4 * 1024 * 1024 * 1024,
    template=template.id,
    cloud_config=userdata,
    cloud_network_config=metadata,
    destroy_cloud_config_vdi_after_boot=True,
    disks=[
        xoa.VmDiskArgs(name_label="disk1", size=20 * 1024 * 1024 * 1024, sr_id=sr.id),
    ],
    networks=[
        xoa.VmNetworkArgs(
            network_id=vif_network.id,
        ),
    ],
    power_state="Running",
    hvm_boot_firmware="uefi",
)

pulumi.export("vm_id", vm.id)
