#!/bin/bash

echo "=== Kubernetes Installation Script ==="

# Pilih container runtime
echo "Pilih container runtime yang ingin digunakan:"
select runtime in "containerd" "cri-o" "docker"; do
    case $runtime in
        containerd | cri-o | docker ) break ;;
        * ) echo "Pilihan tidak valid." ;;
    esac
done

# Masukkan versi Kubernetes
read -p "Masukkan versi Kubernetes yang ingin diinstal (misal: 1.30.0): " kube_version

# Nonaktifkan swap
echo "[+] Menonaktifkan swap..."
sudo swapoff -a
sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

# Modul kernel & sysctl
echo "[+] Mengatur modul kernel dan sysctl..."
cat <<EOF | sudo tee /etc/modules-load.d/${runtime}.conf
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter

cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.ipv4.ip_forward = 1
EOF

sudo sysctl --system

# Instalasi runtime container
if [ "$runtime" = "containerd" ]; then
    echo "[+] Menginstal containerd..."
    sudo apt-get update
    sudo apt-get install -y ca-certificates curl gnupg
    sudo install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo tee /etc/apt/keyrings/docker.asc > /dev/null
    sudo chmod a+r /etc/apt/keyrings/docker.asc

    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
      $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
      sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

    sudo apt-get update
    sudo apt-get install -y containerd.io
    containerd config default | sudo tee /etc/containerd/config.toml >/dev/null 2>&1
    sudo sed -i 's/SystemdCgroup \= false/SystemdCgroup \= true/g' /etc/containerd/config.toml
    sudo systemctl restart containerd
    sudo systemctl enable containerd

elif [ "$runtime" = "cri-o" ]; then
    echo "[+] Menginstal CRI-O..."
    OS="xUbuntu_$(lsb_release -rs)"
    sudo apt-get update
    sudo apt-get install -y curl gnupg lsb-release
    echo "deb [signed-by=/usr/share/keyrings/libcontainers-archive-keyring.gpg] https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/$OS/ /" | sudo tee /etc/apt/sources.list.d/devel:kubic:libcontainers:stable.list
    curl -L https://download.opensuse.org/repositories/devel:kubic:libcontainers:stable/$OS/Release.key | gpg --dearmor | sudo tee /usr/share/keyrings/libcontainers-archive-keyring.gpg > /dev/null
    echo "deb [signed-by=/usr/share/keyrings/cri-o-archive-keyring.gpg] https://download.opensuse.org/repositories/devel:kubic:cri-o:stable:$kube_version/$OS/ /" | sudo tee /etc/apt/sources.list.d/devel:kubic:cri-o:stable:$kube_version.list
    curl -L https://download.opensuse.org/repositories/devel:kubic:cri-o:stable:$kube_version/$OS/Release.key | gpg --dearmor | sudo tee /usr/share/keyrings/cri-o-archive-keyring.gpg > /dev/null

    sudo apt-get update
    sudo apt-get install -y cri-o cri-o-runc
    sudo systemctl daemon-reexec
    sudo systemctl enable --now crio

elif [ "$runtime" = "docker" ]; then
    echo "[+] Menginstal Docker dan cri-dockerd..."
    sudo apt-get update
    sudo apt-get install -y ca-certificates curl gnupg lsb-release
    sudo mkdir -p /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
      $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
      sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    sudo apt-get update
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    # cri-dockerd
    sudo apt-get install -y git golang-go
    git clone https://github.com/Mirantis/cri-dockerd.git
    cd cri-dockerd
    mkdir bin
    go build -o bin/cri-dockerd
    sudo install -o root -m 0755 bin/cri-dockerd /usr/local/bin/cri-dockerd
    sudo cp -a packaging/systemd/* /etc/systemd/system/
    sudo sed -i 's:/usr/bin/cri-dockerd:/usr/local/bin/cri-dockerd:' /etc/systemd/system/cri-docker.service
    sudo systemctl daemon-reexec
    sudo systemctl daemon-reload
    sudo systemctl enable --now docker
    sudo systemctl enable --now cri-docker
    cd ..
fi

# Instalasi Kubernetes
echo "[+] Mengatur repositori Kubernetes (v$kube_version)..."
sudo apt-get install -y apt-transport-https ca-certificates curl gpg
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v${kube_version%.*}/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v${kube_version%.*}/deb/ /" | sudo tee /etc/apt/sources.list.d/kubernetes.list

sudo apt-get update
sudo apt-get install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl
sudo systemctl enable --now kubelet

echo "[✓] Instalasi selesai. Runtime: $runtime, Kubernetes v$kube_version"
