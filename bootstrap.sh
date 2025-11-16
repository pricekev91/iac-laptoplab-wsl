#!/usr/bin/env bash
# ===============================================
# bootstrap.sh — Version 1.2 (WSL AI + Ollama + WebUI + systemd)
# -----------------------------------------------
# Author: Kevin Price (Final)
# Purpose:
#     Configure WSL Ubuntu for Ollama + OpenWebUI with GPU support
#     Install OpenWebUI via official installer (NOT pip)
# ===============================================

LOGFILE="$HOME/bootstrap.log"
exec > >(tee -a "$LOGFILE") 2>&1
set -e

echo "=== Starting Bootstrap Script v1.2 ==="
echo "Timestamp: $(date)"
echo "Logfile: $LOGFILE"
echo "====================================="

##############################################
# [0/12] Enable systemd in WSL
##############################################
echo "[0/12] Enabling systemd in WSL..."
cat << 'EOF' | sudo tee /etc/wsl.conf > /dev/null
[user]
default=root

[boot]
systemd=true
EOF
echo "✅ systemd enabled. Restart WSL after script completes."

##############################################
# [1/12] Update & Upgrade System
##############################################
echo "[1/12] Updating system..."
apt-get update -y && apt-get upgrade -y

##############################################
# [2/12] Install Fastfetch from GitHub
##############################################
echo "[2/12] Installing Fastfetch from GitHub..."
apt-get install -y git cmake gcc g++ pkg-config libwayland-dev libx11-dev libxrandr-dev libxi-dev libxinerama-dev libxft-dev
git clone --depth=1 https://github.com/fastfetch-cli/fastfetch.git /tmp/fastfetch
cd /tmp/fastfetch
mkdir build && cd build
cmake ..
make -j$(nproc)
make install
grep -q "fastfetch" ~/.bashrc || echo "fastfetch" >> ~/.bashrc

##############################################
# [3/12] Install CUDA runtime
##############################################
echo "[3/12] Installing CUDA runtime..."
CUDA_REPO="https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/"
wget -q ${CUDA_REPO}/cuda-keyring_1.1-1_all.deb -O /tmp/cuda-keyring.deb
dpkg -i /tmp/cuda-keyring.deb
apt-get update -y
apt-get install -y cuda-runtime-12-4
echo 'export PATH=$PATH:/usr/local/cuda/bin' >> ~/.bashrc
export PATH=$PATH:/usr/local/cuda/bin

##############################################
# [4/12] Verify GPU
##############################################
echo "[4/12] Checking GPU..."
if command -v nvidia-smi &>/dev/null; then
    nvidia-smi
else
    echo "⚠️ nvidia-smi not found (expected if driver is only present on Windows)."
fi

##############################################
# [5/12] Install Python + AI libs
##############################################
echo "[5/12] Installing Python & AI libs..."
apt-get install -y python3 python3-pip
pip install --break-system-packages torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu121
pip install --break-system-packages transformers accelerate sentencepiece

##############################################
# [6/12] Install Ollama
##############################################
echo "[6/12] Installing Ollama..."
curl -fsSL https://ollama.com/install.sh | sh
export OLLAMA_HOME="$HOME/.ollama"
echo 'export OLLAMA_HOME="$HOME/.ollama"' >> ~/.bashrc

##############################################
# [7/12] Pre-pull default model
##############################################
echo "[7/12] Pulling default model deepseek-r1:1.5b ..."
ollama pull deepseek-r1:1.5b

##############################################
# [8/12] Install OpenWebUI (OFFICIAL installer)
##############################################
echo "[8/12] Installing OpenWebUI using official installer..."
curl -fsSL https://raw.githubusercontent.com/open-webui/open-webui/main/install.sh | bash

##############################################
# [9/12] Create systemd service for Ollama
##############################################
echo "[9/12] Creating Ollama systemd service..."
cat << 'EOF' | sudo tee /etc/systemd/system/ollama.service > /dev/null
[Unit]
Description=Ollama Service
After=network.target

[Service]
ExecStart=/usr/local/bin/ollama serve
Restart=always
User=root
Environment=OLLAMA_HOME=/root/.ollama

[Install]
WantedBy=multi-user.target
EOF

##############################################
# [10/12] Enable OpenWebUI service (already installed)
##############################################
echo "[10/12] Enabling OpenWebUI service..."
systemctl enable openwebui

##############################################
# [11/12] Enable and start services
##############################################
echo "[11/12] Starting services..."
systemctl enable ollama.service
systemctl start ollama.service
systemctl start openwebui.service

##############################################
# [12/12] Cleanup
##############################################
echo "[12/12] Cleaning up..."
apt-get autoremove -y && apt-get clean

##############################################
# Final Notes
##############################################
echo "==============================================="
echo "✅ Bootstrap Completed Successfully!"
echo "Restart WSL using:   wsl --shutdown"
echo "Ollama running at:   http://localhost:11434"
echo "OpenWebUI running at http://<your-ip>:8080"
echo "==============================================="
