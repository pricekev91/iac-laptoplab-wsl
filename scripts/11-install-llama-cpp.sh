#!/usr/bin/env bash
#
# 11-install-llama-cpp.sh — Version 0.3
# Author: Kevin Price
# Last Updated: 2025-11-20
#
# Purpose:
#   Fully automated llama.cpp installation with GPU/CPU detection.
#   Builds in /opt/llama.cpp, auto-fixes common build errors, logs everything.
#

INSTALL_DIR="/opt/llama.cpp"
LOG_DIR="$INSTALL_DIR/logs"
LOG_FILE="$LOG_DIR/llama-cpp-install.log"
mkdir -p "$LOG_DIR"
touch "$LOG_FILE"

log() { echo "$(date +"%Y-%m-%d %H:%M:%S") [LLAMA-C++] $1" | tee -a "$LOG_FILE"; }

log "Starting llama.cpp installation..."

# Source GPU detection
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
sudo apt update >>"$LOG_FILE" 2>&1
sudo apt install -y build-essential cmake git python3 python3-pip wget curl libomp-dev pkg-config libcurl4-openssl-dev >>"$LOG_FILE" 2>&1

# Remove existing install if present
if [[ -d "$INSTALL_DIR" ]]; then
    log "Removing existing llama.cpp installation..."
    sudo rm -rf "$INSTALL_DIR"
fi

# Clone repository
log "Cloning llama.cpp repository to $INSTALL_DIR..."
sudo git clone https://github.com/ggerganov/llama.cpp.git "$INSTALL_DIR" >>"$LOG_FILE" 2>&1

# Prepare build
cd "$INSTALL_DIR" || exit 1
mkdir -p build
cd build || exit 1

# Configure CMake
CMAKE_FLAGS="-DLLAMA_ENABLE_GPU=OFF -DCMAKE_BUILD_TYPE=Release"
if [[ "$GPU_TYPE" == "nvidia" && "$CUDA_AVAILABLE" == true ]]; then
    log "Enabling CUDA build..."
    CMAKE_FLAGS="-DLLAMA_ENABLE_GPU=ON -DCMAKE_CUDA_COMPILER=/usr/local/cuda/bin/nvcc -DCMAKE_BUILD_TYPE=Release"
elif [[ "$GPU_TYPE" == "intel" ]]; then
    log "CPU Intel-optimized build..."
elif [[ "$GPU_TYPE" == "amd" ]]; then
    log "CPU AMD-optimized build..."
else
    log "No GPU detected or CUDA unavailable. CPU-only build..."
fi

log "Running CMake configure: cmake .. $CMAKE_FLAGS"
sudo cmake .. $CMAKE_FLAGS >>"$LOG_FILE" 2>&1

# Compile
log "Compiling llama.cpp..."
sudo cmake --build . --config Release >>"$LOG_FILE" 2>&1

if [[ $? -eq 0 ]]; then
    log "llama.cpp built successfully."
else
    log "ERROR: Build failed. Attempting auto-fix..."

    log "Retrying CMake clean..."
    sudo rm -rf *
    sudo cmake .. $CMAKE_FLAGS >>"$LOG_FILE" 2>&1
    sudo cmake --build . --config Release >>"$LOG_FILE" 2>&1

    if [[ $? -eq 0 ]]; then
        log "llama.cpp rebuilt successfully after auto-fix."
    else
        log "ERROR: Build failed after auto-fix. Check $LOG_FILE"
        exit 1
    fi
fi

# Verify executable
log "Verifying main executable..."
if ./main -h >>"$LOG_FILE" 2>&1; then
    log "Executable works."
else
    log "WARNING: main executable failed. Attempting permission fix..."
    sudo chmod +x ./main
    if ./main -h >>"$LOG_FILE" 2>&1; then
        log "Executable works after chmod fix."
    else
        log "ERROR: main still fails to run. Check $LOG_FILE"
    fi
fi

log "llama.cpp installation completed."
