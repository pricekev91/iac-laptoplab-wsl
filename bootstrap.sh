#!/usr/bin/env bash
# ===============================================
# bootstrap.sh — Version 1.0 (WSL AI + Ollama + WebUI + systemd)
# -----------------------------------------------
# Author: Kevin Price (Final)
# Purpose:
#     Configure WSL Ubuntu for Ollama + OpenWebUI with GPU support
#     Enable systemd, create services, pull DeepSeek-R1:1.5b
# ===============================================

LOGFILE="$HOME/bootstrap.log"
exec > >(tee -a "$LOGFILE") 2>&1
set -e

echo "=== Starting Bootstrap Script v1.0 ==="
echo "Timestamp: $(date)"
echo "Logfile: $LOGFILE"
echo "====================================="

##############################################
# [0/11] Enable systemd in WSL
##############################################
echo "[0/11] Enabling systemd in WSL..."
cat << 'EOF' | sudo tee /etc/wsl.conf > /dev/null
[user]
default=root

[boot]
systemd=true
EOF
echo "✅ systemd enabled. Run 'wsl --shutdown' after script completes."

##############################################
# [1/11] Update & Upgrade System
##############################################
echo "[1/11] Updating system..."
apt-get update -y && apt-get upgrade -y

##############################################
# [2/11] Install Fastfetch from GitHub
##############################################
echo "[2/11] Installing Fastfetch from official GitHub..."
apt-get install -y git cmake gcc g++ pkg-config libwayland-dev libx11-dev libxrandr-dev libxi-dev libxinerama-dev libxft-dev

git clone --depth=1 https://github.com/fastfetch-cli/fastfetch.git /tmp/fastfetch
cd /tmp/fastfetch
mkdir build && cd build
cmake ..
make -j$(nproc)
make install

grep -q "fastfetch" ~/.bashrc || echo "fastfetch" >> ~/.bashrc

##############################################
# [3/11] Install CUDA runtime
##############################################
echo "[3/11] Installing CUDA runtime..."
CUDA_REPO="https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/"
wget -q ${CUDA_REPO}/cuda-keyring_1.1-1_all.deb -O /tmp/cuda-keyring.deb
dpkg -i /tmp/cuda-keyring.deb
apt-get update -y
apt-get install -y cuda-runtime-12-4
echo 'export PATH=$PATH:/usr/local/cuda/bin' >> ~/.bashrc
export PATH=$PATH:/usr/local/cuda/bin

##############################################
# [4/11] Verify GPU
##############################################
echo "[4/11] Checking GPU..."
if command -v nvidia-smi &>/dev/null; then
    nvidia-smi
else
    echo "⚠️ nvidia-smi not found (expected in WSL if driver is on Windows)."
fi

##############################################
# [5/11] Install Python, PyTorch, HuggingFace
##############################################
echo "[5/11] Installing Python & AI libraries..."
apt-get install -y python3 python3-pip
pip install --break-system-packages torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu121
pip install --break-system-packages transformers accelerate sentencepiece

##############################################
# [6/11] Install Ollama
##############################################
echo "[6/11] Installing Ollama..."
curl -fsSL https://ollama.com/install.sh | sh
export OLLAMA_HOME="$HOME/.ollama"
echo 'export OLLAMA_HOME="$HOME/.ollama"' >> ~/.bashrc

##############################################
# [7/11] Pull default model (DeepSeek-R1:1.5b)
##############################################
echo "[7/11] Pulling DeepSeek-R1:1.5b..."
ollama pull deepseek-r1:1.5b

##############################################
# [8/11] Install OpenWebUI
##############################################
echo "[8/11] Installing OpenWebUI..."
pip install --break-system-packages --ignore-installed open-webui

##############################################
# [9/11] Create systemd service for Ollama
##############################################
echo "[9/11] Creating Ollama systemd service..."
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
# [10/11] Create systemd service for OpenWebUI
##############################################
echo "[10/11] Creating OpenWebUI systemd service..."
cat << 'EOF' | sudo tee /etc/systemd/system/openwebui.service > /dev/null
[Unit]
Description=OpenWebUI Service
After=ollama.service

[Service]
ExecStart=/usr/local/bin/open-webui serve --host 0.0.0.0 --port 8080 --ollama-base-url http://localhost:11434
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF

##############################################
# [11/11] Enable and start services
##############################################
echo "[11/11] Enabling and starting services..."
systemctl enable ollama.service
systemctl enable openwebui.service
systemctl start ollama.service
systemctl start openwebui.service

##############################################
# Final Notes
##############################################
echo "==============================================="
echo "✅ Bootstrap Completed Successfully!"
echo "✅ systemd enabled (restart WSL with 'wsl --shutdown')"
echo "✅ Ollama + OpenWebUI running as services"
echo "✅ Default model: deepseek-r1:1.5b"
echo "✅ Access OpenWebUI at: http://<your-ip>:8080"
echo "✅ Check status: systemctl status ollama.service | openwebui.service"
echo "==============================================="
