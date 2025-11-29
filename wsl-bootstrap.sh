#!/usr/bin/env bash

set -e

###############################################
# CONFIGURATION
###############################################
MODEL_REPO="TheBloke/wizardLM-13B-1.0-GGUF"
MODEL_FILE="wizardLM-13B-1.0.Q4_K_M.gguf"
MODEL_INSTALL_DIR="/opt/ai-models"
HF_VENV="/opt/venvs/hf"

###############################################
# 0. Update package lists
###############################################
echo "=== Updating package lists ==="
apt update -y

###############################################
# 1. Install prerequisites
###############################################
echo "=== Installing prerequisites ==="
apt install -y wget btop python3 python3-venv python3-pip git curl

###############################################
# 2. Install Fastfetch
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
# 3. Ensure login starts in /root
###############################################
echo "=== Fixing WSL default login directory ==="
if ! grep -q "cd ~" /root/.bashrc; then
    echo "cd ~" >> /root/.bashrc
fi

# Apply for the invoking user if exists
if [ -n "$SUDO_USER" ] && [ -f "/home/$SUDO_USER/.bashrc" ]; then
    if ! grep -q "cd ~" /home/$SUDO_USER/.bashrc; then
        echo "cd ~" >> /home/$SUDO_USER/.bashrc
    fi
fi

###############################################
# 4. Setup Hugging Face venv & CLI
###############################################
echo "=== Creating Hugging Face venv at $HF_VENV ==="
mkdir -p /opt/venvs
python3 -m venv "$HF_VENV"

# Activate venv
source "$HF_VENV/bin/activate"

# Upgrade pip and install huggingface_hub
echo "=== Installing huggingface_hub in venv ==="
pip install --upgrade pip huggingface_hub

###############################################
# 5. Download Hugging Face model
###############################################
echo "=== Creating model install directory ==="
mkdir -p "$MODEL_INSTALL_DIR"

echo "=== Downloading model $MODEL_REPO / $MODEL_FILE ==="
"$HF_VENV/bin/hf" repo download "$MODEL_REPO" \
    --filename "$MODEL_FILE" \
    --local-dir "$MODEL_INSTALL_DIR"

echo "Model downloaded to $MODEL_INSTALL_DIR/$MODEL_FILE"

###############################################
# 6. Final message
###############################################
echo "=== Setup complete! ==="
echo "Close and reopen your WSL terminal to see Fastfetch on login."
echo "Use the Hugging Face CLI via the venv: $HF_VENV/bin/hf"
echo "Model ready at: $MODEL_INSTALL_DIR/$MODEL_FILE"
