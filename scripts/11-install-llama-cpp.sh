#!/usr/bin/env bash
#
# 11-install-llama-cpp.sh — Version 0.35
# Author: Kevin Price
# Last Updated: 2025-11-21
#
# Purpose:
#   Install llama.cpp to /opt/llama.cpp with CPU/GPU detection and automatic build.
#   Enable CURL support for huggingface downloads.
#   Place models in /srv/ai/models and auto-download Meta-Llama-3-8B GGUF (if available).
#   Install OpenWebUI in a venv under /srv/openwebui and create a start script that points to llama.cpp.
#   Fix PATH and provide symlink so 'llama-cli' is globally available.
#   Logs to /opt/llama-cpp-install.log
#

set -euo pipefail

INSTALL_DIR="/opt/llama.cpp"
LOG_FILE="/opt/llama-cpp-install.log"
PROFILE="$HOME/.bashrc"  # for Linux/WSL users
MODEL_DIR="/srv/ai/models"
OPENWEBUI_DIR="/srv/openwebui"
PYTHON_BIN="$(command -v python3 || true)"

# Logging helpers
sudo touch "$LOG_FILE"
sudo chown "$(whoami):$(whoami)" "$LOG_FILE"
log() { echo "$(date +"%Y-%m-%d %H:%M:%S") [LLAMA-C++] $1" | tee -a "$LOG_FILE"; }

log "Starting llama.cpp + OpenWebUI installation (v0.35)..."

# Source GPU detection (keeps your previous behavior)
GPU_TYPE="cpu"
CUDA_AVAILABLE=false
if [[ -f "$(dirname "$0")/00-detect-gpu.sh" ]]; then
    log "Sourcing GPU detection script..."
    source "$(dirname "$0")/00-detect-gpu.sh"
else
    log "WARNING: GPU detection script missing. Defaulting to CPU."
    GPU_TYPE="cpu"
    CUDA_AVAILABLE=false
fi

log "Detected GPU type: $GPU_TYPE"
log "CUDA available: $CUDA_AVAILABLE"

# Install required packages + dev libraries for curl + optional CUDA build deps
log "Installing required packages..."
sudo apt update
# install libcurl dev so -DLLAMA_CURL=ON can find headers/libs
sudo apt install -y build-essential cmake git python3 python3-venv python3-pip wget curl libomp-dev pkg-config libcurl4-openssl-dev >>"$LOG_FILE" 2>&1

# If you plan to build CUDA, user must already have CUDA toolkit installed; script will try to use nvcc if present.
if [[ "$GPU_TYPE" == "nvidia" && "$CUDA_AVAILABLE" == true ]]; then
    if [[ -x "/usr/local/cuda/bin/nvcc" ]]; then
        log "nvcc found at /usr/local/cuda/bin/nvcc"
    else
        log "WARNING: CUDA reported available but nvcc not found at /usr/local/cuda/bin/nvcc. CUDA build may fail."
    fi
fi

# Remove old install if exists
if [[ -d "$INSTALL_DIR" ]]; then
    log "Removing existing llama.cpp installation at $INSTALL_DIR..."
    sudo rm -rf "$INSTALL_DIR"
fi

# Recreate install directory
log "Creating installation directory $INSTALL_DIR..."
sudo mkdir -p "$INSTALL_DIR"
sudo chown -R "$(whoami):$(whoami)" "$INSTALL_DIR"

# Clone llama.cpp
log "Cloning llama.cpp repository to $INSTALL_DIR..."
git clone https://github.com/ggerganov/llama.cpp.git "$INSTALL_DIR" >>"$LOG_FILE" 2>&1
cd "$INSTALL_DIR" || { log "ERROR: Failed to cd into $INSTALL_DIR"; exit 1; }

# Prepare build
log "Preparing CMake build..."
mkdir -p build
cd build || { log "ERROR: Failed to cd into build directory"; exit 1; }

# Default to enabling CURL so -hf works for huggingface downloads
CMAKE_FLAGS="-DLLAMA_CURL=ON -DCMAKE_BUILD_TYPE=Release"

if [[ "$GPU_TYPE" == "nvidia" && "$CUDA_AVAILABLE" == true ]]; then
    log "Configuring llama.cpp build WITH CUDA and CURL support..."
    # Attempt to set the CUDA compiler if it exists
    if [[ -x "/usr/local/cuda/bin/nvcc" ]]; then
        CMAKE_FLAGS="$CMAKE_FLAGS -DLLAMA_ENABLE_GPU=ON -DCMAKE_CUDA_COMPILER=/usr/local/cuda/bin/nvcc"
    else
        CMAKE_FLAGS="$CMAKE_FLAGS -DLLAMA_ENABLE_GPU=ON"
    fi
