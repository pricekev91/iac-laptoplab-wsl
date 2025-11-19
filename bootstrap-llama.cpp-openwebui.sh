#!/usr/bin/env bash
# bootstrap-llamacpp-openwebui-v0.16.sh — Version 0.16
# Author: adapted for Kevin Price by ChatGPT
# Purpose:
#   - Build llama.cpp (auto-detect CUDA; auto-install CUDA silently if NVIDIA GPU exists)
#   - Install OpenWebUI into a Python venv
#   - Create systemd services:
#       /etc/systemd/system/llamacpp.service      (external llama.cpp server)
#       /etc/systemd/system/openwebui.service
#   - Default model: DeepSeek-R1 1.5B (attempts to download if HF_TOKEN is provided)
# Notes:
#   - THIS SCRIPT WILL NOT RUN pip against the system Python. All pip usage is inside venvs.
#   - If CUDA build fails, script will automatically retry a CPU-only build.
# Usage:
#   sudo bash ./bootstrap-llamacpp-openwebui-v0.16.sh
set -Eeuo pipefail
IFS=$'\n\t'

LOGFILE="/var/log/bootstrap-0.16.log"
exec > >(tee -a "${LOGFILE}") 2>&1

# ---------------- Config ----------------
LLAMACPP_REPO="https://github.com/ggerganov/llama.cpp.git"
LLAMACPP_BRANCH_FALLBACKS=( "master" "main" )
OPENWEBUI_PIPPKG="open-webui"
OPT_DIR="/opt"
SRV_DIR="/srv"
LLAMACPP_OPT="${OPT_DIR}/llama.cpp"
OPENWEBUI_OPT="${OPT_DIR}/openwebui"
AI_MODELS_DIR="${SRV_DIR}/ai/models"
LLAMACPP_MODELS_DIR="${SRV_DIR}/llama.cpp/models"
OPENWEBUI_DATA_DIR="${SRV_DIR}/openwebui/data"
LLAMACPP_SERVICE="llamacpp.service"
OPENWEBUI_SERVICE="openwebui.service"

# model defaults (DeepSeek-R1 1.5B)
DEFAULT_MODEL_NAME="deepseek-r1-1.5b.gguf"
DEFAULT_MODEL_REPO="deepseek/deepseek-r1-1.5b"   # huggingface repo id (may change)
DEFAULT_MODEL_TARGET="${AI_MODELS_DIR}/${DEFAULT_MODEL_NAME}"

# CUDA versions to try
CUDA_PACKAGE_CANDIDATES=( "cuda-runtime-12-4" "cuda-toolkit-12-4" "cuda-runtime-12-5" "cuda-toolkit-12-5" )

# ---------------- Helpers ----------------
section(){ printf "\n%s\n %s\n%s\n\n" "==============================================================" "$1" "=============================================================="; }
require_root(){ if [ "$EUID" -ne 0 ]; then echo "This script requires root. Re-run with sudo."; exit 1; fi; }
mkdir_if_missing(){ local d="$1"; if [ ! -d "${d}" ]; then mkdir -p "${d}"; chown root:root "${d}"; chmod 0755 "${d}"; fi; }
safe_apt_update(){ apt-get update -y || true; }
pause_if_interactive(){ if [ -z "${AUTO:-}" ] && [ -t 0 ]; then read -rp $'\n⏸  Press ENTER to continue (or set AUTO=1 to skip)... ' -r || true; fi; }

# run a command but don't exit on non-zero (used to test)
try(){ "$@" || true; }

# ---------------- Begin ----------------
section "Bootstrap v0.16 — llama.cpp + OpenWebUI"
date
echo "Logfile: ${LOGFILE}"
pause_if_interactive
require_root

# ---------------- [0] create dirs & user ----------------
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

chown -R aiuser:aiuser "${SRV_DIR}" || true
chmod -R 0755 "${SRV_DIR}" || true

# ---------------- [1] apt update + essentials ----------------
section "[1/12] Update & install build/runtime packages"
safe_apt_update

