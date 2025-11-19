#!/usr/bin/env bash
# bootstrap-llamacpp-openwebui-v0.15.sh — Version 0.15
# Author: adapted for Kevin Price by ChatGPT
# Purpose:
#   - Build llama.cpp (auto-detect CUDA and auto-install CUDA silently if NVIDIA GPU exists)
#   - Install OpenWebUI into a venv
#   - Create systemd services:
#       /etc/systemd/system/llamacpp.service      (external llama.cpp server)
#       /etc/systemd/system/openwebui.service
#   - Default model: DeepSeek-R1 1.5B (attempts to download if HF_TOKEN is provided)
#
# Usage:
#   sudo bash ./bootstrap-llamacpp-openwebui-v0.15.sh
#
set -Eeuo pipefail
IFS=$'\n\t'

LOGFILE="/var/log/bootstrap-0.15.log"
exec > >(tee -a "${LOGFILE}") 2>&1

# Config
LLAMACPP_REPO="https://github.com/ggerganov/llama.cpp.git"
LLAMACPP_BRANCH="main"
OPENWEBUI_PIPPKG="open-webui"
PYTHON_MIN_VER="3.10"

OPT_DIR="/opt"
SRV_DIR="/srv"
LLAMACPP_OPT="${OPT_DIR}/llama.cpp"
OPENWEBUI_OPT="${OPT_DIR}/openwebui"
AI_MODELS_DIR="${SRV_DIR}/ai/models"
LLAMACPP_MODELS_DIR="${SRV_DIR}/llama.cpp/models"
OPENWEBUI_DATA_DIR="${SRV_DIR}/openwebui/data"

LLAMACPP_SERVICE="llamacpp.service"
OPENWEBUI_SERVICE="openwebui.service"

# Default model variables (DeepSeek-R1 1.5B)
# Note: automatic download requires HF_TOKEN environment variable.
DEFAULT_MODEL_NAME="deepseek-r1-1.5b.gguf"
DEFAULT_MODEL_REPO="deepseek/deepseek-r1-1.5b"   # huggingface repo id (may change)
DEFAULT_MODEL_TARGET="${AI_MODELS_DIR}/${DEFAULT_MODEL_NAME}"

# Helper functions
section(){ printf "\n%s\n %s\n%s\n\n" "==============================================================" "$1" "=============================================================="; }
require_root(){ if [ "$EUID" -ne 0 ]; then echo "This script requires root. Re-run with sudo."; exit 1; fi; }
mkdir_if_missing(){ local d="$1"; if [ ! -d "${d}" ]; then mkdir -p "${d}"; chown root:root "${d}"; chmod 0755 "${d}"; fi; }
safe_apt_update(){ apt-get update -y || true; }
pause_if_interactive(){ if [ -z "${AUTO:-}" ] && [ -t 0 ]; then read -rp $'\n⏸  Press ENTER to continue (or set AUTO=1 to skip)... ' -r || true; fi; }

# Begin
section "Bootstrap v0.15 — llama.cpp + OpenWebUI (CUDA auto-install: ON)"
date
echo "Logfile: ${LOGFILE}"
pause_if_interactive

require_root

########################################
# [0] basic users & dirs
########################################
section "[0/12] Create directories and aiuser"
mkdir_if_missing "${OPT_DIR}"
mkdir_if_missing "${SRV_DIR}"
mkdir_if_missing "${AI_MODELS_DIR}"
mkdir_if_missing "${LLAMACPP_MODELS_DIR}"
mkdir_if_missing "${OPENWEBUI_DATA_DIR}"

if ! id -u aiuser &>/dev/null; then
    useradd --system --no-create-home --shell /usr/sbin/nologin aiuser
    echo "Created system user: aiuser"
else
    echo "System user aiuser already exists"
fi

chown -R aiuser:aiuser "${SRV_DIR}"
chmod -R 0755 "${SRV_DIR}"

########################################
# [1] apt update + base packages
########################################
section "[1/12] Update & install build/runtime packages"
safe_apt_update

