#!/usr/bin/env bash
#
# 11-install-llama-openwebui.sh — Version 0.42
# Author: Kevin Price
# Updated: 2025-11-23
#
# Purpose:
#   Full AI Appliance installer for llama.cpp + OpenWebUI.
#   - Installs llama.cpp to /opt/llama.cpp
#   - Builds CUDA if available, else CPU
#   - Installs llama-server systemd service
#   - Installs OpenWebUI as venv service
#   - Downloads Meta-Llama-3-8B.gguf using HuggingFace CLI
#

set -euo pipefail

SCRIPT_VERSION="0.42"
LOG_FILE="/opt/llama-install.log"

exec > >(tee -a "$LOG_FILE") 2>&1

echo "============================================================"
echo "AI Appliance Installer (llama.cpp + OpenWebUI) v$SCRIPT_VERSION"
echo "============================================================"

# --------------------------------------------------------
# Validate root
# --------------------------------------------------------
if [[ $EUID -ne 0 ]]; then
    echo "ERROR: This script must run as root. Exiting."
    exit 1
fi

# --------------------------------------------------------
# Paths
# --------------------------------------------------------
INSTALL_DIR="/opt/llama.cpp"
MODEL_DIR="/srv/ai/models"
MODEL_FILE="$MODEL_DIR/Meta-Llama-3-8B.gguf"
OPENWEBUI_DIR="/srv/openwebui"
PROFILE="/root/.bashrc"

mkdir -p "$MODEL_DIR" "$OPENWEBUI_DIR"

# --------------------------------------------------------
# System update
# --------------------------------------------------------
echo "=== Updating system ==="
apt update
apt upgrade -y
apt autoremove -y
apt autoclean -y

# --------------------------------------------------------
# Install dependencies
# --------------------------------------------------------
echo "=== Installing required packages ==="
apt install -y \
    build-essential cmake git python3 python3-venv python3-pip \
    wget curl libomp-dev pkg-config libcurl4-openssl-dev \
    huggingface-hub

# --------------------------------------------------------
# Detect GPU / CUDA
# --------------------------------------------------------
GPU_TYPE="cpu"
CUDA_AVAILABLE=false

if command -v nvidia-smi >/dev/null 2>&1; then
    if [[ -x "/usr/local/cuda/bin/nvcc" ]]; then
        GPU_TYPE="nvidia"
        CUDA_AVAILABLE=true
        echo "Detected NVIDIA GPU with CUDA available."
    else
        echo "NVIDIA GPU detected but nvcc missing — CPU build only."
    fi
fi

# --------------------------------------------------------
# Remove previous install
# --------------------------------------------------------
echo "=== Removing old llama.cpp (if any) ==="
rm -rf "$INSTALL_DIR"
mkdir -p "$INSTALL_DIR"

# --------------------------------------------------------
# Clone llama.cpp
# --------------------------------------------------------
echo "=== Cloning llama.cpp ==="
git clone https://github.com/ggerganov/llama.cpp.git "$INSTALL_DIR"

# --------------------------------------------------------
# Build llama.cpp
# --------------------------------------------------------
echo "=== Building llama.cpp ==="
cd "$INSTALL_DIR"
mkdir -p build
cd build

CMAKE_FLAGS="-DLLAMA_CURL=ON -DCMAKE_BUILD_TYPE=Release"

if [[ "$CUDA_AVAILABLE" == true ]]; then
    echo "Building with CUDA support..."
    CMAKE_FLAGS="$CMAKE_FLAGS -DLLAMA_ENABLE_GPU=ON -DCMAKE_CUDA_COMPILER=/usr/local/cuda/bin/nvcc"
else
    echo "Building CPU-only version..."
    CMAKE_FLAGS="$CMAKE_FLAGS -DLLAMA_ENABLE_GPU=OFF"
fi

cmake .. $CMAKE_FLAGS
cmake --build . --config Release -j"$(nproc)"

echo "llama.cpp build complete."

