---
name: blackwell-gpu
description: Set up and configure NVIDIA Blackwell (RTX 50-series, SM120) GPU environment including PyTorch, vLLM, Unsloth, flash-attn, and xformers. Use when working with RTX 5000/5090, Blackwell GPUs, CUDA 13.0, or when encountering CUDA compatibility issues on SM120 architecture.
---

# Blackwell GPU Setup Skill

This skill guides through setting up a complete machine learning environment for NVIDIA Blackwell GPUs (RTX 5090, RTX 5000 Ada, B200, etc.) with CUDA 13.0 support.

## Hardware Requirements

- NVIDIA GPU with Blackwell architecture (compute capability **SM120**): RTX 5090, RTX 5000 Ada, B200, GB200
- NVIDIA driver **595+** (required for CUDA 13.0 / SM120 support)
- Ubuntu 22.04+ or 24.04
- At least **32GB VRAM** recommended for fine-tuning (RTX 5090 has 32GB)

## Quick Check

Verify your GPU is detected and the driver is correct:

```bash
nvidia-smi
```

Expected: Driver version 595+, and GPU model showing RTX 5090 / RTX 5000 Ada / B200 etc.

Check CUDA architecture support:

```bash
python3 -c "import torch; print(f'CUDA: {torch.cuda.is_available()}, Device: {torch.cuda.get_device_name(0)}, Compute Cap: {torch.cuda.get_device_capability(0)}')"
```

---

## Prerequisites: System Dependencies

Run this once to install system-level dependencies needed for CUDA 13.0 compilation:

```bash
sudo apt update
sudo apt install -y gcc g++ make cmake build-essential \
    python3-dev python3-pip \
    ninja-build libnccl2 libnccl-dev \
    cuda-toolkit-13-0 2>/dev/null || true \
    wget curl git
```

> **Note:** `cuda-toolkit-13-0` may not be in default repos. If unavailable, install from NVIDIA's repository or skip — PyTorch ships its own CUDA runtime.

---

## 1. Install PyTorch with CUDA 13.0

Blackwell requires **PyTorch 2.7+** built against **CUDA 13.0** (cu130). Use `uv` for the fastest install:

```bash
uv pip install torch torchvision --index-url https://download.pytorch.org/whl/cu130
```

Or with pip:

```bash
pip install torch torchvision --index-url https://download.pytorch.org/whl/cu130
```

Verify installation:

```bash
python3 -c "
import torch
print(f'PyTorch: {torch.__version__}')
print(f'CUDA: {torch.cuda.is_available()}')
print(f'Device: {torch.cuda.get_device_name(0)}')
print(f'Compute Capability: {torch.cuda.get_device_capability(0)}')
"
```

---

## 2. Install vLLM for Blackwell

vLLM on Blackwell requires solving **5 key issues**. Follow these steps in order:

### Step 2a: Install vLLM

```bash
uv pip install vllm --torch-backend=auto
```

### Step 2b: Fix libcudart.so.12 compatibility

vLLM's C extensions are compiled against CUDA 12 but CUDA 13 systems only ship `libcudart.so.13`.

**Fix:** Install the backward-compatible CUDA 12 runtime and patch the RPATH on vLLM's `.so` files:

```bash
# Install libcudart.so.12 compatibility package
uv pip install nvidia-cuda-runtime-cu12

# Find and patch all affected .so files in the vLLM package
SO_FILES=$(python3 -c "
import vllm._custom_ops as ops
import os, glob
base = os.path.dirname(ops.__file__)
for f in glob.glob(os.path.join(base, '*.so')):
    print(f)
" 2>/dev/null || find $(python3 -c "import site; print(site.getsitepackages()[0])") -name "_vllm*.so" -o -name "_C*.so" -o -name "_moe_C*.so" -o -name "_flashmla*.so" 2>/dev/null)

for so in $SO_FILES; do
    if [ -f "$so" ]; then
        patchelf --set-rpath \$ORIGIN:$HOME/.cache/uv/sdists-v9  "$so" 2>/dev/null || true
    fi
done
```

Alternatively, use the helper script:

```bash
./scripts/patch-vllm-cuda12.sh
```

### Step 2c: Install FlashInfer JIT dependencies

FlashInfer JIT-compiles CUDA kernels at runtime. It requires these system packages:

```bash
sudo apt install -y gcc python3-dev python3.12-dev cuda-toolkit ninja-build
```

### Step 2d: GDN model parameter fix

For Qwen3.5 27B+ and other GDN (Gated DeltaNet) models, use:

```bash
vllm serve <model> --max-num-batched-tokens 2096 --kv-cache-dtype fp8 --dtype bfloat16
```

### Step 2e: Attention backend note

Do **NOT** combine `--attention-backend FLASH_ATTN` with `--kv-cache-dtype fp8` — this causes a silent crash. Use the default FlashInfer backend with fp8 instead.

---

## 3. Install Unsloth for Blackwell

Unsloth supports Blackwell with custom kernels. Install as follows:

### Using uv (recommended):

```bash
uv pip install unsloth --torch-backend=auto
```

### Or with conda:

```bash
conda create --name unsloth-blackwell python==3.12 -y
conda activate unsloth-blackwell
pip install -U vllm --extra-index-url https://download.pytorch.org/whl/cu128
pip install unsloth unsloth_zoo bitsandbytes
```

### Install xformers from source (optional but recommended for performance):

```bash
git clone https://github.com/facebookresearch/xformers.git
cd xformers
git checkout main
TORCH_CUDA_ARCH_LIST="12.0" pip install -v --no-build-isolation .
cd ..
```

### Update transformers:

```bash
uv pip install -U transformers
```

### Verify Unsloth:

```bash
python3 -c "
from unsloth import FastLanguageModel
print('Unsloth loaded successfully!')
"
```

---

## 4. Install flash-attn (optional, for attention optimization)

```bash
TORCH_CUDA_ARCH_LIST="12.0" pip install flash-attn --no-build-isolation
```

---

## 5. Install flashinfer (optional, for inference acceleration)

```bash
uv pip install flashinfer-python -i https://flashinfer.ai/whl/cu130/torch3.0/
```

Or for CUDA 13.0:

```bash
pip install flashinfer-python --extra-index-url https://flashinfer.ai/whl/cu130/torch3.0/
```

---

## Complete One-Command Setup

For a fresh environment, run the all-in-one setup script:

```bash
./scripts/setup-blackwell.sh
```

This script installs: PyTorch (cu130), vLLM (with CUDA 12 compat patches), Unsloth, xformers, flash-attn, and all system dependencies.

---

## Troubleshooting

### ImportError: libcudart.so.12

vLLM's C extensions link against CUDA 12 but the system has CUDA 13. Fix with:

```bash
uv pip install nvidia-cuda-runtime-cu12
./scripts/patch-vllm-cuda12.sh
```

### FlashInfer JIT compilation fails

Install missing build tools:

```bash
sudo apt install -y gcc python3-dev nvcc ninja-build
```

### Engine core initialization failed

This is a generic error — check the actual cause in `/tmp/vllm-*.log` or run with `--log-level DEBUG`. Common causes:
- GDN models need `--max-num-batched-tokens 2096`
- FLASH_ATTN backend is incompatible with `--kv-cache-dtype fp8`

### CUDA out of memory on Blackwell

Try Unsloth's memory optimizations:

```python
from unsloth import FastLanguageModel
model = FastLanguageModel.from_pretrained(
    "model_name",
    max_seq_length=8192,
    load_in_4bit=True,  # or False for full precision
)
```

### Driver too old

Blackwell requires driver **595+**. Update with:

```bash
sudo apt install -y nvidia-driver-595  # or use the NVIDIA repository
```

---

## Reference Links

- [vLLM Blackwell Issue #37714](https://github.com/vllm-project/vllm/issues/37714) — Full chain of Blackwell setup problems and fixes
- [Unsloth Blackwell Guide](https://unsloth.ai/docs/blog/fine-tuning-llms-with-blackwell-rtx-50-series-and-unsloth) — Unsloth's official Blackwell setup guide
- [PyTorch CUDA 13.0 Wheels](https://download.pytorch.org/whl/cu130) — Pre-built PyTorch for CUDA 13.0

---

## Skill Scripts

This skill includes helper scripts in the `scripts/` directory:
- `setup-blackwell.sh` — One-command full environment setup
- `patch-vllm-cuda12.sh` — Patch vLLM for CUDA 12/13 compatibility