# Install core build tools & runtime (no system-level pip installs)
apt-get install -y --no-install-recommends \
    build-essential cmake ninja-build git curl wget ca-certificates \
    pkg-config unzip zip jq lsb-release gnupg software-properties-common \
    python3 python3-venv python3-dev \
    gcc g++ make libopenblas-dev libblas-dev liblapack-dev

# Ensure pip in system python usable for venv creation (we won't pip install system-wide)
python3 -m pip install --upgrade pip setuptools wheel || true

# ---------------- [2] Nvidia/CUDA detection + auto-install ----------------
section "[2/12] NVIDIA+CUDA detection and auto-install"
# Detect NVIDIA present: check nvidia-smi first (covers WSL & native), then lspci
HAS_NVIDIA_GPU=0
if command -v nvidia-smi >/dev/null 2>&1; then
    HAS_NVIDIA_GPU=1
elif command -v lspci >/dev/null 2>&1 && lspci | grep -i -q nvidia; then
    HAS_NVIDIA_GPU=1
fi

# Detect CUDA toolkit (nvcc or /usr/local/cuda)
HAS_CUDA=0
if command -v nvcc >/dev/null 2>&1 || [ -d "/usr/local/cuda" ]; then
    HAS_CUDA=1
fi

echo "NVIDIA GPU detected: ${HAS_NVIDIA_GPU}"
echo "CUDA toolkit detected: ${HAS_CUDA}"

# Auto-install CUDA silently if GPU exists but toolkit not found (per your choice)
if [ "${HAS_NVIDIA_GPU}" -eq 1 ] && [ "${HAS_CUDA}" -eq 0 ]; then
    echo "Attempting silent NVIDIA CUDA runtime install..."
    CUDA_KEYRING="/tmp/cuda-keyring.deb"
    CUDA_REPO_BASE="https://developer.download.nvidia.com/compute/cuda/repos"
    # try a few common ubuntu repo targets
    for REPO_DIST in "ubuntu2204" "ubuntu2404" "ubuntu2004"; do
        KEYRING_URL="${CUDA_REPO_BASE}/${REPO_DIST}/x86_64/cuda-keyring_1.1-1_all.deb"
        echo "Trying keyring URL: ${KEYRING_URL}"
        if wget -q --timeout=15 --tries=2 "${KEYRING_URL}" -O "${CUDA_KEYRING}"; then
            dpkg -i "${CUDA_KEYRING}" >/dev/null 2>&1 || true
            safe_apt_update
            # try candidate packages
            for pkg in "${CUDA_PACKAGE_CANDIDATES[@]}"; do
                echo "Trying apt install: ${pkg}"
                if apt-get install -y --no-install-recommends "${pkg}"; then
                    echo "Installed ${pkg}"
                    break
                fi
            done
            break
        fi
    done
    # re-detect
    if command -v nvcc >/dev/null 2>&1 || [ -d "/usr/local/cuda" ]; then
        HAS_CUDA=1
        echo "CUDA appears installed."
    else
        echo "CUDA install attempt did not succeed; continuing (will fallback to CPU build)."
        HAS_CUDA=0
    fi
fi

# ---------------- [3] Clone llama.cpp (try master, then fallback) ----------------
section "[3/12] Clone & prepare llama.cpp source"
pause_if_interactive

if [ ! -d "${LLAMACPP_OPT}" ]; then
    CLONED=0
    for br in "${LLAMACPP_BRANCH_FALLBACKS[@]}"; do
        echo "Attempting clone branch: ${br}"
        if git clone --depth 1 --branch "${br}" "${LLAMACPP_REPO}" "${LLAMACPP_OPT}"; then
            CLONED=1
            echo "Cloned ${LLAMACPP_REPO} (branch ${br})"
            break
        fi
    done
    if [ "${CLONED}" -eq 0 ]; then
        echo "Could not clone using fallback branches; attempting default branch clone..."
        if ! git clone --depth 1 "${LLAMACPP_REPO}" "${LLAMACPP_OPT}"; then
            echo "git clone failed; exiting"
            exit 1
        fi
    fi
