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
#   v0.31 — Auto-create logs folder, CPU/GPU fallback, hands-off install, CURL disabled, clean /opt install
#

# -----------------------------
# Logging
# -----------------------------
LOG_DIR="/opt/llama.cpp/logs"
LOG_FILE="$LOG_DIR/llama-cpp-install.log"
sudo mkdir -p "$LOG_DIR"
sudo chown "$USER:$USER" "$LOG_DIR"
touch "$LOG_FILE"

log() {
    echo "$(date +"%Y-%m-%d %H:%M:%S") [LLAMA-C++] $1" | tee -a "$LOG_FILE"
}

log "Starting llama.cpp installation..."

# -----------------------------
# Source GPU detection
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
# Remove existing installation
# -----------------------------
if [[ -d "/opt/llama.cpp" ]]; then
    log "Removing existing llama.cpp installation..."
    sudo rm -rf /opt/llama.cpp
fi

# -----------------------------
# Clone repository
# -----------------------------
log "Cloning llama.cpp repository to /opt/llama.cpp..."
sudo git clone https://github.com/ggerganov/llama.cpp.git /opt/llama.cpp >>"$LOG_FILE" 2>&1
sudo chown -R "$USER:$
32