else
    log "Configuring llama.cpp build for CPU-only with CURL support..."
    CMAKE_FLAGS="$CMAKE_FLAGS -DLLAMA_ENABLE_GPU=OFF"
fi

log "Running CMake configure: cmake .. $CMAKE_FLAGS"
cmake .. $CMAKE_FLAGS >>"$LOG_FILE" 2>&1 || { log "ERROR: CMake configuration failed. See $LOG_FILE"; exit 1; }

log "Compiling llama.cpp (this will take a while)..."
cmake --build . --config Release -j"$(nproc)" >>"$LOG_FILE" 2>&1 || { log "ERROR: Build failed. See $LOG_FILE"; exit 1; }

log "llama.cpp built successfully."

# Verify key artifacts
if [[ -x "$INSTALL_DIR/build/bin/llama-cli" ]]; then
    log "Found llama-cli at $INSTALL_DIR/build/bin/llama-cli"
else
    # fallback check (older builds had different paths)
    if [[ -x "$INSTALL_DIR/build/main" ]]; then
        log "Found build/main; will create wrapper to expose llama-cli name"
        mkdir -p "$INSTALL_DIR/build/bin"
        ln -sf "$INSTALL_DIR/build/main" "$INSTALL_DIR/build/bin/llama-cli"
    else
        log "WARNING: No llama-cli/main binary found after build."
    fi
fi

# Create model directory
log "Creating model directory at $MODEL_DIR..."
sudo mkdir -p "$MODEL_DIR"
sudo chown -R "$(whoami):$(whoami)" "$MODEL_DIR"

# Fix PATH and alias (point at build/bin)
BIN_PATH_LINE="export PATH=\$PATH:$INSTALL_DIR/build/bin"
ALIAS_LINE="alias llama='llama-cli'"

# ensure we add the correct PATH (bin)
if ! grep -Fxq "$BIN_PATH_LINE" "$PROFILE"; then
    {
        echo ""
        echo "# Added by 11-install-llama-cpp.sh: llama.cpp CLI"
        echo "$BIN_PATH_LINE"
        echo "$ALIAS_LINE"
    } >> "$PROFILE"
    log "Added PATH and alias to $PROFILE"
else
    log "PATH line already in $PROFILE"
fi

# Apply to current shell
export PATH=$PATH:"$INSTALL_DIR/build/bin"
alias llama='llama-cli'

# Create symlink in /usr/local/bin for convenience
if [[ -w /usr/local/bin ]]; then
    log "Creating symlink /usr/local/bin/llama-cli -> $INSTALL_DIR/build/bin/llama-cli"
    sudo ln -sf "$INSTALL_DIR/build/bin/llama-cli" /usr/local/bin/llama-cli
    sudo ln -sf "$INSTALL_DIR/build/bin/llama-cli" /usr/local/bin/llama
else
    log "Cannot write to /usr/local/bin (permission issue). Skipping symlink creation."
fi

# === Hugging Face model auto-download (meta-llama/Meta-Llama-3-8B) ===
# This tries to download the model manifest and GGUF into $MODEL_DIR using llama-cli's -hf option.
# If your HF model requires authentication, export HUGGINGFACE_HUB_TOKEN (or HF_TOKEN) before running the script:
#   export HUGGINGFACE_HUB_TOKEN="hf_..."
#
HF_MODEL="meta-llama/Meta-Llama-3-8B"
log "Attempting to test Hugging Face download support by pulling $HF_MODEL into $MODEL_DIR"

# Respect tokens if set in the environment
if [[ -n "${HUGGINGFACE_HUB_TOKEN:-}" ]]; then
    log "Using HUGGINGFACE_HUB_TOKEN from environment for auth."
    export HUGGINGFACE_HUB_TOKEN="${HUGGINGFACE_HUB_TOKEN}"
elif [[ -n "${HF_TOKEN:-}" ]]; then
    log "Using HF_TOKEN from environment for auth (exporting as HUGGINGFACE_HUB_TOKEN)."
    export HUGGINGFACE_HUB_TOKEN="${HF_TOKEN}"
fi

# Do not fail the whole script if model download doesn't work (auth / model not found / naming differences)
set +e
# llama-cli -hf <repo:revision> -p "Hello world" will attempt download
# we will invoke it in a way that downloads to the model directory (if llama-cli supports --outdir or -o)
# Different versions of llama-cli expose different flags; try the common invocation that triggers the HF download:
"$INSTALL_DIR/build/bin/llama-cli" -hf "$HF_MODEL" -p "Hello world" >>"$LOG_FILE" 2>&1
RC=$?
set -e

if [[ $RC -eq 0 ]]; then
    log "Hugging Face download/test succeeded. Verify models in $MODEL_DIR"
else
    log "WARNING: Hugging Face test command returned non-zero ($RC). This may still be OK if the model requires auth or a different naming/quantization suffix. Check $LOG_FILE for the llama-cli output."
