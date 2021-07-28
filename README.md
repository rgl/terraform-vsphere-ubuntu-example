# Usage (Ubuntu 20.04 host)

Install the [Ubuntu 20.04 VM template](https://github.com/rgl/ubuntu-vagrant).

Install Terraform and govc (Ubuntu):

```bash
wget https://releases.hashicorp.com/terraform/0.12.28/terraform_0.12.28_linux_amd64.zip
unzip terraform_0.12.28_linux_amd64.zip
sudo install terraform /usr/local/bin
wget https://github.com/vmware/govmomi/releases/download/v0.23.0/govc_linux_amd64.gz
gunzip govc_linux_amd64.gz
sudo install govc_linux_amd64 /usr/local/bin/govc
```

Install Terraform and govc (Windows):

```bash
choco install -y --version 0.12.28 terraform
choco install -y --version 0.23.0 govc
```

Save your environment details as a script that sets the terraform variables from environment variables, e.g.:

```bash
cat >secrets.sh <<'EOF'
export TF_VAR_vsphere_user='administrator@vsphere.local'
export TF_VAR_vsphere_password='password'
export TF_VAR_vsphere_server='vsphere.local'
export TF_VAR_vsphere_datacenter='Datacenter'
export TF_VAR_vsphere_compute_cluster='Cluster'
export TF_VAR_vsphere_datastore='Datastore'
export TF_VAR_vsphere_network='VM Network'
export TF_VAR_vsphere_ubuntu_template='vagrant-templates/ubuntu-20.04-amd64-vsphere'
export GOVC_INSECURE='1'
export GOVC_URL="https://$TF_VAR_vsphere_server/sdk"
export GOVC_USERNAME="$TF_VAR_vsphere_user"
export GOVC_PASSWORD="$TF_VAR_vsphere_password"
EOF
```

**NB** You could also add these variables definitions into the `terraform.tfvars` file, but I find the environment variables more versatile as they can also be used from other tools, like govc.

Launch this example:

```bash
source secrets.sh
# see https://github.com/vmware/govmomi/blob/master/govc/USAGE.md
govc version
govc about
govc datacenter.info # list datacenters
govc find # find all managed objects
terraform init
terraform plan -out=tfplan
time terraform apply tfplan
ssh-keygen -f ~/.ssh/known_hosts -R "$(terraform output ip)"
ssh "vagrant@$(terraform output ip)"
time terraform destroy -force
```
