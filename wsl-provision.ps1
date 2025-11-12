#!/usr/bin/env bash
# ===============================================
# bootstrap.sh — Version 0.6
# -----------------------------------------------
# Author: Kevin Price
# Purpose:
#     Configure a WSL Ubuntu environment for GPU-enabled
#     AI and development workloads with optional pauses
#     for debugging and verification.
#
# Changelog:
#   v0.6 - Added pause function, error handling, re-ordered
#          PATH and OpenWebUI install, clarified Ollama flow,
#          removed redundant Open LLaMA section.
# ===============================================

LOGFILE="$HOME/bootstrap.log"
exec > >(tee -a "$LOGFILE") 2>&1
set -e  # Exit immediately on any error

# Pause function for interactive debugging
pause() {
    if [ -z "$AUTO" ]; then
        read -rp $'\nPress any key to continue to the next step... ' -n1 -s
        echo -e "\n"
    fi
}

echo "=== Starting Bootstrap Script v0.6 ==="
echo "Timestamp: $(date)"
echo "Logfile: $LOGFILE"
echo "====================================="

##############################################
# [0/10] Configure WSL default user and home
##############################################
echo "[0/10] Configuring /etc/wsl.conf to start in /root..."
cat << 'EOF' | sudo tee /etc/wsl.conf > /dev/null
[user]
default=root

[boot]
command="cd ~"
EOF
pause

##############################################
# [1/10] Update & Upgrade System
##############################################
echo "[1/10] Updating and upgrading system packages..."
apt-get update -y && apt-get upgrade -y
pause

##############################################
# [2/10] Install Fastfetch for system info
##############################################
echo "[2/10] Installing Fastfetch..."
add-apt-repository ppa:zhangsongcui3371/fastfetch -y
apt-get update -y
apt-get install fastfetch -y

# Add Fastfetch and GPU summary to .bashrc
if ! grep -q "fastfetch" ~/.bashrc; then
    echo "fastfetch" >> ~/.bashrc
fi
if ! grep -q "nvidia-smi --query-gpu" ~/.bashrc; then
    echo 'nvidia-smi --query-gpu=name,memory.total,memory.used,utilization.gpu --format=csv,noheader' >> ~/.bashrc
fi
pause

##############################################
# [3/10] Install CUDA Dependencies and Tools
##############################################
echo "[3/10] Installing NVIDIA CUDA tools..."
apt-get install -y wget gnupg libtinfo5
CUDA_REPO="https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/"
wget ${CUDA_REPO}/cuda-keyring_1.1-1_all.deb
dpkg -i cuda-keyring_1.1-1_all.deb
apt-get update -y
apt-get install -y nvidia-utils-535 nvidia-container-toolkit cuda-runtime-12-2
pause

##############################################
# [4/10] Verify GPU Access
##############################################
echo "[4/10] Verifying GPU access..."
if command -v nvidia-smi &>/dev/null; then
    nvidia-smi
else
    echo "⚠️ nvidia-smi not found. Check NVIDIA installation."
fi
pause

##############################################
# [5/10] Install system utilities (btop, etc.)
##############################################
echo "[5/10] Installing btop and base utilities..."
apt-get install -y btop git curl software-properties-common
pause

##############################################
# [6/10] Install Python, PyTorch (CUDA), HuggingFace
##############################################
echo "[6/10] Installing Python, PyTorch (CUDA), and HuggingFace..."
apt-get install -y python3 python3-pip
export PATH=$PATH:/usr/local/bin:~/.local/bin

# Install PyTorch with CUDA 12.x support
pip install --break-system-packages torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu121
pip install --break-system-packages transformers accelerate sentencepiece

# Verify PyTorch GPU support
python3 - << 'EOF'
import torch
print("PyTorch CUDA available:", torch.cuda.is_available())
print("GPU Name:", torch.cuda.get_device_name(0) if torch.cuda.is_available() else "No GPU detected")
EOF
pause

##############################################
# [7/10] Install and start Ollama
##############################################
echo "[7/10] Installing Ollama CLI..."
curl -fsSL https://ollama.com/install.sh | sh

echo "Starting Ollama service..."
nohup ollama serve > /var/log/ollama.log 2>&1 &
sleep 5

echo "Verifying Ollama API..."
curl -s http://localhost:11434/api/tags || echo "⚠️ Ollama may not be running yet."
pause

##############################################
# [8/10] Install OpenWebUI
##############################################
echo "[8/10] Installing OpenWebUI..."
# Recommended install method
curl -fsSL https://openwebui.com/install.sh | bash || {
    echo "Fallback to pip install..."
    pip install --break-system-packages open-webui
}

# Ensure binary path
export PATH=$PATH:/usr/local/bin:~/.local/bin
echo 'export PATH=$PATH:/usr/local/bin:~/.local/bin' >> ~/.bashrc

echo "Starting OpenWebUI on port 8080..."
nohup open-webui serve --host 0.0.0.0 --port 8080 --ollama-base-url http://localhost:11434 > /var/log/openwebui.log 2>&1 &
sleep 5
pause

##############################################
# [9/10] Cleanup
##############################################
echo "[9/10] Cleaning up..."
apt-get autoremove -y && apt-get clean
pause

##############################################
# [10/10] Final Notes
##############################################
echo "=== Bootstrap Completed Successfully ==="
echo "Access OpenWebUI at: http://<your-ip>:8080"
echo "First-use will prompt you to create an admin account."
echo "Log saved to $LOGFILE"
echo "Run 'wsl --shutdown' in PowerShell to apply /etc/wsl.conf changes."
echo "==============================================="
pause
