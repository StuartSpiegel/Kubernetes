if [ "$EUID" -ne 0 ]
  then echo "Please run as root"
  exit
fi

# Check internet connectivity
# dhclient (assign IP)
ping -c 1 google.com
ping -c 1 -q google.com >&/dev/null; echo $?

yum update
yum install -y yum-utils device-mapper-persistent-data lvm2
yum install docker -y
systemctl start docker
systemctl enable docker
systemctl status docker

yum install kubernetes 
yum install -y kubelet kubeadm kubectl
systemctl enable kubelet
systemctl start kubelet 

# Assuming on master node
hostnamectl set-hostname master-node

# sudo vi /etc/hosts - MODIFY for your HOSTS
echo "192.168.1.10 master.domain.com master-node" >> /etc/hosts
echo "192.168.1.20 node1. domain.com node1 worker-node" >> /etc/hosts

# Configure the Firewall
sudo firewall-cmd --permanent --add-port=6443/tcp
sudo firewall-cmd --permanent --add-port=2379-2380/tcp
sudo firewall-cmd --permanent --add-port=10250/tcp
sudo firewall-cmd --permanent --add-port=10251/tcp
sudo firewall-cmd --permanent --add-port=10252/tcp
sudo firewall-cmd --permanent --add-port=10255/tcp
sudo firewall-cmd --reload

# update IP tables settings
cat <<EOF > /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
EOF
sysctl --system

# Disable SE-linux
sudo setenforce 0
sudo sed -i 's/^SELINUX=enforcing$/SELINUX=permissive/' /etc/selinux/config

# disable swap
sudo sed -i '/swap/d' /etc/fstab
sudo swapoff -a

# FROM master node -- initialized above
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

# View Up-Status
kubectl cluster-info
kubectl get nodes

# Join the worker nodes (data nodes)
# sudo kubeadm join k8smaster.first.net:6443 --token ... / --command should exist as output of last command

# Node Status- "Not Ready" must call Container Network Interface or networking add-on
kubectl get nodes

# Use Custom Resource Definitions (CRD) to install artifacts for ECK
kubectl create -f https://download.elastic.co/downloads/eck/2.3.0/crds.yaml

#Install the ECK operator
kubectl apply -f https://download.elastic.co/downloads/eck/2.3.0/operator.yaml

# Monitor the operators logs
kubectl -n elastic-system logs -f statefulset.apps/elastic-operator

