#!/usr/bin/env bash
# bootstrap-llamacpp-openwebui.sh — Version 0.18
# Purpose: Install llama.cpp + OpenWebUI with optional CUDA GPU acceleration
# Author: Kevin Price
# Changelog:
#   v0.18 - Added CUDA toolkit auto-install, systemd service setup, improved GPU detection

set -euo pipefail
IFS=$'\n\t'

LOGFILE="/root/bootstrap-llamacpp.log"
AUTO=${AUTO:-0}

echo "=============================================================="
echo " Bootstrap: llama.cpp + OpenWebUI (v0.18)"
echo "=============================================================="
echo "Logfile: $LOGFILE"
echo ""

pause() {
  if [[ "$AUTO" -eq 0 ]]; then
    read -rp "⏸  Press ENTER to continue (or set AUTO=1 to skip)..."
  fi
}

echo "Starting bootstrap..."
pause

# ========================
# [0/12] Prepare directories and user
# ========================
echo "Creating directories and service user..."
mkdir -p /opt/llama.cpp /opt/openwebui /srv/llama/models
useradd -m -s /bin/bash aiuser || true
pause

# ========================
# [1/12] Update & install build/runtime packages
# ========================
echo "[INFO] Installing prerequisites..."
apt update
apt install -y \
  build-essential cmake git wget curl unzip python3 python3-pip python3-venv \
  ffmpeg libglib2.0-0 libsm6 libxext6 libxrender-dev
pause

# ========================
# [2/12] NVIDIA/CUDA detection
# ========================
echo "[INFO] Detecting NVIDIA GPU..."
GPU_COUNT=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | wc -l || echo 0)
if [[ "$GPU_COUNT" -gt 0 ]]; then
    echo "NVIDIA GPU detected: $GPU_COUNT"
    if ! command -v nvcc &>/dev/null; then
        echo "CUDA toolkit not found. Installing..."
        apt install -y nvidia-cuda-toolkit
    fi
    echo "CUDA version:"
    nvcc --version
    BUILD_MODE="cuda"
else
    echo "No NVIDIA GPU detected. Falling back to CPU-only mode."
    BUILD_MODE="cpu"
fi
pause

# ========================
# [3/12] Clone llama.cpp
# ========================
echo "[INFO] Cloning llama.cpp repository..."
if [[ ! -d /opt/llama.cpp/.git ]]; then
    git clone --branch master https://github.com/ggerganov/llama.cpp.git /opt/llama.cpp
else
    echo "Repository already exists. Pulling latest..."
    cd /opt/llama.cpp && git fetch && git reset --hard origin/master
fi
pause

# ========================
# [4/12] Build llama.cpp
# ========================
echo "[INFO] Building llama.cpp ($BUILD_MODE mode)..."
cd /opt/llama.cpp
mkdir -p build
cd build
set +e
cmake -DCMAKE_BUILD_TYPE=Release -DLLAMA_CUBLAS=OFF -DGGML_CUDA=$( [[ "$BUILD_MODE" == "cuda" ]] && echo "ON" || echo "OFF" ) ..
cmake --build . -j$(nproc)
BUILD_STATUS=$?
set -e

if [[ "$BUILD_STATUS" -ne 0 && "$BUILD_MODE" == "cuda" ]]; then
    echo "[WARN] CUDA build failed. Retrying CPU-only build..."
    cmake -DCMAKE_BUILD_TYPE=Release -DLLAMA_CUBLAS=OFF -DGGML_CUDA=OFF ..
    cmake --build . -j$(nproc)
fi
pause

# ========================
# [5/12] Clone OpenWebUI
# ========================
echo "[INFO] Cloning OpenWebUI..."
if [[ ! -d /opt/openwebui/.git ]]; then
    git clone https://github.com/suno-ai/openwebui.git /opt/openwebui
else
    echo "OpenWebUI repo exists. Pulling latest..."
    cd /opt/openwebui && git fetch && git reset --hard origin/main
fi
pause

# ========================
# [6/12] Python environment for OpenWebUI
# ========================
echo "[INFO] Creating Python virtual environment for OpenWebUI..."
python3 -m venv /opt/openwebui/venv
source /opt/openwebui/venv/bin/activate
pip install --upgrade pip
pip install -r /opt/openwebui/requirements.txt
deactivate
pause

# ========================
# [7/12] Setup systemd services
# ========================
echo "[INFO] Setting up systemd services..."

cat >/etc/systemd/system/llamacpp.service <<'EOF'
[Unit]
Description=llama.cpp Server
After=network.target

[Service]
Type=simple
User=aiuser
WorkingDirectory=/opt/llama.cpp
ExecStart=/opt/llama.cpp/build/main -m /srv/llama/models
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

cat >/etc/systemd/system/openwebui.service <<'EOF'
[Unit]
Description=OpenWebUI
After=network.target llamacpp.service

[Service]
Type=simple
User=aiuser
WorkingDirectory=/opt/openwebui
ExecStart=/opt/openwebui/venv/bin/python main.py --host 0.0.0.0 --port 8080
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable llamacpp
systemctl enable openwebui
pause

# ========================
# [8/12] Final notes
# ========================
echo "=============================================================="
echo "[INFO] Bootstrap complete. You can start services with:"
echo "  sudo systemctl start llamacpp"
echo "  sudo systemctl start openwebui"
echo ""
echo "[INFO] Check logs with:"
echo "  sudo journalctl -u llamacpp -f"
echo "  sudo journalctl -u openwebui -f"
echo "=============================================================="
pause
