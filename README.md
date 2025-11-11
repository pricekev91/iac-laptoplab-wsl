
# WSL Lab Environment Setup

This folder contains scripts to provision and configure a WSL2-based Ubuntu environment for personal lab use on Windows 11. The goal is to automate the setup of a GPU-enabled development environment using Infrastructure-as-Code (IaC) principles.

## 📦 Scripts

### `WSL-provision.ps1`
This PowerShell script:
- Imports a compressed Ubuntu rootfs (`ubuntu-24.04.3-wsl-amd64.gz`) as a WSL2 instance named `Ubuntu-MKI`
- Checks if the instance already exists and prompts for confirmation before deleting and reinstalling
- Sets the new instance as the default WSL distro

### `bootstrap.sh`
This Bash script runs inside the WSL instance and:
- Updates and upgrades the system
- Installs `fastfetch` via PPA for system info display on login
- Adds `fastfetch` to `.bashrc`
- Installs `libtinfo5` manually to resolve CUDA dependencies
- Installs NVIDIA CLI tools and CUDA runtime (via Ubuntu 22.04 repo)
- Verifies GPU access with `nvidia-smi`

## 🚀 Usage

### 1. Clone the Repo
```powershell
git clone https://github.com/pricekev/iac-laptoplab-wsl.git
cd iac-laptoplab-wsl
```

### 2. Run the Provisioning Script
```powershell
.\WSL-provision.ps1
```

### 3. Launch WSL and Run Bootstrap
```bash
bash bootstrap.sh
```

## 🧭 Current Features
- Automated WSL2 instance creation
- GPU support via NVIDIA CLI tools
- Fastfetch system info on login
- Logging to `~/bootstrap.log`

## 🔮 Future Plans
- Install and configure Open LLaMA for local LLM inference
- Integrate OpenWebUI for remote access via browser
- Add snapshot automation using `wsl --export` and `--import`
- Expand to other environments (Docker, Proxmox, etc.) under `laptoplab`

## 📁 Repo Structure
```
iac-laptoplab-wsl/
├── WSL-provision.ps1       # WSL provisioning script
├── bootstrap.sh            # In-WSL setup script
├── README.md               # This file
```

## 🛠️ Requirements
- Windows 11 with WSL2 enabled
- NVIDIA GPU (e.g., 2060M) with drivers installed
- Git and PowerShell

## 📬 Contact
For questions or contributions, reach out via GitHub Issues or Discussions.
