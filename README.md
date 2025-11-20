Below is a **fully updated README.md** that keeps everything from your original version, **adds the new IaC structure**, **explains the LLM engine support**, and **maintains professional formatting**.

You can paste this **directly into your repo**.

---

# **README.md**

# WSL Lab & Linux LLM Environment Setup

This repository contains Infrastructure-as-Code (IaC) scripts used to provision two environments:

1. **WSL2-based Ubuntu environment on Windows 11**
2. **Native Linux environment for LLM engines (Ollama / llama.cpp) + OpenWebUI**

The goal is to automate GPU-capable setups for development, testing, and homelab workloads using a modular, versioned, Git-driven workflow.

---

# 📦 Components

## **1. Windows / WSL2 Provisioning**

### `WSL-provision.ps1`

This PowerShell script:

* Imports a compressed Ubuntu rootfs (`ubuntu-24.04.3-wsl-amd64.gz`) as a WSL2 instance named `Ubuntu-MKI`
* Detects if the instance exists, and prompts before replacing it
* Sets the new distro as the default WSL instance
* Follows IaC principles for OS lifecycle management

### `bootstrap.sh`

Run inside the WSL instance. It:

* Updates and upgrades the system
* Installs **fastfetch** for system summary display at login
* Adds fastfetch to `.bashrc`
* Installs `libtinfo5` manually (fix for CUDA apps)
* Installs NVIDIA CLI tools + CUDA runtime
* Verifies GPU support with `nvidia-smi`
* Logs all actions to `~/bootstrap.log`

---

# **2. Linux LLM Provisioning**

Under `iac-laptoplab/` you will find modular scripts that install:

* **Ollama** (CPU, NVIDIA CUDA, or AMD ROCm)
* **llama.cpp** with correct GPU flags
* **OpenWebUI** via Docker
* Post-setup Ubuntu tooling (htop, neofetch, git, etc.)

This part of the repo uses a **Git feature-branch model**:

| Branch                     | Purpose                                        |
| -------------------------- | ---------------------------------------------- |
| `feature/llm_engine`       | GPU detection, Ollama install, llama.cpp build |
| `feature/openwebui`        | OpenWebUI install + model configuration        |
| `feature/ubuntu_provision` | Post-setup tooling + quality-of-life configs   |
| `main`                     | Orchestrator + stable releases                 |

---

# 📁 Repo Structure

```
iac-laptoplab/
│
├── main.sh                          # Orchestrator (runs all scripts)
│
└── scripts/
    ├── 00-detect-gpu.sh            # feature/llm_engine
    ├── 10-install-ollama.sh        # feature/llm_engine
    ├── 11-install-llama-cpp.sh     # feature/llm_engine
    ├── 20-install-openwebui.sh     # feature/openwebui
    ├── 30-config-openwebui.sh      # feature/openwebui
    └── 40-post-setup.sh            # feature/ubuntu_provision
```

The Linux provisioning is intentionally modular to make it easier to test, version, and expand.

---

# 🚀 Usage

## **1. Clone the Repo**

```powershell
git clone https://github.com/pricekev/iac-laptoplab-wsl.git
cd iac-laptoplab-wsl
```

---

## **2. Provision the WSL Instance**

```powershell
.\WSL-provision.ps1
```

---

## **3. Enter WSL and Bootstrap**

```bash
bash bootstrap.sh
```

---

## **4. (Linux) Run the LLM Orchestrator**

If running on Ubuntu outside of WSL:

```bash
cd iac-laptoplab
bash main.sh
```

This:

* Detects NVIDIA / AMD / CPU
* Installs Ollama
* Builds llama.cpp with correct GPU backend
* Installs OpenWebUI via Docker
* Sets a default model
* Applies post-setup system config

---

# 🧭 Current Features

### WSL Environment

* Automated WSL2 instance deployment
* GPU enablement via NVIDIA tools
* Automatic system info via fastfetch
* Logged bootstrap process

### Linux LLM Environment

* GPU autodetection (NVIDIA / AMD / CPU fallback)
* Easy Ollama install
* GPU-optimized llama.cpp build
* OpenWebUI with Docker
* Default model auto-loaded
* Modular IaC folder structure

---

# 🔮 Future Roadmap

* Add snapshot automation for WSL (`wsl --export` / `--import`)
* Add versioning (v0.1 → v0.2 → v0.3…) following semantic releases
* Add Proxmox automation scripts for homelab
* Add cloud-init templates for VM builds
* Add GitHub Actions for linting + test execution
* Add verification script for GPU performance

---

# 🛠️ Requirements

* Windows 11 with WSL2 enabled (for WSL portion)
* Ubuntu Linux (for LLM engine portion)
* NVIDIA GPU or AMD GPU recommended
* Git
* PowerShell 7+

---

# 📬 Contact

For questions, issues, or enhancements:
Open a GitHub Issue or start a Discussion.

---

If you want, I can also generate:

✔ `CHANGELOG.md`
✔ Version tags (v0.1 → v0.2)
✔ GitHub Actions CI pipeline
✔ Branch-creation commands

Just say **“Generate CHANGELOG”**, **“Add CI actions”**, or **“Create release tags”**.