# modern Python + build tools (no python3-distutils)
apt-get install -y --no-install-recommends \
    build-essential cmake ninja-build git curl wget ca-certificates \
    pkg-config unzip zip jq lsb-release gnupg software-properties-common \
    python3 python3-pip python3-venv python3-dev \
    gcc g++ make libopenblas-dev libblas-dev liblapack-dev

# ensure pip is usable
python3 -m pip install --upgrade pip setuptools wheel || true

########################################
# [2] NVIDIA detection + optional auto-install CUDA
########################################
section "[2/12] NVIDIA/CUDA detection and (auto) install"
# Detect NVIDIA GPU (lspci)
HAS_NVIDIA_GPU=0
if command -v lspci >/dev/null 2>&1 && lspci | grep -i 'nvidia' >/dev/null 2>&1; then
    HAS_NVIDIA_GPU=1
fi

# Detect CUDA toolkit (nvcc or /usr/local/cuda)
HAS_CUDA=0
if command -v nvcc >/dev/null 2>&1 || [ -d "/usr/local/cuda" ]; then
    HAS_CUDA=1
fi

echo "NVIDIA GPU detected: ${HAS_NVIDIA_GPU}"
echo "CUDA toolkit detected: ${HAS_CUDA}"

# Auto-install CUDA silently if GPU exists and CUDA not found (you chose option B)
if [ "${HAS_NVIDIA_GPU}" -eq 1 ] && [ "${HAS_CUDA}" -eq 0 ]; then
    echo "NVIDIA GPU present but CUDA not found — attempting silent CUDA install..."
    # Try NVIDIA keyring + repository (targets Ubuntu 22.04/24.04 paths where possible)
    CUDA_KEYRING="/tmp/cuda-keyring.deb"
    CUDA_REPO_BASE="https://developer.download.nvidia.com/compute/cuda/repos"
    UB_REL="$(lsb_release -cs || echo ubuntu)"
    # map Ubuntu codename for repo path (best-effort)
    if [ -f "${CUDA_KEYRING}" ]; then rm -f "${CUDA_KEYRING}"; fi
    # Attempt to download a keyring for the detected distro family
    # Try known ubuntu2204 path first, fallback to ubuntu2004
    for REPO_DIST in "ubuntu2204" "ubuntu2004" "ubuntu2404"; do
        KEYRING_URL="${CUDA_REPO_BASE}/${REPO_DIST}/x86_64/cuda-keyring_1.1-1_all.deb"
        echo "Trying CUDA keyring: ${KEYRING_URL}"
        if wget -q --timeout=15 --tries=2 "${KEYRING_URL}" -O "${CUDA_KEYRING}"; then
            dpkg -i "${CUDA_KEYRING}" >/dev/null 2>&1 || true
            safe_apt_update
            # best-effort install runtime; allow failure and continue (will fall back to CPU)
            apt-get install -y --no-install-recommends cuda-runtime-12-4 || apt-get install -y --no-install-recommends cuda-toolkit-12-4 || true
            break
        fi
    done

    # re-check
    if command -v nvcc >/dev/null 2>&1 || [ -d "/usr/local/cuda" ]; then
        echo "CUDA appears to be installed."
        HAS_CUDA=1
    else
        echo "CUDA install attempt did not succeed (continuing; will build CPU-only)."
        HAS_CUDA=0
    fi
fi

########################################
# [3] Clone & build llama.cpp (CUDA or CPU)
########################################
section "[3/12] Clone & build llama.cpp"
pause_if_interactive

if [ ! -d "${LLAMACPP_OPT}" ]; then
    git clone --depth 1 --branch "${LLAMACPP_BRANCH}" "${LLAMACPP_REPO}" "${LLAMACPP_OPT}" || {
        echo "git clone failed; exiting"
        exit 1
    }
else
    echo "llama.cpp already exists; fetching latest (shallow)"
    (cd "${LLAMACPP_OPT}" && git fetch --depth=1 origin "${LLAMACPP_BRANCH}" && git reset --hard "origin/${LLAMACPP_BRANCH}") || true
fi

cd "${LLAMACPP_OPT}"
mkdir -p build
cd build

