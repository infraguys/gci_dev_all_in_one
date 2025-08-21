#!/usr/bin/env bash

set -eu
set -x
set -o pipefail

EL_PATH="/opt/stand/genesis_core"

cd /opt
sudo chown ubuntu ./ -R
python3 -m venv .venv
source .venv/bin/activate
pip install genesis-devtools

cd $EL_PATH
genesis bootstrap -i output/genesis-core.raw -f -m core --memory 2000
sudo virsh autostart genesis-core-bootstrap

while [[ "$(curl -s -o /dev/null -w ''%{http_code}'' 10.20.0.2:11010)" != "200" ]]; do
    sleep 5;
done

ADMIN_TOKEN=$(curl --location 'http://10.20.0.2:11010/v1/iam/clients/00000000-0000-0000-0000-000000000000/actions/get_token/invoke' \
    --header 'Content-Type: application/x-www-form-urlencoded' \
    --data-urlencode 'grant_type=password' \
    --data-urlencode 'username=admin' \
    --data-urlencode 'password=admin' \
    --data-urlencode 'client_id=GenesisCoreClientId' \
    --data-urlencode 'client_secret=GenesisCoreClientSecret' \
    --data-urlencode 'scope=' \
    --data-urlencode 'ttl=31536000' | jq .access_token -r)

echo $ADMIN_TOKEN > /home/ubuntu/admin_token.txt

curl --location --request PUT 'http://10.20.0.2:11010/v1/iam/clients/00000000-0000-0000-0000-000000000000' \
    --header 'Content-Type: application/json' \
    --header "Authorization: Bearer $ADMIN_TOKEN" \
    --data '{
        "redirect_url": "http://10.20.0.2:11010/v1/"
    }'

curl --location --globoff 'http://10.20.0.2:11010/v1/hypervisors/' \
    --header 'Content-Type: application/json' \
    --header "Authorization: Bearer $ADMIN_TOKEN" \
    --data '{
        "driver_spec": {
            "driver": "libvirt",
            "iface_mtu": 1500,
            "network_type": "network",
            "network": "genesis-core-net",
            "storage_pool": "rpool",
            "connection_uri": "qemu+tcp://10.20.0.1/system",
            "machine_prefix": "dev-"
        },
        "avail_cores": 10,
        "avail_ram": 15000,
        "all_cores": 24,
        "all_ram": 22000,
        "status": "ACTIVE"
    }'

# create node example
# curl --location 'http://10.20.0.2:11010/v1/nodes/' \
# --header 'Content-Type: application/json' \
# --header "Authorization: Bearer $ADMIN_TOKEN" \
# --data '{
#     "name": "test",
#     "project_id": "5d72ca4a-c053-4b93-b52a-c20ad9c37be4",
#     "root_disk_size": 5,
#     "cores": 1,
#     "ram": 2048,
#     "image": "http://10.130.0.1:8080/genesis-base.raw"
# }'

sudo systemctl restart netfilter-persistent.service

# Some post install additions to minify original distributed image
# zram
sudo apt-get update
sudo apt-get install -y zram-tools linux-modules-extra-$(uname -r)
echo "ALGO=zstd" | sudo tee -a /etc/default/zramswap > /dev/null
echo "PERCENT=20" | sudo tee -a /etc/default/zramswap > /dev/null
sudo systemctl enable zramswap
sudo systemctl start zramswap

# Remove the cron job to ensure bootstrap runs only once
sudo rm /etc/cron.d/core_bootstrap
