# Examples for packer and pulumi (python) usage on XCP-ng

**DISCLAIMER: THIS REPOSITORY IS NOT FOLLOWING ANY BEST PRACTICE IN THE USAGE OF PACKER OR PULUMI. THIS IS ONLY A SIMPLE EXAMPLE THAT MERGES DAYS OF RESEARCH AND TESTS. IT ALSO PROVIDES SOME POINTERS TO LIMITATIONS I ENCOUNTERED ALONG THE WAY AND POSSIBLE WORKAROUNDS.**

## Setup

If you are using nix flakes and direnv is in your path, you should be good to go with ```direnv allow``` after cloning this repository.

Otherwise, the prerequisites are:
  - uv
  - packer
  - pulumi >= 3.182.0 (for resource hooks support)

uv manages its own python version by default.
You can manually create the virtual environment with ```uv venv .venv && uv sync``` or use direnv to automate it if you prefer.

## Packer

Note that the xenserver plugin _must connect to the pool master_, not Xen Orchestra.

See the repository for configuration options and requirements https://github.com/vatesfr/packer-plugin-xenserver/

The packer build process described here assumes that a DHCP server is available on one of the networks attached to the VM.

Both Windows and Ubuntu templates are designed to be used with cloud-init (cloudbase-init for Windows) when deploying cloned VMs.

### Windows

Install the packer plugins

``` shell
packer init packer/windowsServer2022/win2022.pkr.hcl
```

Check the build file ```win2022.pkr.hcl``` and the variables in ```win2022.pkrvars.hcl``` to set everything to your liking.

There are also 2 files in ```packer/windowsServer2022/setup/``` used on first boot for building the template that you may want to edit:

1. ```autounattend.xml```: unattend config file used to install windows server. You can change the language, partitionning, the default Administrator password for the template, etc. See Microsoft documentation for details.

2. ```setup.ps1```: Powershell script that will enable winrm, install XenServer guest management tools and drivers, install cloudbase-init with its configuration and the sysprep config to generalize the image.

Then, you can start the build process:
``` shell
packer build --var-file packer/windowsServer2022/win2022.pkrvars.hcl packer/windowsServer2022/win2022.pkr.hcl
```

### Ubuntu

Install the packer plugins

``` shell
packer init packer/ubuntu/ubuntu-2404.pkr.hcl
```

Check the build file ```ubuntu-2404.pkr.hcl``` and the variables in ```ubuntu-2404.pkrvars.hcl``` to set everything to your liking.

There are also 2 files in ```packer/ubuntu/data/``` used on first boot for building the template that you may want to edit:

1. ```meta-data```: cloud-init meta-data configuration. This is empty because a DHCP server will provide the network configuration.

2. ```user-data```: cloud-init configuration for ubuntu autoinstall. See https://canonical-subiquity.readthedocs-hosted.com/en/latest/intro-to-autoinstall.html

Then, you can start the build process:
``` shell
packer build --var-file packer/ubuntu/ubuntu-2404.pkrvars.hcl packer/ubuntu/ubuntu-2404.pkr.hcl
```


## Pulumi

You will need to generate a new stack for pulumi to store your configuration.

``` shell
pulumi stack init
```

Then you can record the configuration options necessary for the project

``` shell
pulumi config set xenorchestra:url
pulumi config set xenorchestra:insecure
pulumi config set --secret xenorchestra:token
# The Ubuntu user password as a yescrypt hash
pulumi config set --secret defaultLinuxPassword_yescrypt
# The clear text Administrator password (due to windows/cloudbase-init limitations)
pulumi config set --secret defaultWindowsPassword_clear
```

For the provider documentation, check the following link https://www.pulumi.com/registry/packages/xenorchestra/

You will need to adapt the configurations in ```infra/win2022.py``` and ```infra/ubuntu2404.py```

Then, a ```pulumi up``` will start the deployment.

### Some considerations

  * You will see that cloud-init configs are directly set as f-strings in the code. This is done for keeping everything simple and contained but is not very clean. As a side note, pulumi has a nice cloud-init provider but it creates multipart files that cloudbase-init on Windows does not seem to support. You could probably use it with Linux cloud-init though. 

  * All interactions go through XenOrchestra's json-rpc API. We can leverage that and use the provider connection information to add custom logic.

This is helpful because of 2 limitations:

#### Generate MAC addresses before VIF creation

For Windows, cloudbase-init 1.1.6 supports the network v2 meta-data format for the NoCloud config provider (i.e. the CIDATA disk mounted by XenOrchestra at boot). However, network configuration will only work when a match on macaddress is provided for interfaces.

This behavior is not documented by cloudbase-init as far as I know.

The constraint on the macaddress matcher is understandable but problematic for our usage. Indeed, XCP will generate a mac address for VIFs when creating the VM but we need to know it before hand to reference it in the network-data for cloudbase-init.

We will use pulumi's random provider (https://www.pulumi.com/registry/packages/random/) to generate a MAC address for each interface. You can find that function in ```infra/utils/network.py```.
A great aspect of generating addresses with the provider is that pulumi will keep it linked to the lifetime of the VM in its state. Thus, the MAC address _WILL NOT_ change with subsequent ```pulumi up``` compared to a naive python randomization.

The RandomBytes resource is considered a secret in Pulumi's state.

**Notes on collisions**

I made the choice to generate addresses starting with XenSource OUI (00:16:3e) and randomize the last 3 bytes. This will give us 2^24 combinations.

If you are worried about collisions you could change the function to use LAA MACs instead, see https://en.wikipedia.org/wiki/MAC_address#Universal_vs._local_(U/L_bit)

Another possibility is adding collision checks when generating the addresses by querying XenOrchestra's API.

#### Set static memory limits at VM creation

At time of writing, the pulumi/terraform XenOrchestra provider will only set the dynamic memoryMax when creating VMs.

The consequence is that if you clone a template with 2GB of RAM and set the VM memoryMax to 8GB, you will get the following configuration and your VM will run in dynamic memory mode:
  - staticMin: 2GB
  - staticMax: 8GB
  - dynamicMin: 2GB
  - dynamicMax: 8GB

The json-rpc API allows us to set all memory settings for VMs but we have to consider how we do it:

  * **Create the VM halted and bind a hook after VM creation to set the memory settings and then start the VM.** This is a clean flow with only 1 boot but we lose destroy_cloud_config_vdi_after_boot (power_state must be set to Running for this)
    
  * **Create the VM running and bind a hook after VM creation to set the memory settings and then restart the VM.** In this case, we have to take into account that cloud-init runs on first boot and wait a safe amount of time before doing a "set and restart".

I chose the second option but both can work. The hook can be found in ```infra/utils/hooks.py```.

## Thanks and sources

Thanks to everyone working on the providers or sharing their experience on the matter.

- https://xcp-ng.org/blog/2024/02/22/using-packer-with-xcp-ng/
- https://github.com/mtcoffee/xcp-ng-packer-examples
- https://mickael-baron.fr/blog/2021/05/28/xo-server-websocket-jsonrcp
- https://xcp-ng.org/forum/topic/4538/xoa-json-rpc-call-basic-exemple
- https://xen-orchestra.com/blog/windows-templates-with-cloudbase-init-step-by-step-guide-best-practices/
- https://xcp-ng.org/forum/topic/10398/cloudbase-init-on-windows
- https://github.com/vatesfr/terraform-provider-xenorchestra/issues/211

And probably more that I forgot while digging through forums, blogs and various documentation.