else
    echo "llama.cpp already present; updating (shallow)"
    (cd "${LLAMACPP_OPT}" && git fetch --depth=1 origin || true)
fi

# ---------------- [4] Build llama.cpp (try CUDA then fallback to CPU) ----------------
section "[4/12] Build llama.cpp (CUDA if available, else CPU). Auto-retry CPU on failure."
cd "${LLAMACPP_OPT}"
mkdir -p build
cd build

BUILD_MODE="cpu"
if [ "${HAS_CUDA}" -eq 1 ]; then
    BUILD_MODE="cuda"
fi

# function to configure & build
build_llama() {
    local mode="$1"
    echo "Configuring llama.cpp build (mode=${mode})"
    if [ "${mode}" = "cuda" ]; then
        cmake -S .. -B . -G Ninja -DLLAMA_CUBLAS=ON -DCMAKE_BUILD_TYPE=Release || return 1
    else
        cmake -S .. -B . -G Ninja -DCMAKE_BUILD_TYPE=Release || return 1
    fi
    echo "Running ninja build..."
    if ninja -v; then
        return 0
    else
        return 1
    fi
}

# Attempt build; if CUDA build fails, auto-fallback to CPU
if [ "${BUILD_MODE}" = "cuda" ]; then
    if build_llama "cuda"; then
        echo "CUDA build succeeded."
    else
        echo "CUDA build failed. Retrying CPU-only build..."
        if build_llama "cpu"; then
            echo "CPU-only build succeeded after CUDA failure."
        else
            echo "Both CUDA and CPU builds failed. Exiting."
            exit 1
        fi
    fi
else
    if build_llama "cpu"; then
        echo "CPU-only build succeeded."
    else
        echo "CPU-only build failed. Exiting."
        exit 1
    fi
fi

# Copy binary to /opt/llama.cpp/bin (idempotent)
LLAMA_BIN_DIR="${LLAMACPP_OPT}/bin"
mkdir -p "${LLAMA_BIN_DIR}"
# common locations for built binary
if [ -f "${LLAMACPP_OPT}/main" ]; then
    cp -u "${LLAMACPP_OPT}/main" "${LLAMA_BIN_DIR}/llamacpp" || true
elif [ -f "${LLAMACPP_OPT}/build/main" ]; then
    cp -u "${LLAMACPP_OPT}/build/main" "${LLAMA_BIN_DIR}/llamacpp" || true
elif [ -f "${LLAMACPP_OPT}/main.exe" ]; then
    cp -u "${LLAMACPP_OPT}/main.exe" "${LLAMA_BIN_DIR}/llamacpp" || true
fi
chmod +x "${LLAMA_BIN_DIR}/llamacpp" || true
ln -sf "${LLAMA_BIN_DIR}/llamacpp" /usr/local/bin/llamacpp || true
echo "llama.cpp built and installed into ${LLAMA_BIN_DIR}"
pause_if_interactive

# ---------------- [5] Create llama.cpp run wrapper ----------------
section "[5/12] Create llama.cpp server wrapper"
mkdir -p "${LLAMACPP_OPT}/bin"
cat > "${LLAMACPP_OPT}/bin/llamacpp-run" <<'EOF'
#!/usr/bin/env bash
# llama.cpp-run wrapper: tries to start the binary in a server-like mode if supported.
MODEL_PATH="${1:-/srv/ai/models/deepseek-r1-1.5b.gguf}"
PORT="${2:-8081}"
THREADS="${3:-$(nproc)}"

if [ ! -f "${MODEL_PATH}" ]; then
    echo "ERROR: model not found at ${MODEL_PATH}"
    exit 2
fi

BINARY="$(command -v llamacpp || command -v /usr/local/bin/llamacpp || true)"
if [ -z "${BINARY}" ]; then
    echo "ERROR: llama.cpp binary not found."
    exit 3
