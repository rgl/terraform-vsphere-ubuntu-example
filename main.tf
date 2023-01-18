# see https://github.com/hashicorp/terraform
terraform {
  required_version = "1.3.7"
  required_providers {
    # see https://registry.terraform.io/providers/hashicorp/random
    random = {
      source  = "hashicorp/random"
      version = "3.4.3"
    }
    # see https://registry.terraform.io/providers/hashicorp/template
    template = {
      source  = "hashicorp/template"
      version = "2.2.0"
    }
    # see https://registry.terraform.io/providers/hashicorp/vsphere
    # see https://github.com/hashicorp/terraform-provider-vsphere
    vsphere = {
      source  = "hashicorp/vsphere"
      version = "2.2.0"
    }
  }
}

variable "vm_hostname_prefix" {
  default = "example"
}

variable "vm_count" {
  description = "number of VMs to create"
  type = number
  default = 1
  validation {
    condition = var.vm_count >= 1
    error_message = "Must be 1 or more."
  }
}

variable "vm_cpu" {
  description = "number of CPUs per VM"
  type = number
  default = 2
  validation {
    condition = var.vm_cpu >= 1
    error_message = "Must be 1 or more."
  }
}

variable "vm_memory" {
  description = "amount of memory [GiB] per VM"
  type = number
  default = 1
  validation {
    condition = var.vm_memory >= 1
    error_message = "Must be 1 or more."
  }
}

variable "vm_disk_os_size" {
  description = "minimum size of the OS disk [GiB]"
  type = number
  default = 10
  validation {
    condition = var.vm_disk_os_size >= 1
    error_message = "Must be 1 or more."
  }
}

variable "vm_disk_data_size" {
  description = "size of the DATA disk [GiB]"
  type = number
  default = 1
  validation {
    condition = var.vm_disk_data_size >= 1
    error_message = "Must be 1 or more."
  }
}

variable "vsphere_user" {
  default = "administrator@vsphere.local"
}

variable "vsphere_password" {
  default = "password"
  sensitive = true
}

variable "vsphere_server" {
  default = "vsphere.local"
}

variable "vsphere_datacenter" {
  default = "Datacenter"
}

variable "vsphere_compute_cluster" {
  default = "Cluster"
}

variable "vsphere_network" {
  default = "VM Network"
}

variable "vsphere_datastore" {
  default = "Datastore"
}

variable "vsphere_folder" {
  default = "example"
}

variable "vsphere_ubuntu_template" {
  default = "vagrant-templates/ubuntu-22.04-amd64-vsphere"
}

variable "prefix" {
  default = "terraform_ubuntu_example"
}

provider "vsphere" {
  user = var.vsphere_user
  password = var.vsphere_password
  vsphere_server = var.vsphere_server
  allow_unverified_ssl = true
}

data "vsphere_datacenter" "datacenter" {
  name = var.vsphere_datacenter
}

data "vsphere_compute_cluster" "compute_cluster" {
  name = var.vsphere_compute_cluster
  datacenter_id = data.vsphere_datacenter.datacenter.id
}

data "vsphere_datastore" "datastore" {
  name = var.vsphere_datastore
  datacenter_id = data.vsphere_datacenter.datacenter.id
}

data "vsphere_network" "network" {
  name = var.vsphere_network
  datacenter_id = data.vsphere_datacenter.datacenter.id
}

data "vsphere_virtual_machine" "ubuntu_template" {
  name = var.vsphere_ubuntu_template
  datacenter_id = data.vsphere_datacenter.datacenter.id
}

