# Kubernetes Cluster with Multi-Master, HAProxy and KeepAlive Loadbalancer

## We are using the following Hostnames & IP Assignments:
```
HAProxy/KeepAlive Load Balancer:
  192.168.126.100 kube-mgmt - VIP
  192.168.126.110 haproxy-lb1 - Client
  192.168.126.120 haproxy-lb2
  
Etcd/Kubernetes Master Nodes
  192.168.126.101 k8s-master-a
  192.168.126.102 k8s-master-b
  192.168.126.103 k8s-master-c
  
Kubernetes Worker Nodes
  192.168.126.104 worker-01
  192.168.126.105 worker-02
  192.168.126.106 worker-03
```


# Perform on HA/LB Servers 
Create Certs and CA
```
# wget https://pkg.cfssl.org/R1.2/cfssl_linux-amd64
# wget https://pkg.cfssl.org/R1.2/cfssljson_linux-amd64
# chmod +x cfssl*
# sudo mv cfssl_linux-amd64 /usr/local/bin/cfssl
# sudo mv cfssljson_linux-amd64 /usr/local/bin/cfssljson
# cfssl version
```

Installing kubectl
```
# curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
# chmod +x kubectl
# sudo mv kubectl /usr/local/bin
# kubectl version
```

Generating the TLS certificates

Create the certificate authority configuration file
===
```# vi ca-config.json```
```
{
  "signing": {
    "default": {
      "expiry": "8760h"
    },
    "profiles": {
      "kubernetes": {
        "usages": ["signing", "key encipherment", "server auth", "client auth"],
        "expiry": "8760h"
      }
    }
  }
}
```
Create the certificate authority signing request configuration file
```# vi ca-csr.json```
```
{
  "CN": "Kubernetes",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
  {
    "C": "CA",
    "L": "ON",
    "O": "LLACHICA",
    "OU": "LAB",
    "ST": "K8S"
  }
 ]
}
```
```# cfssl gencert -initca ca-csr.json | cfssljson -bare ca```

Create the certificate signing request configuration file
```# kubernetes-csr.json```
```
{
  "CN": "Kubernetes",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
  {
    "C": "CA",
    "L": "ON",
    "O": "LLACHICA",
    "OU": "LAB",
    "ST": "K8S"
  }
 ]
}
```
```
Generate the certificate and private key.
# cfssl gencert \
-ca=ca.pem \
-ca-key=ca-key.pem \
-config=ca-config.json \
-hostname=192.168.126.100,192.168.126.101,192.168.126.102,192.168.126.103,127.0.0.1,kubernetes.default \
-profile=kubernetes kubernetes-csr.json | \
cfssljson -bare kubernetes
```
Copy the certificate to each nodes
```
# scp ca.pem kubernetes.pem kubernetes-key.pem kadmin@k8s-master-a:~
# scp ca.pem kubernetes.pem kubernetes-key.pem kadmin@k8s-master-b:~
# scp ca.pem kubernetes.pem kubernetes-key.pem kadmin@k8s-master-c:~
# scp ca.pem kubernetes.pem kubernetes-key.pem kadmin@192.worker-01:~
# scp ca.pem kubernetes.pem kubernetes-key.pem kadmin@192.worker-02:~
# scp ca.pem kubernetes.pem kubernetes-key.pem kadmin@192.worker-03:~
```
Installing HAProxy Load Balancer
```
# sudo apt-get update && sudo apt-get upgrade -y
# apt update && apt install -y keepalived haproxy
===
# cat >> /etc/keepalived/check_apiserver.sh <<EOF
#!/bin/bash

# Check if localhost is running on port 6443
nc -z -w 1 127.0.0.1 6443 >/dev/null

# Capture the exit code
exit_code=$?

# Exit with appropriate status
if [ $exit_code -eq 0 ]; then
  exit 0  # Localhost is running on port 6443, return success
else
  exit 1  # Localhost is not running on port 6443, return failure
fi
~


EOF

chmod +x /etc/keepalived/check_apiserver.sh

===
# cat >> /etc/keepalived/keepalived.conf <<EOF
global_defs {
#       script_user keepalived_script
        enable_script_security
        script_user root
        dynamic_interfaces

}
vrrp_script chk_apiserver {
    script "/etc/keepalived/check_apiserver.sh"
    interval 5
    timeout 3
}

vrrp_instance VI_1 {
    state MASTER
    interface ens33
    virtual_router_id 51
    priority 101
    advert_int 1
    authentication {
        auth_type PASS
        auth_pass g3nius
    }
    virtual_ipaddress {
        192.168.126.100 dev ens38
    }
    track_script {
        chk_apiserver
    }
}


EOF
# systemctl enable --now keepalived
===
Configure haproxy
# cat >> /etc/haproxy/haproxy.cfg <<EOF
        frontend kubernetes
        #bind 192.168.126.100:6443
        bind *:6443
        option tcplog
        mode tcp
        default_backend kubernetes-master-nodes


        backend kubernetes-master-nodes
        mode tcp
        balance roundrobin
        option tcp-check
        server k8s-master-a 192.168.126.101:6443 check fall 3 rise 2
        server k8s-master-b 192.168.126.102:6443 check fall 3 rise 2
        server k8s-master-c 192.168.126.103:6443 check fall 3 rise 2
  EOF

# systemctl enable haproxy && systemctl restart haproxy
```
Preparing the nodes for kubeadm

