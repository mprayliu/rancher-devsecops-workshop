#! /bin/bash -e

cat _banner.txt
source _awsls_functions.sh
echo
echo "Welcome to SUSE Rancher DevSecOps Hands-on Lab on AWS Lightsail ..."
echo "This script will help you to provision VMs on AWS Lightsail to get started to run your lab exercise."
echo
echo ""

# Supported AWS Lighsail Regions: 
# https://lightsail.aws.amazon.com/ls/docs/en_us/articles/understanding-regions-and-availability-zones-in-amazon-lightsail
title="Select Your Preferred AWS Environment to run your lab:"
options=("Tokyo" "Seoul" "Singapore" "Sydney" "Mumbai")
echo "$title"
PS3="$prompt "
select opt in "${options[@]}" "Quit"; do 
  case "$REPLY" in
  1) echo "You picked $opt "; export AWS_REGION=ap-northeast-1; export AWSLS_VM_SIZE_SUFFIX=_2_0; break;;
  2) echo "You picked $opt "; export AWS_REGION=ap-northeast-2; export AWSLS_VM_SIZE_SUFFIX=_2_0; break;;
  3) echo "You picked $opt "; export AWS_REGION=ap-southeast-1; export AWSLS_VM_SIZE_SUFFIX=_2_0; break;;
  4) echo "You picked $opt "; export AWS_REGION=ap-southeast-2; export AWSLS_VM_SIZE_SUFFIX=_2_2; break;;
  5) echo "You picked $opt "; export AWS_REGION=ap-south-1;     export AWSLS_VM_SIZE_SUFFIX=_2_1; break;;
  $((${#options[@]}+1))) echo "Aborted. Bye!!"; break;;
  *) echo "Invalid choice. Please try another one.";continue;;
  esac
done

echo "export AWS_REGION=${AWS_REGION}" > mylab_aws_region.sh
export AWS_AZ=${AWS_REGION}a
# Instance Sizes
# medium = 4GB RAM; large = 8GB RAM
# aws lightsail get-bundles
export AWS_SIZE_MEDIUM="medium${AWSLS_VM_SIZE_SUFFIX}"
export AWS_SIZE_LARGE="large${AWSLS_VM_SIZE_SUFFIX}"

echo "Provisioning VM in your AWS Lightsail region $AWS_REGION as lab environment ..."
create-vm demo-rancher $AWS_SIZE_MEDIUM
create-vm demo-harbor  $AWS_SIZE_MEDIUM
create-vm demo-devsecops-m1 $AWS_SIZE_MEDIUM
create-vm demo-devsecops-w1 $AWS_SIZE_LARGE
create-vm demo-devsecops-w2 $AWS_SIZE_LARGE
create-vm demo-devsecops-w3 $AWS_SIZE_LARGE
create-vm demo-cluster1 $AWS_SIZE_MEDIUM
create-vm demo-cluster2 $AWS_SIZE_MEDIUM

# wait until all VMs are running
while list-vm | grep -q 'pending'
do
  echo "Wait until all VMs are up and running..."
  list-vm
  sleep 10
done
echo "All VMs are up and running now..."
list-vm

echo "Configure firewall rules for the VMs on the lab"
open-vm-standard-network-port demo-rancher
open-vm-specific-network-port demo-rancher 80 80
open-vm-specific-network-port demo-rancher 443 443
open-vm-standard-network-port demo-harbor
open-vm-specific-network-port demo-harbor 30443 30443
open-vm-standard-network-port demo-devsecops-m1
open-vm-standard-network-port demo-devsecops-w1
open-vm-standard-network-port demo-devsecops-w2
open-vm-standard-network-port demo-devsecops-w3
open-vm-standard-network-port demo-cluster1
open-vm-standard-network-port demo-cluster2

echo "Capture all the VM IP addresses into a file"
cat mylab_aws_region.sh > mylab_vm_list.txt
list-vm >> mylab_vm_list.txt

echo "Download default AWS lightsail SSH key pair from your region $AWS_REGION"
download-key-pair

# build mylab-ssh-config file
touch mylab-ssh-config
echo "Host *" > mylab-ssh-config
echo "  StrictHostKeyChecking no" >> mylab-ssh-config
echo >> mylab-ssh-config
for vm in rancher harbor devsecops-m1 devsecops-w1 devsecops-w2 devsecops-w3 cluster1 cluster2; do
  VM_IP=`cat mylab_vm_list.txt | grep demo-$vm | cut -d '|' -f 4 | xargs`
  echo "Host $vm" >> mylab-ssh-config
  echo "  HostName $VM_IP" >> mylab-ssh-config
  echo "  User ec2-user" >> mylab-ssh-config
  echo "  IdentityFile ~/.ssh/mylab.key" >> mylab-ssh-config
  echo >> mylab-ssh-config
done
chmod 600 mylab-ssh-config

export SSH_OPTS="-o StrictHostKeyChecking=no"
for vm in rancher harbor; do
  VM_IP=`get-vm-public-ip demo-$vm`
  echo "SSH into demo-$vm (IP:$VM_IP) and upload files into this server ..."
  until ssh $SSH_OPTS -i mylab.key ec2-user@$VM_IP true; do
      sleep 5
  done
  scp $SSH_OPTS -i mylab.key mylab.key ec2-user@$VM_IP:~/.ssh/
  scp $SSH_OPTS -i mylab.key mylab-ssh-config ec2-user@$VM_IP:~/.ssh/config
  scp $SSH_OPTS -i mylab.key ../setup/$vm/*.*  ec2-user@$VM_IP:~/
done 

# upload files to be deployed onto devsecops cluster
echo "Upload files to be executed onto devsecops cluster into harbor instance ..."
HARBOR_IP=`get-vm-public-ip demo-harbor`
ssh $SSH_OPTS -i mylab.key ec2-user@$HARBOR_IP mkdir -p devsecops/{jenkins,sonarqube,anchore}
scp $SSH_OPTS -i mylab.key ../setup/jenkins/*.* ec2-user@$HARBOR_IP:~/devsecops/jenkins
scp $SSH_OPTS -i mylab.key ../setup/sonarqube/*.* ec2-user@$HARBOR_IP:~/devsecops/sonarqube
scp $SSH_OPTS -i mylab.key ../setup/anchore/*.* ec2-user@$HARBOR_IP:~/devsecops/anchore


# write ssh file for easy access
echo "Generating shortcut ssh files for VM access..."
for vm in rancher harbor devsecops-m1 devsecops-w1 devsecops-w2 devsecops-w3 cluster1 cluster2; do
  VM_IP=`cat mylab_vm_list.txt | grep demo-$vm | cut -d '|' -f 4 | xargs`
  echo "ssh -o StrictHostKeyChecking=no -i mylab.key ec2-user@$VM_IP" > ssh-mylab-$vm.sh
  chmod +x ssh-mylab-$vm.sh
done


# install rancher now?
function install_rancher() {
  RANCHER_IP=`cat mylab_vm_list.txt | grep demo-rancher | cut -d '|' -f 4 | xargs`
  ssh -o StrictHostKeyChecking=no -i mylab.key ec2-user@$RANCHER_IP sh 99-one-step-install-rancher.sh
}
read -p "Do you want to install Rancher now? (y/n)?" choice
case "$choice" in
  y|Y ) install_rancher;;
  n|N ) echo "You can ssh into Rancher instance and follow the instruction guide to install Rancher.";;
  *   ) echo "Please enter y or n.";;
esac

# # install harbor now?
# function install_harbor() {
#   HARBOR_IP=`cat mylab_vm_list.txt | grep demo-harbor | cut -d '|' -f 4 | xargs`
#   ssh -o StrictHostKeyChecking=no -i mylab.key ec2-user@$HARBOR_IP sh 99-one-step-install-harbor.sh
# }
# read -p "Do you want to install Harbor now? (y/n)?" choice
# case "$choice" in
#   y|Y ) install_harbor;;
#   n|N ) echo "You can ssh into Harbor instance and follow the instruction guide to install Harbor.";;
#   *   ) echo "Please enter y or n.";;
# esac



echo 
echo
echo "Your lab environment on AWS Lightsail $AWS_REGION is ready. "
echo
echo "Here's the list of VMs running in your lab environment (See file: mylab_vm_list.txt):"
list-vm
echo
echo "To SSH into the VM on the lab, you can run this command:"
echo
echo "./ssh-mylab-<vm>.sh"
echo
echo "Please continue the lab exercises according to our guide. Thank you! Have a nice day!"