# a cloud-init.
# see journactl -u cloud-init
# see /run/cloud-init/*.log
# see less /usr/share/doc/cloud-init/examples/cloud-config.txt.gz
# see https://cloudinit.readthedocs.io/en/latest/topics/examples.html#disk-setup
# see https://www.terraform.io/docs/providers/template/d/cloudinit_config.html
# see https://www.terraform.io/docs/configuration/expressions.html#string-literals
data "template_cloudinit_config" "example" {
  count = var.vm_count
  gzip = true
  base64_encode = true
  part {
    content_type = "text/cloud-config"
    content = <<-EOF
      #cloud-config
      hostname: ${var.vm_hostname_prefix}${count.index}
      users:
        - name: vagrant
          passwd: '$6$rounds=4096$NQ.EmIrGxn$rTvGsI3WIsix9TjWaDfKrt9tm3aa7SX7pzB.PSjbwtLbsplk1HsVzIrZbXwQNce6wmeJXhCq9YFJHDx9bXFHH.'
          lock_passwd: false
          ssh-authorized-keys:
            - ${file("~/.ssh/id_rsa.pub")}
      disk_setup:
        /dev/sdb:
          table_type: mbr
          layout:
            - [100, 83]
          overwrite: false
      fs_setup:
        - label: data
          device: /dev/sdb1
          filesystem: ext4
          overwrite: false
      mounts:
        - [/dev/sdb1, /data, ext4, 'defaults,discard,nofail', '0', '2']
      runcmd:
        - sed -i '/vagrant insecure public key/d' /home/vagrant/.ssh/authorized_keys
        # make sure the vagrant account is not expired.
        # NB this is needed when the base image expires the vagrant account.
        - usermod --expiredate '' vagrant
      EOF
  }
}

resource "vsphere_folder" "folder" {
  path = var.vsphere_folder
  type = "vm"
  datacenter_id = data.vsphere_datacenter.datacenter.id
}

# see https://www.terraform.io/docs/providers/vsphere/r/virtual_machine.html
resource "vsphere_virtual_machine" "example" {
  count = var.vm_count
  folder = vsphere_folder.folder.path
  name = "${var.prefix}${count.index}"
  guest_id = data.vsphere_virtual_machine.ubuntu_template.guest_id
  firmware = data.vsphere_virtual_machine.ubuntu_template.firmware
  num_cpus = var.vm_cpu
  num_cores_per_socket = var.vm_cpu
  memory = var.vm_memory*1024
  enable_disk_uuid = true # NB the VM must have disk.EnableUUID=1 for, e.g., k8s persistent storage.
  resource_pool_id = data.vsphere_compute_cluster.compute_cluster.resource_pool_id
  datastore_id = data.vsphere_datastore.datastore.id
  scsi_type = data.vsphere_virtual_machine.ubuntu_template.scsi_type
  disk {
    unit_number = 0
    label = "os"
    size = max(data.vsphere_virtual_machine.ubuntu_template.disks.0.size, var.vm_disk_os_size)
    eagerly_scrub = data.vsphere_virtual_machine.ubuntu_template.disks.0.eagerly_scrub
    thin_provisioned = data.vsphere_virtual_machine.ubuntu_template.disks.0.thin_provisioned
  }
  disk {
    unit_number = 1
    label = "data"
    size = var.vm_disk_data_size # [GiB]
    eagerly_scrub = data.vsphere_virtual_machine.ubuntu_template.disks.0.eagerly_scrub
    thin_provisioned = data.vsphere_virtual_machine.ubuntu_template.disks.0.thin_provisioned
  }
  network_interface {
    network_id = data.vsphere_network.network.id
    adapter_type = data.vsphere_virtual_machine.ubuntu_template.network_interface_types.0
  }
  clone {
    template_uuid = data.vsphere_virtual_machine.ubuntu_template.id
  }
  # NB this extra_config data ends-up inside the VM .vmx file and will be
  #    exposed by cloud-init-vmware-guestinfo as a cloud-init datasource.
  extra_config = {
    "guestinfo.userdata" = data.template_cloudinit_config.example[count.index].rendered
    "guestinfo.userdata.encoding" = "gzip+base64"
  }
  provisioner "remote-exec" {
    inline = [
      "id",
      "uname -a",
      "cat /etc/os-release",
      "echo \"machine-id is $(cat /etc/machine-id)\"",
      "lsblk -x KNAME -o KNAME,SIZE,TRAN,SUBSYSTEMS,FSTYPE,UUID,LABEL,MODEL,SERIAL",
      "mount | grep ^/dev",
      "df -h",
    ]
    connection {
      type = "ssh"
      user = "vagrant"
      host = self.default_ip_address
      private_key = file("~/.ssh/id_rsa")
    }
  }
}

output "ips" {
  value = vsphere_virtual_machine.example.*.default_ip_address
}
