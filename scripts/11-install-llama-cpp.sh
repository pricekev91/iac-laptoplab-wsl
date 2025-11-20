#!/usr/bin/env bash
#
# 11-install-llama-cpp.sh — Version 0.31
# Author: Kevin Price
# Last Updated: 2025-11-20
#
# Purpose:
#   Install and build llama.cpp to /opt/llama.cpp for CPU or GPU (CUDA) if available.
#   Automatically handles dependencies, logs, and GPU detection.
#
# Changelog:
#   v0.31 — Fixed logs folder creation & unclosed quotes, CPU/GPU fallback, hands-off install
#

# -----------------------------
# Directories & logging
# -----------------------------
INSTALL_DIR="/opt/llama.cpp"
LOG_DIR="$INSTALL_DIR/logs"
LOG_FILE="$LOG_DIR/llama-cpp-install.log"

# Ensure directories exist
sudo mkdir -p "$LOG_DIR"
sudo chown "$USER:$USER" "$INSTALL_DIR" "$LOG_DIR"
touch "$LOG_FILE"

log() {
    echo "$(date +"%Y-%m-%d %H:%M:%S") [LLAMA-C++] $1" | tee -a "$LOG_FILE"
}

log "Starting llama.cpp installation..."

# -----------------------------
# GPU detection
# -----------------------------
if [[ -f "$(dirname "$0")/00-detect-gpu.sh" ]]; then
    log "Sourcing GPU detection script..."
    source "$(dirname "$0")/00-detect-gpu.sh"
else
    log "WARNING: GPU detection script not found. Defaulting to CPU."
    GPU_TYPE="cpu"
    CUDA_AVAILABLE=false
fi

log "Detected GPU type: $GPU_TYPE"
log "CUDA available: $CUDA_AVAILABLE"

# -----------------------------
# Install dependencies
# -----------------------------
log "Installing required packages..."
sudo apt update
sudo apt install -y build-essential cmake git python3 python3-pip wget curl libomp-dev pkg-config >>"$LOG_FILE" 2>&1

# -----------------------------
# Remove old installation
# -----------------------------
if [[ -d "$INSTALL_DIR" ]]; then
    log "Removing existing llama.cpp installation..."
    sudo rm -rf "$INSTALL_DIR"
fi

# -----------------------------
# Clone repository
# -----------------------------
log "Cloning llama.cpp repository to $INSTALL_DIR..."
sudo git clone https://github.com/ggerganov/llama.cpp.git "$INSTALL_DIR" >>"$LOG_FILE" 2>&1
sudo chown -R "$USER:$USER" "$INSTALL_DIR"
cd "$INSTALL_DIR" || { log "ERROR: $INSTALL_DIR missing"; exit 1; }

# -----------------------------
# Prepare CMake build
# -----------------------------
log "Preparing CMake build..."
mkdir -p build
cd build || { log "ERROR: Cannot enter build directory"; exit 1; }

CMAKE_FLAGS="-DLLAMA_ENABLE_GPU=OFF -DLLAMA_CURL=OFF"
if [[ "$GPU_TYPE" == "nvidia" && "$CUDA_AVAILABLE" == true ]]; then
    log "Building llama.cpp with CUDA support..."
    CMAKE_FLAGS="-DLLAMA_ENABLE_GPU=ON -DCMAKE_CUDA_COMPILER=/usr/local/cuda/bin/nvcc -DLLAMA_CURL=OFF"
else
    log "No GPU detected or CUDA unavailable. Building CPU-only version..."
fi

log "Running CMake configure: cmake .. $CMAKE_FLAGS"
cmake .. $CMAKE_FLAGS >>"$LOG_FILE" 2>&1

# -----------------------------
# Compile
# -----------------------------
log "Compiling llama.cpp..."
cmake --build . --config Release >>"$LOG_FILE" 2>&1
if [[ $? -eq 0 ]]; then
    log "llama.cpp built successfully."
else
    log "ERROR: Build failed. Check log $LOG_FILE"
    exit 1
fi

# -----------------------------
# Verify build
# -----------------------------
log "Verifying build..."
if ./main -h >>"$LOG_FILE" 2>&1; then
    log "llama.cpp main executable works."
else
    log "WARNING: main executable failed to run. Attempting automatic fix..."
    chmod +x ./main
    if ./main -h >>"$LOG_FILE" 2>&1; then
        log "main executable now works after chmod."
    else
        log "ERROR: main executable still fails. Check $LOG_FILE manually."
    fi
fi

log "llama.cpp installation completed."
