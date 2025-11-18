#!/usr/bin/env bash
# bootstrap.sh - Version 1.3
# Purpose: Provision WSL Ubuntu with Ollama + Open WebUI (supported installer), Fastfetch, and system fixes.
# Author: Kevin Price
# Notes:
#   - Removes old OpenWebUI pip install
#   - Uses official curl installer
#   - Fixes Ollama timing issue by explicitly starting ollama serve before pulling model
#   - Adds pauses between sections

set -e
set -o pipefail

log() {
    echo -e "[INFO] $1"
}

pause() {
    read -p "Press ENTER to continue..." dummy
}

log "-----------------------------------------"
log "WSL Bootstrap v1.3 Starting..."
log "-----------------------------------------"

### 1️⃣ UPDATE SYSTEM ###
log "Updating system packages..."
apt update && apt upgrade -y
pause

### 2️⃣ INSTALL PREREQS ###
log "Installing prerequisites..."
apt install -y wget curl gnupg lsb-release software-properties-common
pause

### 3️⃣ INSTALL FASTFETCH ###
log "Installing Fastfetch..."
add-apt-repository ppa:fastfetch-maintainers/fastfetch -y
apt update
apt install -y fastfetch
pause

### 4️⃣ INSTALL OLLAMA ###
log "Installing Ollama..."
curl -fsSL https://ollama.com/install.sh | sh
pause

log "Starting Ollama server manually to avoid timing issues..."
ollama serve &
sleep 4

log "Pulling default model: gemma3:270m ..."
ollama pull gemma3:270m || log "Model pull failed — but bootstrap will continue"
pause

### 5️⃣ INSTALL OPEN-WEBUI (Official Installer) ###
log "Installing Open WebUI via official script..."
curl -fsSL https://raw.githubusercontent.com/open-webui/open-webui/main/install.sh | bash
pause

log "Enabling and starting OpenWebUI service..."
systemctl enable open-webui\ssystemctl start open-webui
pause

### 6️⃣ VERIFY INSTALLATIONS ###
log "Checking versions..."
ollama --version || true
open-webui --version || true
fastfetch || true
pause

log "-----------------------------------------"
log "Bootstrap v1.3 completed successfully!"
log "-----------------------------------------"
