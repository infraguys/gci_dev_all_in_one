#!/usr/bin/env bash

set -eu
set -x
set -o pipefail

# Some post install additions to minify original distributed image
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
sudo systemctl start ksmtuned

# Remove the cron job to ensure bootstrap runs only once
sudo rm /etc/cron.d/core_bootstrap
