**Get Started**
-

1. Clone Repository
```bash
git clone https://github.com/sandyxd18/Kubernetes-script.git
cd Kubernetes-script
```
2. Run the script
```bash
sudo bash kube-install.sh # on all nodes
sudo bash calico-install.sh # on master node
```

3. Install HAProxy (HA Master Scenario)
```bash
sudo bash haproxy-install.sh
```

4. Bootstrap Cluster
```bash
sudo kubeadm init --config kubeadm-config.yaml # on master node
```