#!/usr/bin/env bash
#
# 00-detect-gpu.sh — Version 0.1
# Author: Kevin Price
# Last Updated: 2025-11-20
#
# Purpose:
#   Automatically detect GPU type and CUDA availability.
#   Sets:
#     GPU_TYPE       = "nvidia", "intel", "amd", or "cpu"
#     CUDA_AVAILABLE = true/false
#

GPU_TYPE="cpu"
CUDA_AVAILABLE=false

# Detect NVIDIA GPU
if command -v nvidia-smi >/dev/null 2>&1; then
    NVIDIA_COUNT=$(nvidia-smi -L 2>/dev/null | wc -l)
    if [[ $NVIDIA_COUNT -gt 0 ]]; then
        GPU_TYPE="nvidia"
        # Check if CUDA is installed
        if command -v nvcc >/dev/null 2>&1; then
            CUDA_AVAILABLE=true
        else
            CUDA_AVAILABLE=false
        fi
    fi
fi

# Detect Intel GPU (primarily integrated graphics)
if [[ "$GPU_TYPE" == "cpu" ]] && command -v lspci >/dev/null 2>&1; then
    if lspci | grep -i 'intel.*graphics' >/dev/null 2>&1; then
        GPU_TYPE="intel"
    fi
fi

# Detect AMD GPU
if [[ "$GPU_TYPE" == "cpu" ]] && command -v lspci >/dev/null 2>&1; then
    if lspci | grep -i 'amd.*vga\|radeon\|vega' >/dev/null 2>&1; then
        GPU_TYPE="amd"
    fi
fi

# Environment check for WSL
if grep -qi microsoft /proc/version 2>/dev/null; then
    WSL_DETECTED=true
else
    WSL_DETECTED=false
fi

# Summary
echo "-------------------------------------"
echo "[GPU-DETECT] GPU detection complete:"
echo "[GPU-DETECT]   GPU_TYPE:       $GPU_TYPE"
echo "[GPU-DETECT]   CUDA_AVAILABLE: $CUDA_AVAILABLE"
echo "[GPU-DETECT]   WSL_DETECTED:   $WSL_DETECTED"
echo "-------------------------------------"

# Export variables so sourcing script can use them
export GPU_TYPE
export CUDA_AVAILABLE
export WSL_DETECTED