if [ "${HAS_CUDA}" -eq 1 ]; then
    echo "Building llama.cpp with CUDA/cuBLAS support..."
    # Attempt to enable cublas/cuda through CMake flags used by llama.cpp
    cmake -S .. -B . -G Ninja -DLLAMA_CUBLAS=ON -DCMAKE_BUILD_TYPE=Release || {
        echo "CMake (CUDA) configure failed; retrying CPU-only configure..."
        cmake -S .. -B . -G Ninja -DCMAKE_BUILD_TYPE=Release
    }
else
    echo "Building CPU-only optimized llama.cpp..."
    cmake -S .. -B . -G Ninja -DCMAKE_BUILD_TYPE=Release
fi

# build
if ! ninja -v; then
    echo "Build failed. If CUDA was enabled, trying a CPU-only rebuild..."
    cmake -S .. -B . -G Ninja -DCMAKE_BUILD_TYPE=Release || true
    ninja -v || { echo "Final build attempt failed; exit."; exit 1; }
fi

# copy binary to /opt location
LLAMA_BIN_DIR="${LLAMACPP_OPT}/bin"
mkdir -p "${LLAMA_BIN_DIR}"
# The built binary is commonly called main (project may vary). Copy/update.
if [ -f "${LLAMACPP_OPT}/main" ]; then
    cp -u "${LLAMACPP_OPT}/main" "${LLAMA_BIN_DIR}/llamacpp" 2>/dev/null || true
elif [ -f "${LLAMACPP_OPT}/build/main" ]; then
    cp -u "${LLAMACPP_OPT}/build/main" "${LLAMA_BIN_DIR}/llamacpp" 2>/dev/null || true
fi
chmod +x "${LLAMA_BIN_DIR}/llamacpp"
ln -sf "${LLAMA_BIN_DIR}/llamacpp" /usr/local/bin/llamacpp || true

echo "llama.cpp built and installed to ${LLAMA_BIN_DIR}"
pause_if_interactive

########################################
# [4] Create llama.cpp run wrapper (external server)
########################################
section "[4/12] Create llama.cpp server wrapper"
# This wrapper is a best-effort example. Adjust flags if your build expects different CLI.
mkdir -p "${LLAMACPP_OPT}/bin"
cat > "${LLAMACPP_OPT}/bin/llamacpp-run" <<'EOF'
#!/usr/bin/env bash
# wrapper to run llama.cpp as a "server" for OpenWebUI.
# NOTE: Adjust parameters to match your llama.cpp version if needed.

MODEL_PATH="${1:-/srv/ai/models/deepseek-r1-1.5b.gguf}"
PORT="${2:-8081}"
THREADS="${3:-$(nproc)}"

# If model file missing, warn and exit (systemd will show logs)
if [ ! -f "${MODEL_PATH}" ]; then
    echo "ERROR: Model not found at ${MODEL_PATH}"
    echo "Place the model there or edit this wrapper to point to the correct model path."
    exit 2
fi

# Common flags — adjust if your build supports different options
# Some builds might have a dedicated server example. Use it if available.
# This attempts to run the built binary with model and a listening port (best-effort).
exec /usr/local/bin/llamacpp -m "${MODEL_PATH}" --threads "${THREADS}" --port "${PORT}"
EOF
chmod +x "${LLAMACPP_OPT}/bin/llamacpp-run"
ln -sf "${LLAMACPP_OPT}/bin/llamacpp-run" /usr/local/bin/llamacpp-run || true

########################################
# [5] Install OpenWebUI (venv)
########################################
section "[5/12] Install OpenWebUI into a venv"
pause_if_interactive

if [ ! -d "${OPENWEBUI_OPT}" ]; then
    mkdir -p "${OPENWEBUI_OPT}"
    chown root:root "${OPENWEBUI_OPT}"
fi

OPENWEBUI_VENV="${OPENWEBUI_OPT}/venv"
if [ ! -d "${OPENWEBUI_VENV}" ]; then
    python3 -m venv "${OPENWEBUI_VENV}"
fi

# activate and install
# shellcheck disable=SC1090
source "${OPENWEBUI_VENV}/bin/activate"
pip install --upgrade pip setuptools wheel
# OpenWebUI upstream package name is sometimes different; using provided name
pip install --break-system-packages --upgrade "${OPENWEBUI_PIPPKG}" || {
    echo "Warning: pip install ${OPENWEBUI_PIPPKG} had non-zero exit code; continuing."
}
deactivate

