#!/usr/bin/env bash

set -e

echo "=== Updating package lists ==="
apt update -y

echo "=== Installing prerequisites ==="
apt install -y wget

###############################################
# 1. Install Fastfetch
###############################################

echo "=== Downloading latest Fastfetch .deb package ==="
cd /tmp
wget -O fastfetch-linux-amd64.deb \
  https://github.com/fastfetch-cli/fastfetch/releases/latest/download/fastfetch-linux-amd64.deb

echo "=== Installing Fastfetch ==="
apt install -y ./fastfetch-linux-amd64.deb

echo "=== Adding fastfetch to root's .bashrc ==="
if ! grep -q "fastfetch" /root/.bashrc; then
    echo "fastfetch" >> /root/.bashrc
fi


###############################################
# 2. Install btop
###############################################

echo "=== Installing btop ==="
apt install -y btop


###############################################
# 3. Ensure login starts in /root
###############################################

echo "=== Fixing WSL default login directory ==="

# This prevents WSL from spawning in /mnt/c or /mnt/d
# Adds: cd ~  to .bashrc if not already present
if ! grep -q "cd ~" /root/.bashrc; then
    echo "cd ~" >> /root/.bashrc
fi

# Also apply for the non-root user if needed
if [ -f "/home/$SUDO_USER/.bashrc" ]; then
    if ! grep -q "cd ~" /home/$SUDO_USER/.bashrc; then
        echo "cd ~" >> /home/$SUDO_USER/.bashrc
    fi
fi

echo "=== Completed successfully! ==="
echo "Exit WSL and re-open your instance to see Fastfetch on login."
