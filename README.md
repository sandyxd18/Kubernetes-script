**Get Started**
-

1. Clone Repository
```bash
git clone https://github.com/sandyxd18/Kubernetes-script.git
cd Kubernetes-script
```
2. Add execute to the file
```bash!
chmod +x kube-install-* # on all nodes
chmod +x calico-install.sh # on master node
```
3. Run the script
```bash
./kube-install.sh # on all nodes
./calico-install.sh # on master node
```

4. Install HAProxy (HA Master Scenario)
```bash
chmod +x haproxy-install.sh
./haproxy-install.sh
```

5. Bootstrap Cluster
```bash
sudo kubeadm init --config kubeadm-config.yaml # on master node
```