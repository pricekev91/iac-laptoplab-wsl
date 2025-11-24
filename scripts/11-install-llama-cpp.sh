#!/usr/bin/env bash
#
# Llama.cpp + OpenWebUI Installer — Version v0.463
# Author: Kevin Price
# Updated: 2025-11-24
#
# RAW OUTPUT version — no suppressed build logs.

set -e

INSTALL_DIR="/srv/ai"
LLAMA_DIR="${INSTALL_DIR}/llama.cpp"
MODEL_DIR="${INSTALL_DIR}/models"
OPENWEBUI_DIR="${INSTALL_DIR}/open-webui"
MODEL_URL="https://huggingface.co/QuantFactory/Meta-Llama-3-8B-Instruct-GGUF/resolve/main/Meta-Llama-3-8B-Instruct.Q4_0.gguf"
MODEL_FILE="Meta-Llama-3-8B-Instruct.Q4_0.gguf"

echo "=== Llama.cpp Bootstrap v0.462 ==="
echo "Running on: $(uname -a)"
echo ""

###############################################
# Ensure sudo exists (WSL often missing sudo)
###############################################
if ! command -v sudo >/dev/null 2>&1; then
    echo "[WSL] sudo not found. Installing minimal sudo..."
    apt update && apt install -y sudo
fi

###############################################
# Install dependencies
###############################################
echo "=== Installing Dependencies ==="
sudo apt update
sudo apt install -y \
    git cmake build-essential python3 python3-pip \
    python3-venv curl unzip wget

###############################################
# Prepare folder structure
###############################################
sudo mkdir -p "${INSTALL_DIR}"
sudo mkdir -p "${MODEL_DIR}"
sudo chown -R $USER:$USER "${INSTALL_DIR}"

###############################################
# Clone or update llama.cpp
###############################################
echo "=== Syncing llama.cpp ==="

if [ ! -d "${LLAMA_DIR}" ]; then
    echo "[Clone] llama.cpp directory not found. Cloning fresh..."
    git clone https://github.com/ggerganov/llama.cpp.git "${LLAMA_DIR}"
else
    echo "[Update] llama.cpp exists — updating..."
    cd "${LLAMA_DIR}"
    git reset --hard
    git pull --rebase origin master
fi

###############################################
# Build llama.cpp (RAW full output)
###############################################
echo ""
echo "=== Building llama.cpp (CUDA, RAW output) ==="
cd "${LLAMA_DIR}"
mkdir -p build
cd build

echo "[CMAKE] Running CMake with CUDA..."
cmake .. -DGGML_CUDA=ON -DCMAKE_BUILD_TYPE=Release

echo "[MAKE] Compiling — this will show ALL build lines..."
make -j"$(nproc)"

###############################################
# Download model
###############################################
cd "${MODEL_DIR}"

if [ ! -f "${MODEL_FILE}" ]; then
    echo "=== Downloading Model ==="
    curl -L -o "${MODEL_FILE}" "${MODEL_URL}"
else
    echo "Model already exists: ${MODEL_FILE}"
fi

###############################################
# Install OpenWebUI
###############################################
echo "=== Installing OpenWebUI ==="
cd "${INSTALL_DIR}"

if [ ! -d "${OPENWEBUI_DIR}" ]; then
    git clone https://github.com/open-webui/open-webui.git "${OPENWEBUI_DIR}"
else
    cd "${OPENWEBUI_DIR}"
    git pull --rebase
fi

echo "=== Python Venv setup ==="
cd "${OPENWEBUI_DIR}"
python3 -m venv venv
source venv/bin/activate
pip install --upgrade pip
pip install -r requirements.txt

###############################################
# Systemd services (WSL-safe)
###############################################
echo "=== Creating systemd services (WSL-aware) ==="

SERVICE1=/etc/systemd/system/llama.service
SERVICE2=/etc/systemd/system/openwebui.service

sudo bash -c "cat > $SERVICE1" <<EOF
[Unit]
Description=Llama.cpp Server
After=network.target

[Service]
Type=simple
WorkingDirectory=${LLAMA_DIR}/build/bin
ExecStart=${LLAMA_DIR}/build/bin/llama-server -m ${MODEL_DIR}/${MODEL_FILE} --port 9999 --n-gpu-layers 999
Restart=always

[Install]
WantedBy=multi-user.target
EOF

sudo bash -c "cat > $SERVICE2" <<EOF
[Unit]
Description=OpenWebUI
After=network.target llama.service

[Service]
Type=simple
WorkingDirectory=${OPENWEBUI_DIR}
ExecStart=${OPENWEBUI_DIR}/venv/bin/python app.py
Environment="LLAMA_SERVER=http://localhost:9999"
Restart=always

[Install]
WantedBy=multi-user.target
EOF

echo "=== Enabling services (WSL will fake-enable) ==="
sudo systemctl daemon-reload || true
sudo systemctl enable llama.service || true
sudo systemctl enable openwebui.service || true

echo ""
echo "==============================================="
echo "    Installation Complete - v0.462"
echo "==============================================="
echo "llama.cpp model: ${MODEL_DIR}/${MODEL_FILE}"
echo "OpenWebUI installed at: ${OPENWEBUI_DIR}"
echo ""
echo "Start manually under WSL with:"
echo "    systemctl start llama || true"
echo "    systemctl start openwebui || true"
echo ""
echo "Open OpenWebUI in browser:"
echo "    http://localhost:8080"
echo ""
echo "Done."
