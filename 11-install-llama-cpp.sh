#!/usr/bin/env bash
#
# 11-install-llama-cpp.sh
# Install and build llama.cpp for CPU or GPU based on detection script.
#

LOG_DIR="/var/log/laptoplab"
LOG_FILE="$LOG_DIR/llama-cpp-install.log"
mkdir -p "$LOG_DIR"
touch "$LOG_FILE"

log() { echo "$(date +"%Y-%m-%d %H:%M:%S") [LLAMA-C++] $1" | tee -a "$LOG_FILE"; }

log "Starting llama.cpp installation..."

# Source GPU detection if not already sourced
if [[ -z "$GPU_TYPE" ]]; then
    if [[ -f "$(dirname "$0")/00-detect-gpu.sh" ]]; then
        log "Sourcing GPU detection script..."
        source "$(dirname "$0")/00-detect-gpu.sh"
    else
        log "WARNING: GPU detection script not found. Defaulting to CPU."
        GPU_TYPE="cpu"
        CUDA_AVAILABLE=false
    fi
fi

log "Detected GPU type: $GPU_TYPE"
log "CUDA available: $CUDA_AVAILABLE"

# Install dependencies
log "Installing required packages..."
sudo apt update
sudo apt install -y build-essential cmake git python3 python3-pip wget curl libomp-dev pkg-config >>"$LOG_FILE" 2>&1

# Directory for LLMs
LLAMA_DIR="$HOME/llama.cpp"
if [[ -d "$LLAMA_DIR" ]]; then
    log "Removing existing llama.cpp directory..."
    rm -rf "$LLAMA_DIR"
fi

log "Cloning llama.cpp repository..."
git clone https://github.com/ggerganov/llama.cpp.git "$LLAMA_DIR" >>"$LOG_FILE" 2>&1

cd "$LLAMA_DIR" || exit 1

# Build options
MAKE_CMD="make"

if [[ "$GPU_TYPE" == "nvidia" && "$CUDA_AVAILABLE" == true ]]; then
    log "Building llama.cpp with CUDA support..."
    MAKE_CMD="make CUDA=1 CUBLAS=1"
elif [[ "$GPU_TYPE" == "intel" ]]; then
    log "Building llama.cpp for CPU (Intel optimized)..."
elif [[ "$GPU_TYPE" == "amd" ]]; then
    log "Building llama.cpp for CPU (AMD optimized, no official ROCm build)..."
else
    log "No GPU detected or CUDA unavailable. Building CPU-only version..."
fi

# Build llama.cpp
log "Running build command: $MAKE_CMD"
$MAKE_CMD >>"$LOG_FILE" 2>&1

if [[ $? -eq 0 ]]; then
    log "llama.cpp built successfully."
else
    log "ERROR: Build failed. Check log file $LOG_FILE."
    exit 1
fi

# Optional: Verify build
log "Verifying build..."
./main -h >>"$LOG_FILE" 2>&1
if [[ $? -eq 0 ]]; then
    log "llama.cpp main executable works."
else
    log "WARNING: main executable failed to run."
fi

log "llama.cpp installation completed."

echo
read -rp "Press ENTER to continue..."