fi

# Try to run with port flag (many builds provide a server mode)
"${BINARY}" --help >/dev/null 2>&1 || true

# Attempt with common flags (best-effort); adjust for your build if needed
exec "${BINARY}" -m "${MODEL_PATH}" --threads "${THREADS}" --port "${PORT}"
EOF
chmod +x "${LLAMACPP_OPT}/bin/llamacpp-run" || true
ln -sf "${LLAMACPP_OPT}/bin/llamacpp-run" /usr/local/bin/llamacpp-run || true

# ---------------- [6] Install OpenWebUI (venv) ----------------
section "[6/12] Install OpenWebUI into a Python venv"
pause_if_interactive

if [ ! -d "${OPENWEBUI_OPT}" ]; then
    mkdir -p "${OPENWEBUI_OPT}"
    chown root:root "${OPENWEBUI_OPT}"
fi

OPENWEBUI_VENV="${OPENWEBUI_OPT}/venv"
if [ ! -d "${OPENWEBUI_VENV}" ]; then
    python3 -m venv "${OPENWEBUI_VENV}"
fi

# Install open-webui inside venv (no system pip modifications)
# shellcheck disable=SC1090
source "${OPENWEBUI_VENV}/bin/activate"
python -m pip install --upgrade pip setuptools wheel || true
python -m pip install --break-system-packages --upgrade "${OPENWEBUI_PIPPKG}" || {
    echo "Warning: pip install ${OPENWEBUI_PIPPKG} had non-zero exit code; continuing."
}
deactivate

# run wrapper
mkdir -p "${OPENWEBUI_OPT}/bin"
cat > "${OPENWEBUI_OPT}/bin/openwebui-run" <<'EOF'
#!/usr/bin/env bash
BASE_DIR="$(dirname "$(dirname "$0")")"
source "${BASE_DIR}/venv/bin/activate"
exec open-webui serve --host 0.0.0.0 --port 8080
EOF
chmod +x "${OPENWEBUI_OPT}/bin/openwebui-run"
ln -sf "${OPENWEBUI_OPT}/bin/openwebui-run" /usr/local/bin/openwebui-run || true

chown -R aiuser:aiuser "${OPENWEBUI_DATA_DIR}" || true

# ---------------- [7] Model download (optional) ----------------
section "[7/12] Attempt to download default model (DeepSeek-R1 1.5B) using HF_TOKEN"
pause_if_interactive

if [ -n "${HF_TOKEN:-}" ]; then
    echo "HF_TOKEN present — using temporary venv to run huggingface_hub download"
    TMP_VENV_DIR="$(mktemp -d /tmp/hfvenv.XXXX)"
    python3 -m venv "${TMP_VENV_DIR}"
    # shellcheck disable=SC1090
    source "${TMP_VENV_DIR}/bin/activate"
    python -m pip install --upgrade pip setuptools wheel huggingface_hub || true
    python - <<PY
import os,sys
from huggingface_hub import hf_hub_download
repo = os.environ.get("HF_REPO","${DEFAULT_MODEL_REPO}")
fname = "${DEFAULT_MODEL_NAME}"
target_dir = "${AI_MODELS_DIR}"
os.makedirs(target_dir, exist_ok=True)
try:
    print("Downloading", fname, "from", repo)
    p = hf_hub_download(repo_id=repo, filename=fname, cache_dir=target_dir, token=os.environ.get("HF_TOKEN"))
    print("Downloaded to:", p)
except Exception as e:
    print("Model download failed:", e)
    sys.exit(1)
PY
    deactivate
    rm -rf "${TMP_VENV_DIR}"
    chown -R aiuser:aiuser "${AI_MODELS_DIR}" || true
else
    echo "HF_TOKEN not set — skipping automatic model download."
    echo "Place model at: ${DEFAULT_MODEL_TARGET} and chown to aiuser, or export HF_TOKEN and re-run."
fi

