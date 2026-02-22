---
name: rocm-torch-installer
description: Helps install the correct PyTorch (torch, torchvision, torchaudio) wheel for a specific ROCm version and Python version, with special support for AMD Strix Halo (gfx1151 / Ryzen AI Max series). Use when the user asks about installing PyTorch with ROCm, picking the right torch wheel, or setting up PyTorch on Strix Halo.
---

# ROCm PyTorch Installer for Strix Halo (gfx1151)

This skill detects the user's environment and generates the correct `pip install` commands for PyTorch on AMD ROCm, with special handling for Strix Halo (gfx1151 / Ryzen AI Max 395).

---

## Step 1: Detect the Environment

Run these commands to detect the system configuration:

```bash
# Detect ROCm version
rocminfo 2>/dev/null | grep "ROCm" | head -3 || cat /opt/rocm/.info/version 2>/dev/null || rocm-smi --version 2>/dev/null | head -2

# Detect Python version
python3 --version 2>/dev/null || python --version 2>/dev/null

# Detect GPU architecture (critical for Strix Halo)
rocminfo 2>/dev/null | grep "gfx" | grep -v "^#" | head -5

# Detect OS / platform
uname -s -m
```

Parse the output to determine:
- **ROCm version** (e.g. `6.4.1`, `7.1`, `7.2`)
- **Python version** → map to CPython tag (see table below)
- **GPU architecture** → check if `gfx1151` is listed (= Strix Halo)
- **Platform** → Linux x86_64 or Windows (different wheel sources)

### Python Version → CPython Tag Mapping

| Python | CPython Tag |
|--------|-------------|
| 3.9    | cp39        |
| 3.10   | cp310       |
| 3.11   | cp311       |
| 3.12   | cp312       |
| 3.13   | cp313       |

---

## Step 2: Determine the Install Strategy

### ⚠️ Critical: gfx1151 (Strix Halo) Compatibility

**gfx1151 IS Strix Halo** (Ryzen AI Max 395 / Radeon 8060S). Official AMD wheels compiled for older ROCm (≤6.4.x) do **not** include gfx1151 kernels and will fail with `invalid device function`.

| ROCm Version | torch Version | gfx1151 Support | Install Source |
|---|---|---|---|
| 6.0 | 2.3.0 | ❌ No native kernels | Community wheels only |
| 6.1 | 2.4.1 | ❌ No native kernels | Community wheels only |
| 6.2 / 6.2.3 | 2.5.1 | ❌ No native kernels | Community wheels only |
| 6.3 / 6.3.x | 2.6.0 | ❌ No native kernels | Community wheels only |
| 6.4 / 6.4.1 | 2.6.0 or 2.7.1 | ⚠️ Partial via HSA override | Community wheels recommended |
| 6.5 (rc) | 2.7.x | ✅ Native gfx1151 kernels | Community wheels (scottt) |
| 7.0 / 7.0.2 | 2.7.1 | ✅ via gfx11-generic | Official AMD wheels |
| 7.1 / 7.1.1 | 2.8.0 or 2.9.1 | ✅ Native | Official AMD wheels |
| 7.2 | 2.9.1 | ✅ Native | Official AMD wheels |

### Decision Logic

1. **ROCm ≥ 7.0 on Linux** → Use **official AMD repo** wheels
2. **ROCm ≤ 6.4.x on Linux** → Use **community wheels** from scottt/rocm-TheRock
3. **Windows** → Use **community wheels** from scottt/rocm-TheRock (Windows-specific builds)
4. **gfx1151 detected + ROCm ≤ 6.4** → Always use community wheels, and set HSA override

---

## Step 3A: Official AMD Repo Wheels (ROCm 7.0+)

> **IMPORTANT**: The AMD repo (`repo.radeon.com/rocm/manylinux/`) is a **plain file directory**, NOT a PEP 503 package index.
> `pip install --index-url` and `--extra-index-url` will NOT work. You must install via **direct wheel URLs**.

### How to Find the Exact Filename

Each wheel filename embeds a git hash that changes per build. Use this command to look up what's available:

```bash
# List all torch-related wheels for a given ROCm release:
curl -s https://repo.radeon.com/rocm/manylinux/rocm-rel-{ROCM_REL}/ \
  | grep -oP 'href="[^"]*\.whl"' | sed 's/href="//;s/"//' \
  | grep -E "^torch|^torchaudio|^torchvision"
```

