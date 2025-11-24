#!/usr/bin/env bash
#
# 11-install-llama-openwebui.sh — Version 0.44
# Author: Kevin Price
# Updated: 2025-11-24
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

SCRIPT_VERSION="0.44"
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
apt-get update
apt-get upgrade -y
apt-get autoremove -y
apt-get autoclean -y

# --------------------------------------------------------
# Install dependencies
# --------------------------------------------------------
echo "=== Installing required packages ==="
apt-get install -y \
    build-essential cmake git python3 python3-venv python3-pip \
    wget curl libomp-dev pkg-config libcurl4-openssl-dev

# --------------------------------------------------------
# Install CUDA runtime (lightweight) if NVIDIA GPU present
# --------------------------------------------------------
GPU_TYPE="cpu"
CUDA_AVAILABLE=false

if command -v nvidia-smi >/dev/null 2>&1; then
    echo "=== NVIDIA GPU detected ==="
    nvidia-smi --query-gpu=name,driver_version,memory.total --format=csv
    if ! command -v nvcc >/dev/null 2>&1; then
        echo "Installing CUDA runtime..."
        wget -q https://developer.download.nvidia.com/compute/cuda/repos/wsl-ubuntu/x86_64/cuda-keyring_1.1-1_all.deb
        dpkg -i cuda-keyring_1.1-1_all.deb
        apt-get update
        apt-get install -y cuda-nvcc-12-6 cuda-cudart-dev-12-6 libcublas-12-6 libcublas-dev-12-6
        echo 'export PATH=/usr/local/cuda/bin:$PATH' >> "$PROFILE"
        echo 'export LD_LIBRARY_PATH=/usr/local/cuda/lib64:${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}' >> "$PROFILE"
        export PATH=/usr/local/cuda/bin:$PATH
        export LD_LIBRARY_PATH=/usr/local/cuda/lib64${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
    fi
    if [[ -x "/usr/local/cuda/bin/nvcc" ]]; then
        GPU_TYPE="nvidia"
        CUDA_AVAILABLE=true
        echo "✓ CUDA toolkit found - will build with GPU acceleration"
    else
        echo "⚠ CUDA toolkit missing. Falling back to CPU build"
    fi
else
    echo "No NVIDIA GPU detected - building CPU-only version"
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
    CMAKE_FLAGS="$CMAKE_FLAGS -DLLAMA_CUDA=ON -DCMAKE_CUDA_COMPILER=/usr/local/cuda/bin/nvcc"
else
    echo "Building CPU-only version..."
    CMAKE_FLAGS="$CMAKE_FLAGS -DLLAMA_CUDA=OFF"
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
# Install HuggingFace CLI via pip
# --------------------------------------------------------
echo "=== Installing HuggingFace CLI ==="
pip3 install --break-system-packages --upgrade huggingface-hub

# Detect HuggingFace CLI executable
HF_CLI=$(command -v hf || command -v huggingface || command -v huggingface-cli || true)
if [[ -z "$HF_CLI" ]]; then
    echo "ERROR: HuggingFace CLI not found. Install via: pip3 install huggingface-hub"
    exit 1
fi

# --------------------------------------------------------
# Download model
# --------------------------------------------------------
echo "=== Checking for model: $MODEL_FILE ==="
if [[ ! -f "$MODEL_FILE" ]]; then
    echo "Model not found. Downloading via HuggingFace CLI..."
    if [[ -n "${HUGGINGFACE_HUB_TOKEN:-}" ]]; then
        export HUGGINGFACE_HUB_TOKEN="${HUGGINGFACE_HUB_TOKEN}"
        echo "Using HuggingFace token."
    else
        echo "WARNING: No HuggingFace token set — public models only."
    fi

    $HF_CLI download meta-llama/Meta-Llama-3-8B \
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