Initial Setup for all master and node machines
Copy the commands below and paste them into a setup.sh file and then execute it with . setup.sh
```
# vi setup.sh
sudo apt-get remove docker docker-engine docker.io containerd runc

curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
sudo usermod -a -G docker $USER
sudo systemctl enable docker
sudo systemctl restart docker

sudo containerd config default | sudo tee /etc/containerd/config.toml
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml
systemctl restart containerd

cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter

cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

sudo sysctl --system

curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -
cat <<EOF | sudo tee /etc/apt/sources.list.d/kubernetes.list
deb https://apt.kubernetes.io/ kubernetes-xenial main
EOF

sudo apt-get update
sudo apt-get install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl

sudo swapoff -a

```
Installing and configuring Etcd on all 3 Master Nodes
```
# sudo mkdir /etc/etcd /var/lib/etcd
# sudo mv ~/ca.pem ~/kubernetes.pem ~/kubernetes-key.pem /etc/etcd
# wget https://github.com/etcd-io/etcd/releases/download/v3.4.13/etcd-v3.4.13-linux-amd64.tar.gz
# tar xvzf etcd-v3.4.13-linux-amd64.tar.gz
# sudo mv etcd-v3.4.13-linux-amd64/etcd* /usr/local/bin/
```
Create an etcd systemd unit file
```
# vi /etc/systemd/system/etcd.service
[Unit]
Description=etcd
Documentation=https://github.com/coreos


[Service]
ExecStart=/usr/local/bin/etcd \
  --name 192.168.126.101 \
  --cert-file=/etc/etcd/kubernetes.pem \
  --key-file=/etc/etcd/kubernetes-key.pem \
  --peer-cert-file=/etc/etcd/kubernetes.pem \
  --peer-key-file=/etc/etcd/kubernetes-key.pem \
  --trusted-ca-file=/etc/etcd/ca.pem \
  --peer-trusted-ca-file=/etc/etcd/ca.pem \
  --peer-client-cert-auth \
  --client-cert-auth \
  --initial-advertise-peer-urls https://192.168.126.101:2380 \
  --listen-peer-urls https://192.168.126.101:2380 \
  --listen-client-urls https://192.168.126.101:2379,http://127.0.0.1:2379 \
  --advertise-client-urls https://192.168.126.101:2379 \
  --initial-cluster-token etcd-cluster-0 \
  --initial-cluster 192.168.126.101=https://192.168.126.101:2380,192.168.126.102=https://192.168.126.102:2380,192.168.126.103=https://192.168.126.103:2380 \
  --initial-cluster-state new \
  --data-dir=/var/lib/etcd
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
```
```
# sudo systemctl daemon-reload
# sudo systemctl start etcd
# ETCDCTL_API=3 etcdctl member list
9e677e1f11447ef, started, 192.168.126.101, https://192.168.126.101:2380, https://192.168.126.101:2379, false
ccca2718255320c4, started, 192.168.126.103, https://192.168.126.103:2380, https://192.168.126.103:2379, false
f5775738eb720ba7, started, 192.168.126.102, https://192.168.126.102:2380, https://192.168.126.102:2379, false
```
Initialising the First Master Node
```
# vi config.yaml
apiVersion: kubeadm.k8s.io/v1beta3
kind: ClusterConfiguration
kubernetesVersion: v1.27.0
controlPlaneEndpoint: "192.168.126.100:6443"
etcd:
  external:
    endpoints:
      - https://192.168.126.101:2379
      - https://192.168.126.102:2379
      - https://192.168.126.103:2379
    caFile: /etc/etcd/ca.pem
    certFile: /etc/etcd/kubernetes.pem
    keyFile: /etc/etcd/kubernetes-key.pem
networking:
  podSubnet: 10.10.10.0/24
apiServer:
  certSANs:
    - "192.168.126.100"
  extraArgs:
    apiserver-count: "3"
```
```# sudo kubeadm init --config=config.yaml```