### Verified Wheel Filenames — ROCm 7.1

Base URL: `https://repo.radeon.com/rocm/manylinux/rocm-rel-7.1/`

> The `+` in version strings is URL-encoded as `%2B` in the path.

#### torch 2.9.1 (latest for ROCm 7.1 — cp310 only, no cp39)

| Python | Filename |
|--------|----------|
| cp310  | `torch-2.9.1%2Brocm7.1.0.lw.git351ff442-cp310-cp310-linux_x86_64.whl` |
| cp311  | `torch-2.9.1%2Brocm7.1.0.lw.git351ff442-cp311-cp311-linux_x86_64.whl` |
| cp312  | `torch-2.9.1%2Brocm7.1.0.lw.git351ff442-cp312-cp312-linux_x86_64.whl` |
| cp313  | `torch-2.9.1%2Brocm7.1.0.lw.git351ff442-cp313-cp313-linux_x86_64.whl` |

#### torch 2.7.1 (stable, includes cp39)

| Python | Filename |
|--------|----------|
| cp39   | `torch-2.7.1%2Brocm7.1.0.lw.git4b0d5f80-cp39-cp39-linux_x86_64.whl` |
| cp310  | `torch-2.7.1%2Brocm7.1.0.lw.git4b0d5f80-cp310-cp310-linux_x86_64.whl` |
| cp311  | `torch-2.7.1%2Brocm7.1.0.lw.git4b0d5f80-cp311-cp311-linux_x86_64.whl` |
| cp312  | `torch-2.7.1%2Brocm7.1.0.lw.git4b0d5f80-cp312-cp312-linux_x86_64.whl` |
| cp313  | `torch-2.7.1%2Brocm7.1.0.lw.git4b0d5f80-cp313-cp313-linux_x86_64.whl` |

#### torchaudio 2.9.0 (matches torch 2.9.1)

| Python | Filename |
|--------|----------|
| cp310  | `torchaudio-2.9.0%2Brocm7.1.0.gite3c6ee2b-cp310-cp310-linux_x86_64.whl` |
| cp311  | `torchaudio-2.9.0%2Brocm7.1.0.gite3c6ee2b-cp311-cp311-linux_x86_64.whl` |
| cp312  | `torchaudio-2.9.0%2Brocm7.1.0.gite3c6ee2b-cp312-cp312-linux_x86_64.whl` |
| cp313  | `torchaudio-2.9.0%2Brocm7.1.0.gite3c6ee2b-cp313-cp313-linux_x86_64.whl` |

#### torchvision 0.24.0 (matches torch 2.9.1)

| Python | Filename |
|--------|----------|
| cp310  | `torchvision-0.24.0%2Brocm7.1.0.gitb919bd0c-cp310-cp310-linux_x86_64.whl` |
| cp311  | `torchvision-0.24.0%2Brocm7.1.0.gitb919bd0c-cp311-cp311-linux_x86_64.whl` |
| cp312  | `torchvision-0.24.0%2Brocm7.1.0.gitb919bd0c-cp312-cp312-linux_x86_64.whl` |
| cp313  | `torchvision-0.24.0%2Brocm7.1.0.gitb919bd0c-cp313-cp313-linux_x86_64.whl` |

### Install Commands (Direct URL — ROCm 7.1)

Substitute `{PY}` with your CPython tag (cp310, cp311, cp312, cp313):

```bash
BASE=https://repo.radeon.com/rocm/manylinux/rocm-rel-7.1
PY=cp310  # change to match your Python version

pip install \
  "${BASE}/torch-2.9.1%2Brocm7.1.0.lw.git351ff442-${PY}-${PY}-linux_x86_64.whl" \
  "${BASE}/torchvision-0.24.0%2Brocm7.1.0.gitb919bd0c-${PY}-${PY}-linux_x86_64.whl" \
  "${BASE}/torchaudio-2.9.0%2Brocm7.1.0.gite3c6ee2b-${PY}-${PY}-linux_x86_64.whl"
```