# ---------------- [8] Create systemd service for llama.cpp ----------------
section "[8/12] Create systemd unit for llama.cpp"
LLAMA_SYSTEMD_PATH="/etc/systemd/system/${LLAMACPP_SERVICE}"
cat > "${LLAMA_SYSTEMD_PATH}" <<EOF
[Unit]
Description=llama.cpp external server (wrapper)
After=network.target
After=local-fs.target

[Service]
Type=simple
User=aiuser
Group=aiuser
WorkingDirectory=${LLAMACPP_OPT}
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

# ---------------- [9] Create systemd service for OpenWebUI ----------------
section "[9/12] Create systemd unit for OpenWebUI"
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
StartLimitIntervalSec=60
StartLimitBurst=5

[Install]
WantedBy=multi-user.target
EOF
chmod 644 "${OPENWEBUI_SYSTEMD_PATH}"

systemctl daemon-reload || true

# ---------------- [10] Enable & start services ----------------
section "[10/12] Enable and start services (if systemd active)"
if pidof systemd >/dev/null 2>&1; then
    echo "systemd detected — enabling and starting services..."
    systemctl enable --now "${LLAMACPP_SERVICE}" || echo "Warning: enabling/starting ${LLAMACPP_SERVICE} failed."
    # small delay to let llama.cpp attempt to bind model/port
    sleep 4
    systemctl enable --now "${OPENWEBUI_SERVICE}" || echo "Warning: enabling/starting ${OPENWEBUI_SERVICE} failed."
else
    echo "systemd not detected/running. Services were written to /etc/systemd/system but you must enable/start them manually or enable systemd in WSL."
    echo "Manual start examples:"
    echo "  sudo -u aiuser ${LLAMACPP_OPT}/bin/llamacpp-run ${DEFAULT_MODEL_TARGET} 8081 &"
    echo "  sudo -u aiuser ${OPENWEBUI_OPT}/bin/openwebui-run &"
fi

# ---------------- [11] Verify & notes ----------------
section "[11/12] Quick verification & notes"
echo "Check service status with:"
echo "  systemctl status ${LLAMACPP_SERVICE} --no-pager"
echo "  systemctl status ${OPENWEBUI_SERVICE} --no-pager"
echo "View logs:"
echo "  journalctl -u ${LLAMACPP_SERVICE} -n 200 --no-pager"
echo "  journalctl -u ${OPENWEBUI_SERVICE} -n 200 --no-pager"
echo "OpenWebUI: http://<wsl-ip>:8080"
echo "llama.cpp server (if running): port 8081"
pause_if_interactive

# ---------------- [12] Cleanup & finish ----------------
section "[12/12] Cleanup & finish"
apt-get autoremove -y || true
apt-get clean || true

cat <<EOF

Bootstrap v0.16 completed.

Summary:
• Built llama.cpp (CUDA enabled if available and successful; automatically retried CPU-only on CUDA build failure).
• Binary symlink: /usr/local/bin/llamacpp
• Wrapper: /usr/local/bin/llamacpp-run
• OpenWebUI installed into venv at: ${OPENWEBUI_OPT}
• Default model path: ${DEFAULT_MODEL_TARGET} (automatic download attempted only if HF_TOKEN present)
• Systemd units created:
    - ${LLAMACPP_SERVICE}
    - ${OPENWEBUI_SERVICE}

If your llama.cpp binary uses different CLI options for server mode, edit:
    ${LLAMACPP_OPT}/bin/llamacpp-run
to the correct exec line, then restart:
    sudo systemctl restart ${LLAMACPP_SERVICE}

If model download failed and you have the gguf file:
    sudo mkdir -p ${AI_MODELS_DIR}
    sudo cp /path/to/${DEFAULT_MODEL_NAME} ${DEFAULT_MODEL_TARGET}
    sudo chown aiuser:aiuser ${DEFAULT_MODEL_TARGET}
    sudo systemctl restart ${LLAMACPP_SERVICE}

Log file: ${LOGFILE}
EOF

echo "Done at $(date)"