Copy the certificates to the two other masters
```
# sudo scp -r /etc/kubernetes/pki kadmin@k8s-master-b:~
# sudo scp -r /etc/kubernetes/pki kadmin@k8s-master-c:~
```
Initialising the second/Third Master Node
```
# ssh kadmin@k8s-master-b/c
# rm ~/pki/apiserver.*
# sudo mv ~/pki /etc/kubernetes/
# vi config.yaml
apiVersion: kubeadm.k8s.io/v1beta3
kind: ClusterConfiguration
kubernetesVersion: v1.27.0
controlPlaneEndpoint: "192.168.126.100:6443"
etcd:
  external:
    endpoints:
      - https://192.168.126.101:2379
      - https://192.168.126.102:2379
      - https://192.168.126.103:2379
    caFile: /etc/etcd/ca.pem
    certFile: /etc/etcd/kubernetes.pem
    keyFile: /etc/etcd/kubernetes-key.pem
networking:
  podSubnet: 10.10.10.0/24
apiServer:
  certSANs:
    - "192.168.126.100"
  extraArgs:
    apiserver-count: "3"
```
```# sudo kubeadm init --config=config.yaml```

Save the join command printed in the output after the above command
```
You can now join any number of control-plane nodes by copying certificate authorities
and service account keys on each node and then running the following as root:

  kubeadm join 192.168.126.100:6443 --token okbe1g.xda572lf27kw17ef \
        --discovery-token-ca-cert-hash sha256:7ce76ae448fe1008df3ac7238fff0126b8e7952bfe88db0b1f9ddd9d0afdccd5 \
        --control-plane

Then you can join any number of worker nodes by running the following on each as root:

kubeadm join 192.168.126.100:6443 --token okbe1g.xda572lf27kw17ef \
        --discovery-token-ca-cert-hash sha256:7ce76ae448fe1008df3ac7238fff0126b8e7952bfe88db0b1f9ddd9d0afdccd5

```

