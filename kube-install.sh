#!/bin/bash

set -e

#############################################
# Root enforcement
#############################################
if [[ $EUID -ne 0 ]]; then
  echo "[-] Script ini harus dijalankan sebagai root"
  echo "    Contoh: sudo ./install-k8s.sh"
  exit 1
fi

echo "=== Kubernetes Installation Script ==="

#############################################
# Input & validation
#############################################
read -p "Masukkan versi Kubernetes yang ingin diinstal (misal: 1.30.0): " kube_version

if ! [[ "$kube_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "[-] Format versi tidak valid (contoh: 1.30.0)"
  exit 1
fi

#############################################
# OS detection
#############################################
. /etc/os-release

OS_ID="$ID"
OS_CODENAME="$VERSION_CODENAME"

#############################################
# Disable swap (required by Kubernetes)
#############################################
echo "[+] Menonaktifkan swap..."
swapoff -a
sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

#############################################
# Kernel modules & sysctl
#############################################
echo "[+] Mengatur kernel module & sysctl..."
cat > /etc/modules-load.d/containerd.conf <<EOF
overlay
br_netfilter
EOF

modprobe overlay
modprobe br_netfilter

cat > /etc/sysctl.d/99-kubernetes-cri.conf <<EOF
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                = 1
EOF

sysctl --system

#############################################
# Debian / Ubuntu
#############################################
if [[ "$ID" == "ubuntu" || "$ID" == "debian" ]]; then

  echo "[+] Detected Debian-based distro ($ID)"

  ###########################################
  # Docker repo (containerd)
  ###########################################
  echo "[+] Mengatur Docker repository..."
  apt-get update
  apt-get install -y ca-certificates curl gnupg

  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/${OS_ID}/gpg \
    | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg

  echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/${OS_ID} \
  ${OS_CODENAME} stable" \
  > /etc/apt/sources.list.d/docker.list

  ###########################################
  # Install containerd
  ###########################################
  echo "[+] Menginstal containerd..."
  apt-get update
  apt-get install -y containerd.io

  containerd config default > /etc/containerd/config.toml
  sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml

  systemctl restart containerd
  systemctl enable containerd

  ###########################################
  # Kubernetes repo & install
  ###########################################
  echo "[+] Mengatur repository Kubernetes v$kube_version..."
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://pkgs.k8s.io/core:/stable:/v${kube_version%.*}/deb/Release.key \
    | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

  echo \
  "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] \
  https://pkgs.k8s.io/core:/stable:/v${kube_version%.*}/deb/ /" \
  > /etc/apt/sources.list.d/kubernetes.list

  apt-get update
  apt-get install -y kubelet kubeadm kubectl
  apt-mark hold kubelet kubeadm kubectl

#############################################
# RHEL family (Rocky / Alma / RHEL / CentOS)
#############################################
elif [[ "$ID_LIKE" == *"rhel"* ]]; then

  echo "[+] Detected RHEL-based distro ($ID)"

  ###########################################
  # SELinux
  ###########################################
  setenforce 0 || true
  sed -i 's/^SELINUX=.*/SELINUX=permissive/' /etc/selinux/config

  ###########################################
  # Install containerd
  ###########################################
  echo "[+] Menginstal containerd..."
  dnf -y install dnf-plugins-core
  dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
  dnf install -y containerd.io

  mkdir -p /etc/containerd
  containerd config default > /etc/containerd/config.toml
  sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml

  systemctl restart containerd
  systemctl enable containerd

  ###########################################
  # Kubernetes repo & install
  ###########################################
  echo "[+] Mengatur repository Kubernetes v$kube_version..."
  cat > /etc/yum.repos.d/kubernetes.repo <<EOF
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/v${kube_version%.*}/rpm/
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/v${kube_version%.*}/rpm/repodata/repomd.xml.key
exclude=kubelet kubeadm kubectl
EOF

  dnf install -y kubelet kubeadm kubectl --disableexcludes=kubernetes

else
  echo "[-] Sistem operasi tidak didukung"
  exit 1
fi

#############################################
# Enable kubelet
#############################################
systemctl enable --now kubelet

echo
echo "[✓] Instalasi selesai"
echo "[✓] Kubernetes version: $kube_version"