#!/bin/bash
set -e

echo "=== HAProxy dan Keepalived Installation Script ==="

read -p "Masukkan status HA (MASTER/BACKUP): " HA_STATE
read -p "Masukkan prioritas HA (misal: 100 untuk MASTER, 90 untuk BACKUP): " HA_PRIORITY
read -p "Masukkan IP Load Balancer virtual (misal: 192.168.100.100): " YOUR_LB_IP
read -p "Masukkan prefix length untuk IP Load Balancer virtual (misal: 24): " PREFIX_LENGTH
read -p "Masukkan jumlah Master Node (misal: 2): " MASTER_NODE_COUNT

# Array untuk menyimpan IP master
MASTER_NODES=()

for (( i=1; i<=MASTER_NODE_COUNT; i++ )); do
    read -p "Masukkan IP Master Node $i (misal: 192.168.100.101): " NODE_IP
    MASTER_NODES+=("$NODE_IP")
done

sudo apt-get update
sudo apt-get install -y haproxy keepalived iproute2 iputils-ping vim

cat <<EOF | sudo tee /etc/sysctl.d/haproxy.conf
net.ipv4.ip_nonlocal_bind = 1
EOF

sudo sysctl --system

# ===============================
# Generate HAProxy backend server
# ===============================
BACKEND_SERVERS=""
INDEX=1
for IP in "${MASTER_NODES[@]}"; do
    BACKEND_SERVERS+="    server master-node-${INDEX} ${IP}:6443 check\n"
    ((INDEX++))
done

# ===============================
# HAProxy config
# ===============================
cat <<EOF | sudo tee /etc/haproxy/haproxy.cfg
global
    log stdout format raw local0
    maxconn 2048
    daemon

defaults
    log     global
    mode    tcp
    timeout connect 5s
    timeout client  1m
    timeout server  1m

frontend kubernetes
    bind ${YOUR_LB_IP}:6443
    default_backend kubernetes-master-nodes

backend kubernetes-master-nodes
    mode tcp
    balance roundrobin
    option tcp-check
${BACKEND_SERVERS}
EOF

sudo systemctl enable haproxy
sudo systemctl restart haproxy

# ===============================
# Keepalived config
# ===============================
cat <<EOF | sudo tee /etc/keepalived/keepalived.conf
vrrp_script chk_haproxy {
    script "pkill -0 haproxy"
    interval 2
    weight -20
}

vrrp_instance VI_1 {
    state ${HA_STATE}
    interface eth0
    virtual_router_id 51
    priority ${HA_PRIORITY}
    advert_int 1
    nopreempt

    authentication {
        auth_type PASS
        auth_pass 123123
    }

    virtual_ipaddress {
        ${YOUR_LB_IP}/${PREFIX_LENGTH}
    }

    track_script {
        chk_haproxy
    }
}
EOF

sudo systemctl enable keepalived
sudo systemctl restart keepalived

sudo systemctl start keepalived
sudo systemctl start haproxy