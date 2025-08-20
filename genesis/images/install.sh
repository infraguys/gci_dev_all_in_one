#!/usr/bin/env bash

# Copyright 2025 Genesis Corporation
#
# All Rights Reserved.
#
#    Licensed under the Apache License, Version 2.0 (the "License"); you may
#    not use this file except in compliance with the License. You may obtain
#    a copy of the License at
#
#         http://www.apache.org/licenses/LICENSE-2.0
#
#    Unless required by applicable law or agreed to in writing, software
#    distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
#    WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
#    License for the specific language governing permissions and limitations
#    under the License.

set -eu
set -x
set -o pipefail

EL_PATH="/opt/stand"


# Optimize apt
echo 'APT::Install-Recommends "false";' | sudo tee -a /etc/apt/apt.conf.d/99genesis.conf > /dev/null
echo 'APT::Install-Suggests "false";' | sudo tee -a /etc/apt/apt.conf.d/99genesis.conf > /dev/null
sudo apt-get update
sudo apt-get install python3.12-venv yq -y

# Access
echo "ubuntu:ubuntu" | sudo chpasswd
sudo rm /etc/ssh/sshd_config.d/60-cloudimg-settings.conf
sudo yq -yi '.system_info.default_user.lock_passwd |= false' /etc/cloud/cloud.cfg

# Common optimizations for FS and RAM usage
sudo zfs set compression=zstd rpool
sudo zfs set sync=disabled rpool
sudo zfs create -o compression=zstd-10 -o recordsize=1M rpool/opt
sudo mv /opt_orig/stand /opt
sudo rm -rf /opt_orig

sudo mkdir -p /etc/docker/
echo '{"storage-driver": "zfs"}' | sudo tee /etc/docker/daemon.json

# Reset cloud-init, ubuntu-zfs image have it
sudo cloud-init clean --log --seed
sudo rm /etc/netplan/50-cloud-init.yaml
echo "datasource_list: [ None ]" | sudo tee /etc/cloud/cloud.cfg.d/99_overrides.cfg

# zram
sudo apt-get update
sudo apt-get install -y zram-tools linux-modules-extra-$(uname -r)
echo "ALGO=zstd" | sudo tee -a /etc/default/zramswap > /dev/null
echo "PERCENT=20" | sudo tee -a /etc/default/zramswap > /dev/null
sudo systemctl enable zramswap
sudo systemctl start zramswap

# ksm
sudo apt install -y ksmtuned
# minimize cpu usage
echo "KSM_SLEEP_MSEC=100" | sudo tee -a /etc/ksmtuned.conf > /dev/null
sudo systemctl enable ksmtuned

sudo apt-get update
sudo apt install qemu-guest-agent bridge-utils qemu-kvm libvirt-daemon-system libvirt-dev mkisofs net-tools libvirt-daemon-driver-storage-zfs dnsmasq qemu-system-modules-spice iptables-persistent -y


# libvirt install breaks dns, fix it temporarily
sudo resolvectl dns ens4 1.1.1.1

cat | sudo tee -a /etc/libvirt/libvirtd.conf > /dev/null <<EOL
listen_tcp = 1
listen_addr = "0.0.0.0"
auth_tcp = "none"
EOL

sudo systemctl stop libvirtd
sudo systemctl enable libvirtd-tcp.socket
sudo systemctl start libvirtd-tcp.socket
sudo systemctl start libvirtd

# Prepare storage
zfs create rpool/disks
virsh pool-define-as --name rpool --source-name rpool/disks --type zfs
virsh pool-start rpool

# iptables rules are order-sensitive, so set appropriate rules via libvirt hooks
sudo mkdir -p /etc/libvirt/hooks
sudo cp $EL_PATH/etc/libvirt/hooks/qemu /etc/libvirt/hooks/
sudo chmod +x /etc/libvirt/hooks/qemu

cat | sudo tee /etc/iptables/rules.v4 > /dev/null <<EOL
*nat
-A POSTROUTING -s 10.20.0.0/24 -o enp1s0 -j MASQUERADE
COMMIT
EOL

cat | sudo tee -a /etc/sysctl.conf > /dev/null <<EOL
net.ipv4.ip_forward=1
EOL

echo "@reboot ubuntu ${EL_PATH}/genesis/images/bootstrap.sh 2>&1 | logger -t genesis_bootstrap" | sudo tee /etc/cron.d/core_bootstrap > /dev/null

# Minimize image size
sudo apt-get clean
sudo rm -rf /var/lib/apt/lists/*
sudo sync
sudo zpool sync
sudo zpool trim -w rpool
sudo echo '0' | sudo tee /sys/module/zfs/parameters/zfs_initialize_value > /dev/null
sudo zpool initialize -w rpool