# --------------------------------------------------------
# Ensure binaries on PATH
# --------------------------------------------------------
echo "export PATH=\$PATH:$INSTALL_DIR/build/bin" >> "$PROFILE"
export PATH=$PATH:"$INSTALL_DIR/build/bin"

ln -sf "$INSTALL_DIR/build/bin/llama-cli" /usr/local/bin/llama-cli
ln -sf "$INSTALL_DIR/build/bin/llama-server" /usr/local/bin/llama-server
ln -sf "$INSTALL_DIR/build/bin/llama-cli" /usr/local/bin/llama

# --------------------------------------------------------
# Download model using HuggingFace CLI
# --------------------------------------------------------
echo "=== Checking for model: $MODEL_FILE ==="

if [[ ! -f "$MODEL_FILE" ]]; then
    echo "Model not found. Downloading via HuggingFace CLI..."

    # Export token if provided
    if [[ -n "${HUGGINGFACE_HUB_TOKEN:-}" ]]; then
        export HUGGINGFACE_HUB_TOKEN="${HUGGINGFACE_HUB_TOKEN}"
        echo "Using HuggingFace token."
    else
        echo "WARNING: No HuggingFace token set — public models only."
    fi

    huggingface-cli download meta-llama/Meta-Llama-3-8B \
        --include "*.gguf" \
        --local-dir "$MODEL_DIR" \
        --local-dir-use-symlinks False

    if [[ -f "$MODEL_FILE" ]]; then
        echo "Model downloaded successfully: $MODEL_FILE"
    else
        echo
        echo "*******************************************************************"
        echo "MODEL DOWNLOAD FAILED"
        echo "Manually download:"
        echo "  https://huggingface.co/meta-llama/Meta-Llama-3-8B"
        echo "Place file here:"
        echo "  $MODEL_FILE"
        echo "*******************************************************************"
        echo
    fi
else
    echo "Model already exists: $MODEL_FILE"
fi

# --------------------------------------------------------
# Install OpenWebUI
# --------------------------------------------------------
echo "=== Installing OpenWebUI ==="
python3 -m venv "$OPENWEBUI_DIR/venv"
source "$OPENWEBUI_DIR/venv/bin/activate"
pip install --upgrade pip
pip install open-webui
deactivate

# --------------------------------------------------------
# Systemd: llama-server
# --------------------------------------------------------
echo "=== Installing llama-server systemd service ==="

cat > /etc/systemd/system/llama-server.service <<EOF
[Unit]
Description=llama-server — Llama.cpp inference server
After=network-online.target
Wants=network-online.target

[Service]
ExecStart=/usr/local/bin/llama-server \\
    --model $MODEL_FILE \\
    --host 0.0.0.0 \\
    --port 8081
Restart=always
WorkingDirectory=$MODEL_DIR

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now llama-server.service

# --------------------------------------------------------
# Systemd: OpenWebUI
# --------------------------------------------------------
echo "=== Installing OpenWebUI systemd service ==="

cat > /etc/systemd/system/openwebui.service <<EOF
[Unit]
Description=OpenWebUI
After=network-online.target llama-server.service
Requires=llama-server.service

[Service]
Type=simple
WorkingDirectory=$OPENWEBUI_DIR
ExecStart=$OPENWEBUI_DIR/venv/bin/open-webui serve \\
    --host 0.0.0.0 \\
    --port 8080 \\
    --models-dir $MODEL_DIR
Restart=always

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now openwebui.service

# --------------------------------------------------------
# Finished
# --------------------------------------------------------
echo "============================================================"
echo "AI Appliance Installation Complete!"
echo "Version: $SCRIPT_VERSION"
echo
echo "llama-server running on:  http://localhost:8081"
echo "OpenWebUI running on:     http://localhost:8080"
echo
echo "Model directory:"
echo "  $MODEL_DIR"
echo
echo "Log file:"
echo "  $LOG_FILE"
echo "============================================================"