**Full example for Python 3.10 (cp310):**
```bash
pip install \
  "https://repo.radeon.com/rocm/manylinux/rocm-rel-7.1/torch-2.9.1%2Brocm7.1.0.lw.git351ff442-cp310-cp310-linux_x86_64.whl" \
  "https://repo.radeon.com/rocm/manylinux/rocm-rel-7.1/torchvision-0.24.0%2Brocm7.1.0.gitb919bd0c-cp310-cp310-linux_x86_64.whl" \
  "https://repo.radeon.com/rocm/manylinux/rocm-rel-7.1/torchaudio-2.9.0%2Brocm7.1.0.gite3c6ee2b-cp310-cp310-linux_x86_64.whl"
```

### Available Version Summary per ROCm Release

| ROCm | torch | torchvision | torchaudio | Python Tags |
|------|-------|-------------|------------|-------------|
| 7.2  | 2.6.0, 2.7.1, 2.8.0, 2.9.1 | 0.21.0–0.24.0 | 2.6.0–2.9.0 | cp39–cp313 |
| 7.1  | 2.6.0, 2.7.1, 2.8.0, 2.9.1 | 0.21.0–0.24.0 | 2.6.0–2.9.0 | cp39–cp313 (cp39 missing for 2.9.1) |
| 7.0  | 2.6.0, 2.7.1 | 0.21.0, 0.22.1 | 2.6.0, 2.7.1 | cp39–cp312 |
| 6.4.1| 2.3.0–2.7.1 | 0.18.0–0.22.1 | 2.3.0–2.7.1 | cp39–cp313 |
| 6.3  | 2.3.0–2.6.0 | 0.18.0–0.21.0 | 2.3.0–2.6.0 | cp39–cp312 |
| 6.2  | 2.3.0–2.5.1 | 0.18.0–0.20.1 | 2.3.0–2.5.0 | cp39–cp312 |

---

## Step 3B: Community Wheels for gfx1151 (ROCm ≤ 6.4 or Windows)

### Source: `scottt/rocm-TheRock` on GitHub

Maintained by @scottt and @jammm. These are self-contained wheels compiled natively for gfx1151.

**Releases page:** `https://github.com/scottt/rocm-TheRock/releases`

#### Known Available Wheels

**Release `v6.5.0rc-pytorch` (Linux, Python 3.11)**
```
torch-2.7.0a0+gitbfd8155-cp311-cp311-linux_x86_64.whl
```
Direct URL:
```
https://github.com/scottt/rocm-TheRock/releases/download/v6.5.0rc-pytorch/torch-2.7.0a0+gitbfd8155-cp311-cp311-linux_x86_64.whl
```

**Release `v6.5.0rc-pytorch` (Windows, Python 3.12)**
```
torch-2.7.0a0+git3f903c3-cp312-cp312-win_amd64.whl
torchvision-0.22.0+9eb57cd-cp312-cp312-win_amd64.whl
torchaudio-2.6.0a0+1a8f621-cp312-cp312-win_amd64.whl
```

**Release `v6.5.0rc-pytorch-gfx110x` (Windows + Linux, Python 3.12)**
Supports: gfx1100, gfx1101, gfx1102, gfx1103, **gfx1151**, gfx1201

> Always check the latest release at: `https://github.com/scottt/rocm-TheRock/releases`

### Install Command (Community Wheels)

```bash
# Linux, Python 3.11 — gfx1151 native
pip install https://github.com/scottt/rocm-TheRock/releases/download/v6.5.0rc-pytorch/torch-2.7.0a0+gitbfd8155-cp311-cp311-linux_x86_64.whl

# Windows, Python 3.12 — gfx1151 native
pip install https://github.com/scottt/rocm-TheRock/releases/download/v6.5.0rc-pytorch/torch-2.7.0a0+git3f903c3-cp312-cp312-win_amd64.whl
pip install https://github.com/scottt/rocm-TheRock/releases/download/v6.5.0rc-pytorch/torchvision-0.22.0+9eb57cd-cp312-cp312-win_amd64.whl
pip install https://github.com/scottt/rocm-TheRock/releases/download/v6.5.0rc-pytorch/torchaudio-2.6.0a0+1a8f621-cp312-cp312-win_amd64.whl
```

---

## Step 4: Set Required Environment Variables

After installation, gfx1151 users may need environment variables. Add to `~/.bashrc` / `~/.zshrc` (Linux) or system environment (Windows):