# create a run wrapper
mkdir -p "${OPENWEBUI_OPT}/bin"
cat > "${OPENWEBUI_OPT}/bin/openwebui-run" <<'EOF'
#!/usr/bin/env bash
BASE_DIR="$(dirname "$(dirname "$0")")"
source "${BASE_DIR}/venv/bin/activate"
# serve on 0.0.0.0:8080 by default
exec open-webui serve --host 0.0.0.0 --port 8080
EOF
chmod +x "${OPENWEBUI_OPT}/bin/openwebui-run"
ln -sf "${OPENWEBUI_OPT}/bin/openwebui-run" /usr/local/bin/openwebui-run || true

# ensure data dir and ownership
mkdir -p "${OPENWEBUI_DATA_DIR}"
chown -R aiuser:aiuser "${OPENWEBUI_DATA_DIR}"

########################################
# [6] Model download (attempt) — uses HF_TOKEN if available
########################################
section "[6/12] Attempt to download default model (DeepSeek-R1 1.5B)"
pause_if_interactive

if [ -n "${HF_TOKEN:-}" ]; then
    echo "HF_TOKEN detected — attempting model download using huggingface_hub"
    python3 - <<PY
from huggingface_hub import hf_hub_download
import os,sys
repo_id = os.environ.get("HF_REPO","${DEFAULT_MODEL_REPO}")
fname = "${DEFAULT_MODEL_NAME}"
target_dir = "${AI_MODELS_DIR}"
os.makedirs(target_dir, exist_ok=True)
try:
    print("Downloading", fname, "from", repo_id)
    path = hf_hub_download(repo_id=repo_id, filename=fname, cache_dir=target_dir, token=os.environ.get("HF_TOKEN"))
    print("Downloaded to:", path)
except Exception as e:
    print("Model download failed:", e)
    sys.exit(1)
PY

    # ensure proper ownership
    chown -R aiuser:aiuser "${AI_MODELS_DIR}"
else
    echo "HF_TOKEN not set — skipping automatic model download."
    echo "To download DeepSeek-R1 1.5B automatically, export HF_TOKEN and re-run."
    echo "Example:"
    echo "  export HF_TOKEN='hf_xxx' && sudo bash ./bootstrap-llamacpp-openwebui-v0.15.sh"
    echo "Alternately, manually place the gguf file at: ${DEFAULT_MODEL_TARGET}"
fi

########################################
# [7] Create systemd service for llama.cpp
########################################
section "[7/12] Create systemd service for llama.cpp (external server)"
LLAMA_SYSTEMD_PATH="/etc/systemd/system/${LLAMACPP_SERVICE}"
cat > "${LLAMA_SYSTEMD_PATH}" <<EOF
[Unit]
Description=llama.cpp external server (best-effort wrapper)
After=network.target
After=local-fs.target

[Service]
Type=simple
User=aiuser
Group=aiuser
WorkingDirectory=${LLAMACPP_OPT}
# ExecStart uses wrapper which will call /usr/local/bin/llamacpp
ExecStart=${LLAMACPP_OPT}/bin/llamacpp-run ${DEFAULT_MODEL_TARGET} 8081
Restart=on-failure
RestartSec=5s
LimitNOFILE=65536
StartLimitIntervalSec=60
StartLimitBurst=5

[Install]
WantedBy=multi-user.target
EOF

chmod 644 "${LLAMA_SYSTEMD_PATH}"

########################################
# [8] Create systemd service for OpenWebUI
########################################
section "[8/12] Create systemd service for OpenWebUI"
OPENWEBUI_SYSTEMD_PATH="/etc/systemd/system/${OPENWEBUI_SERVICE}"
cat > "${OPENWEBUI_SYSTEMD_PATH}" <<EOF
[Unit]
Description=OpenWebUI (Python venv)
After=network.target
After=llamacpp.service

