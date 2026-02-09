#!/bin/bash

echo "=== HAProxy dan Keepalived Installation Script ==="

read -p "Masukkan status HA (MASTER/BACKUP): " HA_STATE
read -p "Masukkan prioritas HA (misal: 100 untuk MASTER, 90 untuk BACKUP): " HA_PRIORITY
read -p "Masukkan IP Load Balancer virtual (misal: 192.168.100.100): " YOUR_LB_IP
read -p "Masukkan IP Master Node 1 (misal: 192.168.100.101): " MASTER_NODE_1_IP
read -p "Masukkan IP Master Node 2 (misal: 192.168.100.102): " MASTER_NODE_2_IP

sudo apt-get update
sudo apt-get install -y haproxy keepalived iproute2 iputils-ping vim

cat <<EOF | sudo tee /etc/sysctl.d/haproxy.conf
net.ipv4.ip_nonlocal_bind = 1
EOF

sudo sysctl --system

cat <<EOF | sudo tee /etc/haproxy/haproxy.cfg
global
    log stdout format raw local0
    maxconn 2048
    daemon

defaults
    log     global
    mode    http
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
    server master-node-1 ${MASTER_NODE_1_IP}:6443 check
    server master-node-2 ${MASTER_NODE_2_IP}:6443 check
EOF

sudo systemctl enable haproxy
sudo systemctl restart haproxy

cat <<EOF | sudo tee /etc/keepalived/keepalived.conf
vrrp_script chk_haproxy {
    script "/usr/local/bin/check_haproxy.sh"
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
        <YOUR_LB_IP>/24
    }

    track_script {
        chk_haproxy
    }
}
EOF

sudo systemctl enable keepalived
sudo systemctl restart keepalived

cat <<'EOF' | sudo tee /usr/local/bin/check_haproxy.sh
#!/bin/bash
pkill -0 haproxy
EOF

sudo chmod +x /usr/local/bin/check_haproxy.sh

sudo systemctl start keepalived
sudo systemctl start haproxy