```bash
# Use HIP device visibility (not CUDA) — unset CUDA_VISIBLE_DEVICES if it was set
unset CUDA_VISIBLE_DEVICES
export HIP_VISIBLE_DEVICES=0

# For ROCm ≤ 6.4: override GFX version to gfx1100-compatible mode
# (Only needed if using official wheels that lack gfx1151 kernels)
export HSA_OVERRIDE_GFX_VERSION=11.0.0

# Recommended performance flags for Strix Halo (unified memory)
export PYTORCH_HIP_ALLOC_CONF=expandable_segments:True
export PYTORCH_NO_CUDA_MEMORY_CACHING=1
```

> Note: `HSA_OVERRIDE_GFX_VERSION=11.0.0` is a workaround for wheels that don't include gfx1151 kernels.
> It maps gfx1151 to gfx1100 kernels. Performance may be suboptimal. Prefer native gfx1151 wheels when possible.

---

## Step 5: Verify Installation

```python
import torch
print(f"torch version: {torch.__version__}")
print(f"ROCm available: {torch.cuda.is_available()}")
print(f"Device count: {torch.cuda.device_count()}")
print(f"Device name: {torch.cuda.get_device_name(0)}")

# Quick smoke test
x = torch.randn(3, 3).cuda()
print(f"Tensor on GPU: {x.device}")
print("✓ PyTorch ROCm working on gfx1151!")
```

---

## Quick Reference: All Available AMD Repo URLs

```
ROCm 7.2  → https://repo.radeon.com/rocm/manylinux/rocm-rel-7.2/
ROCm 7.1  → https://repo.radeon.com/rocm/manylinux/rocm-rel-7.1/
ROCm 7.0  → https://repo.radeon.com/rocm/manylinux/rocm-rel-7.0/
ROCm 6.4.1→ https://repo.radeon.com/rocm/manylinux/rocm-rel-6.4.1/
ROCm 6.4  → https://repo.radeon.com/rocm/manylinux/rocm-rel-6.4/
ROCm 6.3  → https://repo.radeon.com/rocm/manylinux/rocm-rel-6.3/
ROCm 6.2.3→ https://repo.radeon.com/rocm/manylinux/rocm-rel-6.2.3/
ROCm 6.2  → https://repo.radeon.com/rocm/manylinux/rocm-rel-6.2/
ROCm 6.1  → https://repo.radeon.com/rocm/manylinux/rocm-rel-6.1/
ROCm 6.0  → https://repo.radeon.com/rocm/manylinux/rocm-rel-6.0/
```

Community wheels: `https://github.com/scottt/rocm-TheRock/releases`

---

## Common Issues and Fixes

| Error | Cause | Fix |
|---|---|---|
| `invalid device function` | Wheel has no gfx1151 kernels | Switch to community wheels or set `HSA_OVERRIDE_GFX_VERSION=11.0.0` |
| `No GPU found` / `device_count() == 0` | `CUDA_VISIBLE_DEVICES=""` set | Run `unset CUDA_VISIBLE_DEVICES && export HIP_VISIBLE_DEVICES=0` |
| Wrong torch installed over gfx1151 wheel | Another package pulled in CUDA torch | Pin torch in requirements and install community wheel last |
| `GLIBCXX_3.4.x not found` | Wheel built on newer glibc | Use a container or upgrade libc++ / libstdc++ |
| Flash-attention not available | Not compiled for gfx1151 | Set `FLASH_ATTENTION_TRITON_AMD_ENABLE=TRUE` to use Triton fallback |

---

## Docker Alternative (No Wheel Hunting)

For maximum compatibility with gfx1151, use AMD's official Docker image:

```bash
docker run --device /dev/kfd --device /dev/dri --group-add video \
  -it rocm/pytorch:latest bash
# Includes: Ubuntu 24.04 + ROCm 7.1.1 + Python 3.12 + PyTorch 2.9.1
```

---

## Workflow Summary

When invoked, follow these steps:
1. Run detection commands (Step 1) to get ROCm version, Python version, GPU arch
2. Check if `gfx1151` is present in `rocminfo` output
3. Use the decision logic (Step 2) to pick Official vs Community wheels
4. Generate exact `pip install` commands from Step 3A or 3B
5. Show the environment variable setup from Step 4
6. Offer the verification script from Step 5