[Service]
Type=simple
User=aiuser
Group=aiuser
WorkingDirectory=${OPENWEBUI_OPT}
ExecStart=${OPENWEBUI_OPT}/bin/openwebui-run
Restart=on-failure
RestartSec=5s
Environment=OPENWEBUI_DATA_DIR=${OPENWEBUI_DATA_DIR}
LimitNOFILE=65536
# Allow OpenWebUI to start after llama.cpp comes up
StartLimitIntervalSec=60
StartLimitBurst=5

[Install]
WantedBy=multi-user.target
EOF

chmod 644 "${OPENWEBUI_SYSTEMD_PATH}"

# reload systemd daemon
systemctl daemon-reload || true

########################################
# [9] Enable & start services (if systemd active)
########################################
section "[9/12] Enable and start services (systemd)"
# Check if systemd is available and running
if pidof systemd >/dev/null 2>&1; then
    echo "systemd detected — enabling and starting services..."
    systemctl enable --now "${LLAMACPP_SERVICE}" || echo "Warning: enabling/starting ${LLAMACPP_SERVICE} failed."
    # wait a bit for llama.cpp to start
    sleep 3
    systemctl enable --now "${OPENWEBUI_SERVICE}" || echo "Warning: enabling/starting ${OPENWEBUI_SERVICE} failed."
else
    echo "systemd not detected/running in this environment. You must start the services manually or enable systemd in WSL."
    echo "Manual start examples:"
    echo "  sudo -u aiuser ${LLAMACPP_OPT}/bin/llamacpp-run ${DEFAULT_MODEL_TARGET} 8081 &"
    echo "  sudo -u aiuser ${OPENWEBUI_OPT}/bin/openwebui-run &"
fi

########################################
# [10] Quick verification notes
########################################
section "[10/12] Quick verification"
echo "Commands to check status:"
echo "  systemctl status ${LLAMACPP_SERVICE} --no-pager"
echo "  systemctl status ${OPENWEBUI_SERVICE} --no-pager"
echo "  journalctl -u ${LLAMACPP_SERVICE} -n 200 --no-pager"
echo "  journalctl -u ${OPENWEBUI_SERVICE} -n 200 --no-pager"
echo "OpenWebUI should be available at http://<wsl-ip>:8080"
echo "llama.cpp external server (if running) should listen at port 8081"
pause_if_interactive

########################################
# [11] Cleanup & final notes
########################################
section "[11/12] Cleanup & notes"
apt-get autoremove -y || true
apt-get clean || true

cat <<EOF

Bootstrap v0.15 completed (best-effort).

Summary:
• llama.cpp built at: ${LLAMACPP_OPT}
  - binary symlink: /usr/local/bin/llamacpp
  - wrapper: /usr/local/bin/llamacpp-run (calls ${LLAMACPP_OPT}/bin/llamacpp-run)
  - default model: ${DEFAULT_MODEL_TARGET} (attempted download only if HF_TOKEN set)

• OpenWebUI installed in venv at: ${OPENWEBUI_OPT}
  - run via: openwebui-run (symlinked to /usr/local/bin/openwebui-run)
  - data dir: ${OPENWEBUI_DATA_DIR}

• Systemd services created:
  - ${LLAMACPP_SERVICE}
  - ${OPENWEBUI_SERVICE}
  (Enabled and started if systemd is active.)

Notes & next steps:
1) If HF_TOKEN was not provided, manually place the model:
     sudo mkdir -p ${AI_MODELS_DIR}
     sudo chown aiuser:aiuser ${AI_MODELS_DIR}
     sudo cp /path/to/deepseek-r1-1.5b.gguf ${DEFAULT_MODEL_TARGET}
     sudo chown aiuser:aiuser ${DEFAULT_MODEL_TARGET}
   Then restart the service:
     sudo systemctl restart ${LLAMACPP_SERVICE}

2) If llama.cpp fails to start due to CLI flag differences, edit:
     ${LLAMACPP_OPT}/bin/llamacpp-run
   adjust exec line to the correct flags for your compiled build.

3) If you want a CPU-only build regardless of CUDA detection, re-run the build step
   with HAS_CUDA=0, or edit the cmake configure command.

Log file: ${LOGFILE}

EOF

########################################
# [12] Finish
########################################
section "[12/12] Done"
echo "Bootstrap finished at: $(date)"
echo "Inspect ${LOGFILE} and journalctl for service logs."