fi

# If the model files exist in the current dir or ~/.cache/huggingface/... try to copy or move them to $MODEL_DIR
# We can't reliably know the exact path (llama-cli and huggingface cache locations vary), so only log guidance
log "If the model was downloaded to a cache location, move or symlink it into $MODEL_DIR. Example:"
log "  mkdir -p $MODEL_DIR && mv /path/to/model.gguf $MODEL_DIR/"

# === OpenWebUI installation (pip into venv) ===
log "Installing OpenWebUI into a python venv at $OPENWEBUI_DIR..."

sudo mkdir -p "$OPENWEBUI_DIR"
sudo chown -R "$(whoami):$(whoami)" "$OPENWEBUI_DIR"

# create venv
if [[ -z "$PYTHON_BIN" ]]; then
    log "ERROR: python3 not found on PATH. Aborting OpenWebUI install."
else
    "$PYTHON_BIN" -m venv "$OPENWEBUI_DIR/venv" >>"$LOG_FILE" 2>&1
    source "$OPENWEBUI_DIR/venv/bin/activate"
    pip install --upgrade pip >>"$LOG_FILE" 2>&1
    # install OpenWebUI; any version conflicts should be resolved manually
    pip install open-webui >>"$LOG_FILE" 2>&1 || {
        log "WARNING: pip install open-webui failed. Check $LOG_FILE and consider installing a specific version (pip install open-webui==<version>)"
    }
    deactivate
fi

# Create a small start script for OpenWebUI
START_SCRIPT="$OPENWEBUI_DIR/start-openwebui.sh"
cat > "$START_SCRIPT" <<'EOF'
#!/usr/bin/env bash
# start-openwebui.sh — start script for OpenWebUI (adjust flags for your OpenWebUI version if needed)
OPENWEBUI_DIR="/srv/openwebui"
MODEL_DIR="/srv/ai/models"
LLAMA_CLI_BIN="/opt/llama.cpp/build/bin/llama-cli"

# activate venv
source "$OPENWEBUI_DIR/venv/bin/activate"

# If your OpenWebUI accepts a --models-dir flag, use it; otherwise you may need to configure models inside the UI.
# This command attempts to run OpenWebUI and instruct it to use local models and the llama.cpp binary.
# If your installed OpenWebUI version expects different flags, edit this line to match.
open-webui serve --host 0.0.0.0 --port 8080 --models-dir "$MODEL_DIR" --llama-cpp-binary "$LLAMA_CLI_BIN"
# Notes:
#  - If 'open-webui serve' does not accept --llama-cpp-binary or --models-dir, edit this script and remove/add options as required by your OpenWebUI version.
#  - You can run the command manually to diagnose issues.
EOF

chmod +x "$START_SCRIPT"
log "Created OpenWebUI start script at $START_SCRIPT"

# Optionally create a basic systemd service (works if your WSL distribution uses systemd)
if command -v systemctl >/dev/null 2>&1 && systemctl --version >/dev/null 2>&1; then
    log "Systemd detected — creating user service for OpenWebUI"
    mkdir -p "$HOME/.config/systemd/user"
    cat > "$HOME/.config/systemd/user/openwebui.service" <<EOF
[Unit]
Description=OpenWebUI (user service)
After=network.target

[Service]
Type=simple
ExecStart=$START_SCRIPT
Restart=on-failure
Environment=PATH=$OPENWEBUI_DIR/venv/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin
WorkingDirectory=$OPENWEBUI_DIR

[Install]
WantedBy=default.target
EOF
    log "Enabling and starting openwebui.service (user)"
    systemctl --user daemon-reload || true
    systemctl --user enable --now openwebui.service || log "Failed to enable/start openwebui.service via systemctl --user. You can start via $START_SCRIPT"
else
    log "Systemd not detected (or not available). Start OpenWebUI manually with: $START_SCRIPT"
fi

# Final notices
log "Installation finished. Summary and recommendations:"
log " - llama-cli location: $INSTALL_DIR/build/bin/llama-cli"
log " - Symlink (if created): /usr/local/bin/llama-cli"
log " - Model directory: $MODEL_DIR"
log " - OpenWebUI venv: $OPENWEBUI_DIR/venv"
log " - OpenWebUI start script: $START_SCRIPT"
log ""
log "If a Hugging Face model requires authentication, export HUGGINGFACE_HUB_TOKEN or HF_TOKEN before invoking llama-cli to download."
log "Example:"
log "  export HUGGINGFACE_HUB_TOKEN='hf_...'"
log "  llama-cli -hf meta-llama/Meta-Llama-3-8B -p 'Hello world'"

log "If OpenWebUI's CLI flags differ on your installed version, edit $START_SCRIPT and replace the serve CLI options with the correct ones."
log "Done."
