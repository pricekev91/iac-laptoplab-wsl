#!/usr/bin/env bash

LOG_DIR="/var/log/laptoplab"
LOG_FILE="$LOG_DIR/gpu-detect.log"
mkdir -p "$LOG_DIR"
touch "$LOG_FILE"

log() { echo "$(date +"%Y-%m-%d %H:%M:%S") [GPU-DETECT] $1" | tee -a "$LOG_FILE"; }

log "Starting GPU detection..."

# Detect WSL
if grep -qi "microsoft" /proc/version; then
    log "Running inside WSL environment (detected)."
fi

# WSL GPU device
if [[ -e /dev/dxg ]]; then
    log "WSL GPU compute device detected: /dev/dxg"
else
    log "ERROR: /dev/dxg not found — GPU compute not available in WSL."
fi

##############################################
# NVIDIA GPU Detection (WSL-safe)
##############################################

if command -v nvidia-smi >/dev/null 2>&1; then
    log "nvidia-smi found."

    if nvidia-smi >>"$LOG_FILE" 2>&1; then
        log "NVIDIA GPU detected via nvidia-smi."
        GPU_NVIDIA=true
    else
        log "ERROR: nvidia-smi exists but cannot communicate with driver."
        GPU_NVIDIA=false
    fi
else
    log "NVIDIA utilities NOT found."
    GPU_NVIDIA=false
fi

##############################################
# Intel GPU Detection
##############################################

if command -v sycl-ls >/dev/null 2>&1; then
    if sycl-ls | grep -qi intel; then
        log "Intel GPU detected via oneAPI Level Zero."
        GPU_INTEL=true
    else
        GPU_INTEL=false
    fi
else
    GPU_INTEL=false
fi

##############################################
# AMD GPU Detection (WSL ROCm)
##############################################

if command -v rocminfo >/dev/null 2>&1; then
    if rocminfo | grep -qi amdgpu; then
        log "AMD GPU detected via ROCm."
        GPU_AMD=true
    else
        GPU_AMD=false
    fi
else
    GPU_AMD=false
fi

##############################################
# Summary
##############################################

log "Summary:"
log "  NVIDIA GPU: $GPU_NVIDIA"
log "  Intel GPU:  $GPU_INTEL"
log "  AMD GPU:    $GPU_AMD"

if [[ "$GPU_NVIDIA" = true ]]; then
    EXIT_CODE=0
elif [[ "$GPU_INTEL" = true ]]; then
    EXIT_CODE=0
elif [[ "$GPU_AMD" = true ]]; then
    EXIT_CODE=0
else
    log "WARNING: No GPU detected. CPU-only mode will be used."
    EXIT_CODE=0
fi

echo
read -rp "Press ENTER to continue..."
exit $EXIT_CODE

