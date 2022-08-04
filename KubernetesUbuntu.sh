# Prerequisities - Set the hostnames of the worker nodes and master nodes
# Login to master node and set the hostnames
# sudo hostnamectl set-hostname "k8s-cluster.first.net"

# exec bash

# sudo hostnamectl set-hostname "k8sworker1.first.net"
# sudo hostnamectl set-hostname "k8sworker2.first.net"   

# exec bash

# append to /etc/hosts on each node
# 192.168.1.172
# 192.168.1.173
# 192.168.1.174

###########################################################################################
# Modify for your HOSTS
echo "192.168.1.172 K8smaster.first.net k8smaster" >> /etc/hosts
echo "192.168.1.173 K8worker1.first.net k8sworker1" >> /etc/hosts
echo "192.168.1.174 K8sworker2.first.net k8sworker2" >> /etc/hosts

# Disable swapping for the kernel
sudo swapoff -a
sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

#Setup the Kernel Modules
sudo tee /etc/modules-load.d/containered.conf<<EOF
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo nodprobe br_netfilter

# Setup kernel parameters for Kubernetes
sudo tee /etc/sysctl.d/Kubernetes.conf<<EOF
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
EOF 

# Pickup /reload changes 
sudo sysctl --system

# Install Kubernetes Runtime environment - containered 
sudo apt install -y curl gnupg2 software-properties-common apt-transport-https ca-certificates
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
sudo apt update
sudo apt install -y containered.io

# Configure C-group for containered
containerd config default | sudo tee /etc/containerd/config.toml >/dev/null 2>&1
sudo sed -i 's/SystemdCgroup \= false/SystemdCgroup \= true/g' /etc/containerd/config.toml

# Restart and enable containered service
sudo systemctl restart containerd
sudo systemctl enable containerd

# Add APT repo for Kubernetes // later replace "xenial" with Jammy for Jammy Jellyifsh 22.04 LTS
curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -
sudo apt-add-repository "deb http://apt.kubernetes.io/ kubernetes-xenial main"
sudo apt update
sudo apt install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl

# Initialize our installed cluster 
sudo kubeadm init --control-plane-endpoint=K8smaster.first.net

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

# Install Calico networking add-on
curl https://projectcalico.docs.tigera.io/manifests/calico.yaml -O
kubectl apply -f calico.yaml

# verify status of Pods in Kube-system namespace
kubectl get pods -n kube-system
kubectl get nodes

### ECK INSTALL - Custom Rresource Definitions (CRD) with YML manifest #######
kubectl create -f https://download.elastic.co/downloads/eck/2.3.0/crds.yaml

# Install the ECK Operator
kubectl apply -f https://download.elastic.co/downloads/eck/2.3.0/operator.yaml

# Monitor the operator logs
kubectl -n elastic-system logs -f statefulset.apps/elastic-operator

# Deploy ECK
cat <<EOF | kubectl apply -f -
apiVersion: elasticsearch.k8s.elastic.co/v1
kind: Elasticsearch
metadata:
  name: quickstart
spec:
  version: 8.3.3
  nodeSets:
  - name: default
    count: 1
    config:
      node.store.allow_mmap: false
EOF

# Check status
kubectl get elasticsearch
kubectl get pods --selector='elasticsearch.k8s.elastic.co/cluster-name=quickstart'

# Start Cluster IP service 
kubectl get service quickstart-es-http

#GET the deafult Credentials for the HTTP endpoint
PASSWORD=$(kubectl get secret quickstart-es-elastic-user -o go-template='{{.data.elastic | base64decode}}')
echo $PASSWORD

# Check Status of ECK Cluster and CURL // and port forward 
# "-k" flag is not recommended in production : disables certificate validation. 
curl -u "elastic:$PASSWORD" -k "https://quickstart-es-http:9200"
kubectl port-forward service/quickstart-es-http 9200
curl -u "elastic:$PASSWORD" -k "https://localhost:9200"

# Deploy Kibana
cat <<EOF | kubectl apply -f -
apiVersion: kibana.k8s.elastic.co/v1
kind: Kibana
metadata:
  name: quickstart
spec:
  version: 8.3.3
  count: 1
  elasticsearchRef:
    name: quickstart
EOF

kubectl get kibana
kubectl get pod --selector='kibana.k8s.elastic.co/name=quickstart'
kubectl get service quickstart-kb-http
kubectl port-forward service/quickstart-kb-http 5601
kubectl get secret quickstart-es-elastic-user -o=jsonpath='{.data.elastic}' | base64 --decode; echo




















