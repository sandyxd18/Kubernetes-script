#!/bin/bash

echo "=== Kubernetes Installation Script ==="

# Masukkan versi Kubernetes
read -p "Masukkan versi Kubernetes yang ingin diinstal (misal: 1.30.0): " kube_version

# Nonaktifkan swap
echo "[+] Menonaktifkan swap..."
sudo swapoff -a
sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

# Modul kernel & sysctl
echo "[+] Mengatur modul kernel dan sysctl..."
cat > /etc/modules-load.d/containerd.conf <<EOF
overlay
br_netfilter
EOF

modprobe overlay
modprobe br_netfilter

cat > /etc/sysctl.d/99-kubernetes-cri.conf <<EOF
net.bridge.bridge-nf-call-iptables  = 1
net.ipv4.ip_forward                 = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF

sysctl --system

# Instalasi runtime container
echo "[+] Menginstal containerd..."
sudo dnf -y install dnf-plugins-core
sudo dnf config-manager --add-repo https://download.docker.com/linux/rhel/docker-ce.repo
sudo dnf install -y containerd.io
mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml
sudo sed -i 's/SystemdCgroup \= false/SystemdCgroup \= true/g' /etc/containerd/config.toml
sudo systemctl restart containerd
sudo systemctl enable containerd

# Instalasi Kubernetes
echo "[+] Mengatur repositori Kubernetes (v$kube_version)..."
cat <<EOF > /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/v${kube_version%.*}/rpm/
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/v${kube_version%.*}/rpm/repodata/repomd.xml.key
exclude=kubelet kubeadm kubectl
EOF

setenforce 0
sudo sed -i 's/^SELINUX=enforcing$/SELINUX=permissive/' /etc/selinux/config

sudo dnf upgrade -y
sudo dnf install -y kubelet kubeadm kubectl --disableexcludes=kubernetes

sudo systemctl enable --now kubelet
sudo systemctl start kubelet

echo "[✓] Instalasi selesai. Kubernetes v$kube_version"
