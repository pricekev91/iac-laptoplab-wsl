#!/usr/bin/env bash
# bootstrap.sh - Configure WSL Ubuntu environment for GPU-enabled development
# Logs everything to ~/bootstrap.log

LOGFILE="$HOME/bootstrap.log"
exec > >(tee -a "$LOGFILE") 2>&1

echo "=== Starting Bootstrap Script ==="
echo "Timestamp: $(date)"

# --- Ensure WSL config sets root home as default ---
echo "[0/7] Configuring /etc/wsl.conf to start in /root..."
cat << 'EOF' | sudo tee /etc/wsl.conf > /dev/null
[user]
default=root

[boot]
command="cd ~"
EOF

# --- Update & Upgrade ---
echo "[1/7] Updating system..."
apt-get update -y && apt-get upgrade -y

# --- Install Fastfetch ---
echo "[2/7] Installing Fastfetch..."
add-apt-repository ppa:zhangsongcui3371/fastfetch -y
apt-get update -y
apt-get install fastfetch -y

# Add Fastfetch and GPU summary to .bashrc if not already present
if ! grep -q "fastfetch" ~/.bashrc; then
    echo "fastfetch" >> ~/.bashrc
fi
if ! grep -q "nvidia-smi --query-gpu" ~/.bashrc; then
    echo 'nvidia-smi --query-gpu=name,memory.total,memory.used,utilization.gpu --format=csv,noheader' >> ~/.bashrc
fi

# --- Install libtinfo5 (CUDA dependency) ---
echo "[3/7] Installing libtinfo5..."
apt-get install libtinfo5 -y

# --- Install NVIDIA CLI tools & CUDA runtime ---
echo "[4/7] Installing NVIDIA CLI tools and CUDA runtime..."
CUDA_REPO="https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/"
apt-get install wget gnupg -y
wget ${CUDA_REPO}/cuda-keyring_1.1-1_all.deb
dpkg -i cuda-keyring_1.1-1_all.deb
apt-get update -y
apt-get install nvidia-utils-535 nvidia-container-toolkit cuda-runtime-12-2 -y

# --- Verify GPU Access ---
echo "[5/7] Verifying GPU access..."
if command -v nvidia-smi &> /dev/null; then
    nvidia-smi
else
    echo "nvidia-smi not found. Check NVIDIA installation."
fi

# --- Install btop (system monitor) ---
echo "[6/7] Installing btop..."
apt-get install btop -y

# --- Cleanup ---
echo "[7/7] Cleaning up..."
apt-get autoremove -y && apt-get clean

echo "=== Bootstrap Completed Successfully ==="
echo "Log saved to $LOGFILE"
echo "Reminder: run 'wsl --shutdown' in PowerShell to apply /etc/wsl.conf changes."