Configure kubectl on the client machine
SSH to one of the master nodes
```
# ssh kadmin@k8s-master-a
# sudo chmod +r /etc/kubernetes/admin.conf
# scp kadmin@k8s-master-a:/etc/kubernetes/admin.conf .
```
Create and configure the kubectl configuration directory.
```
# mkdir ~/.kube
# mv admin.conf ~/.kube/config
# chmod 600 ~/.kube/config
```
Go back to the SSH session and revert the permissions of the config file
```
# sudo chmod 600 /etc/kubernetes/admin.conf


Initialise the worker nodes
# kubeadm join 192.168.126.100:6443 --token okbe1g.xda572lf27kw17ef \
        --discovery-token-ca-cert-hash sha256:7ce76ae448fe1008df3ac7238fff0126b8e7952bfe88db0b1f9ddd9d0afdccd5

Test to see if you can access the Kubernetes API from the client machine

root@haproxy-lb1:~# kubectl get nodes
NAME           STATUS   ROLES           AGE    VERSION
k8s-master-a   Ready    control-plane   20d    v1.27.1
k8s-master-b   Ready    control-plane   20d    v1.27.1
k8s-master-c   Ready    control-plane   20d    v1.27.1
worker-01      Ready    <none>          5d3h   v1.27.1
worker-02      Ready    <none>          3d1h   v1.27.1

root@haproxy-lb1:~# kubectl get cs
Warning: v1 ComponentStatus is deprecated in v1.19+
NAME                 STATUS    MESSAGE             ERROR
scheduler            Healthy   ok
controller-manager   Healthy   ok
etcd-0               Healthy   {"health":"true"}
etcd-2               Healthy   {"health":"true"}
etcd-1               Healthy   {"health":"true"}


Deploying the overlay network
Deploy Calico network
kubectl --kubeconfig=/etc/kubernetes/admin.conf create -f https://docs.projectcalico.org/v3.18/manifests/calico.yaml

root@haproxy-lb1:~# kubectl get pods -n kube-system -o wide
NAME                                       READY   STATUS    RESTARTS        AGE     IP                NODE           NOMINATED NODE   READINESS GATES
calico-kube-controllers-674fff74c8-skfhj   1/1     Running   1 (3d4h ago)    5d22h   192.168.218.133   k8s-master-c   <none>           <none>
calico-node-9ljp8                          1/1     Running   0               4h55m   192.168.126.105   worker-02      <none>           <none>
calico-node-jgszs                          1/1     Running   0               4h56m   192.168.126.103   k8s-master-c   <none>           <none>
calico-node-s2bfq                          1/1     Running   0               4h55m   192.168.126.104   worker-01      <none>           <none>
calico-node-x5qfs                          1/1     Running   0               4h55m   192.168.126.101   k8s-master-a   <none>           <none>
calico-node-xklgr                          1/1     Running   0               4h55m   192.168.126.102   k8s-master-b   <none>           <none>
coredns-5d78c9869d-bcfqw                   1/1     Running   1 (3d4h ago)    5d3h    192.168.216.195   k8s-master-b   <none>           <none>
coredns-5d78c9869d-zxlbs                   1/1     Running   1 (3d4h ago)    5d3h    192.168.218.134   k8s-master-c   <none>           <none>
kube-apiserver-k8s-master-a                1/1     Running   24 (3d1h ago)   20d     192.168.126.101   k8s-master-a   <none>           <none>
kube-apiserver-k8s-master-b                1/1     Running   23 (3d4h ago)   20d     192.168.126.102   k8s-master-b   <none>           <none>
kube-apiserver-k8s-master-c                1/1     Running   17 (3d4h ago)   20d     192.168.126.103   k8s-master-c   <none>           <none>
kube-controller-manager-k8s-master-a       1/1     Running   28 (3d1h ago)   20d     192.168.126.101   k8s-master-a   <none>           <none>
kube-controller-manager-k8s-master-b       1/1     Running   31 (3d4h ago)   20d     192.168.126.102   k8s-master-b   <none>           <none>
kube-controller-manager-k8s-master-c       1/1     Running   21 (3d4h ago)   20d     192.168.126.103   k8s-master-c   <none>           <none>
kube-proxy-2rbs8                           1/1     Running   15 (3d1h ago)   20d     192.168.126.101   k8s-master-a   <none>           <none>
kube-proxy-5kmd4                           1/1     Running   19 (3d4h ago)   20d     192.168.126.103   k8s-master-c   <none>           <none>
kube-proxy-7t9lv                           1/1     Running   0               3d1h    192.168.126.105   worker-02      <none>           <none>
kube-proxy-dzsl4                           1/1     Running   1 (3d4h ago)    5d3h    192.168.126.104   worker-01      <none>           <none>
kube-proxy-s2gsr                           1/1     Running   16 (3d4h ago)   20d     192.168.126.102   k8s-master-b   <none>           <none>
kube-scheduler-k8s-master-a                1/1     Running   28 (3d1h ago)   20d     192.168.126.101   k8s-master-a   <none>           <none>
kube-scheduler-k8s-master-b                1/1     Running   26 (3d4h ago)   20d     192.168.126.102   k8s-master-b   <none>           <none>
kube-scheduler-k8s-master-c                1/1     Running   19 (3d4h ago)   20d     192.168.126.103   k8s-master-c   <none>           <none>

```

```
Here is how to download the Linux binaries for kubectx and kubens utility:

wget https://github.com/ahmetb/kubectx/releases/download/v0.9.0/kubectx_v0.9.0_linux_x86_64.tar.gz
wget https://github.com/ahmetb/kubectx/releases/download/v0.9.0/kubens_v0.9.0_linux_x86_64.tar.gz
Then you extract them with the following commands:

tar -xvf kubectx_v0.9.0_linux_x86_64.tar.gz
tar -xvf kubens_v0.9.0_linux_x86_64.tar.gz
Finally, you move them to your PATH:

sudo mv kubectx /usr/local/bin
sudo mv kubens /usr/local/bin
```
