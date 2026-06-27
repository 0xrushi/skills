#!/usr/bin/env bash
# setup-blackwell.sh
# Complete Blackwell GPU (RTX 50-series / SM120) environment setup
#
# Installs: system deps, PyTorch (cu130), vLLM (with CUDA 12 compat patches),
#           Unsloth, xformers, flash-attn, and all supporting libraries

set -euo pipefail

BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

info()  { echo -e "${BLUE}[INFO]${NC} $1"; }
ok()    { echo -e "${GREEN}[ OK ]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERR ]${NC} $1"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ============================================================
# Pre-flight checks
# ============================================================
info "=== Blackwell GPU Setup ==="

# Check nvidia-smi
if ! command -v nvidia-smi &>/dev/null; then
    error "nvidia-smi not found. Is the NVIDIA driver installed?"
    exit 1
fi

GPU_NAME=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1)
DRIVER_VERSION=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | head -1)

info "GPU: $GPU_NAME"
info "Driver: $DRIVER_VERSION"

if [[ "$DRIVER_VERSION" < "595" ]]; then
    warn "Driver version $DRIVER_VERSION is below 595. Blackwell may not be fully supported."
    warn "Consider upgrading to driver 595+ for CUDA 13.0 / SM120 support."
fi

# Check Python
if ! command -v python3 &>/dev/null; then
    error "python3 not found. Install Python 3.12+ first."
    exit 1
fi

PYTHON_VERSION=$(python3 -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")
info "Python: $PYTHON_VERSION"

# Check if uv is available
if ! command -v uv &>/dev/null; then
    warn "uv is not installed. Installing uv..."
    curl -LsSf https://astral.sh/uv/install.sh | sh
    export PATH="$HOME/.local/bin:$PATH"
    export PATH="$HOME/.cargo/bin:$PATH"
fi

# ============================================================
# Step 1: System dependencies
# ============================================================
info "Step 1: Installing system dependencies..."
sudo apt-get update -qq
sudo apt-get install -y -qq \
    gcc g++ make cmake build-essential \
    python3-dev python3-pip \
    ninja-build libnccl2 libnccl-dev \
    wget curl git ca-certificates \
    2>/dev/null || warn "Some system packages may have failed to install"

ok "System dependencies installed"

# ============================================================
# Step 2: PyTorch with CUDA 13.0
# ============================================================
info "Step 2: Installing PyTorch with CUDA 13.0..."
uv pip install torch torchvision --index-url https://download.pytorch.org/whl/cu130 --quiet

echo "PyTorch verification:"
python3 -c "
import torch
print(f'  PyTorch version: {torch.__version__}')
print(f'  CUDA available: {torch.cuda.is_available()}')
if torch.cuda.is_available():
    print(f'  Device: {torch.cuda.get_device_name(0)}')
    print(f'  Compute Capability: {torch.cuda.get_device_capability(0)}')
"
ok "PyTorch installed"

# ============================================================
# Step 3: vLLM with CUDA 12 compat fix
# ============================================================
info "Step 3: Installing vLLM..."
uv pip install vllm --torch-backend=auto --quiet

# Install CUDA 12 runtime for vLLM C extensions
info "  Patching vLLM for CUDA 12/13 compatibility..."
uv pip install nvidia-cuda-runtime-cu12 --quiet

# Run the patching script
bash "$SCRIPT_DIR/patch-vllm-cuda12.sh"

ok "vLLM installed"

# ============================================================
# Step 4: Unsloth
# ============================================================
info "Step 4: Installing Unsloth..."
uv pip install unsloth unsloth_zoo bitsandbytes --quiet

ok "Unsloth installed"

# ============================================================
# Step 5: xformers from source
# ============================================================
info "Step 5: Installing xformers from source..."

XFDIR=$(mktemp -d)
cd "$XFDIR"
git clone --depth 1 https://github.com/facebookresearch/xformers.git 2>/dev/null || {
    warn "Could not clone xformers. Skipping xformers installation."
}

if [ -d xformers ]; then
    cd xformers
    TORCH_CUDA_ARCH_LIST="12.0" pip install -v --no-build-isolation . 2>&1 | tail -5 || {
        warn "xformers build failed. Unsloth will use PyTorch native SDPA instead."
    }
    cd - > /dev/null
else
    warn "xformers source not available."
fi
rm -rf "$XFDIR"

ok "xformers setup complete"

# ============================================================
# Step 6: flash-attn (optional)
# ============================================================
info "Step 6: Installing flash-attn..."
TORCH_CUDA_ARCH_LIST="12.0" pip install flash-attn --no-build-isolation --quiet 2>/dev/null || {
    warn "flash-attn installation failed. Unsloth includes optimized kernels."
}
ok "flash-attn setup complete"

# ============================================================
# Step 7: flashinfer (optional)
# ============================================================
info "Step 7: Installing flashinfer..."
uv pip install flashinfer-python -i https://flashinfer.ai/whl/cu130/torch3.0/ --quiet 2>/dev/null || {
    warn "flashinfer installation failed. Continuing without it."
}
ok "flashinfer setup complete"

# ============================================================
# Step 8: Update transformers
# ============================================================
info "Step 8: Updating transformers..."
uv pip install -U transformers --quiet
ok "transformers updated"

# ============================================================
# Final verification
# ============================================================
echo ""
info "=== Final Verification ==="
echo ""

python3 -c "
import torch
print(f'PyTorch:       {torch.__version__}')
print(f'CUDA:          {torch.cuda.is_available()}')
if torch.cuda.is_available():
    print(f'GPU:           {torch.cuda.get_device_name(0)}')
    print(f'Compute Cap:   {torch.cuda.get_device_capability(0)}')
    print(f'VRAM:          {torch.cuda.get_device_properties(0).total_mem / 1e9:.1f} GB')
print()

try:
    import vllm
    print(f'vLLM:          {vllm.__version__}')
except ImportError as e:
    print(f'vLLM:          FAILED ({e})')
except Exception as e:
    print(f'vLLM:          WARNING ({e})')
print()

try:
    import unsloth
    print(f'Unsloth:       OK')
except ImportError as e:
    print(f'Unsloth:       FAILED ({e})')
print()

try:
    import xformers
    print(f'xformers:      {xformers.__version__}')
except ImportError:
    print(f'xformers:      Not installed (using native SDPA)')
print()

try:
    import flash_attn
    print(f'flash-attn:    {flash_attn.__version__}')
except ImportError:
    print(f'flash-attn:    Not installed')
"

echo ""
ok "=== Blackwell GPU setup complete! ==="
echo ""
echo "Quick start examples:"
echo "  # vLLM server with Blackwell-specific args:"
echo "  vllm serve Qwen/Qwen3.5-27B-FP8 --max-num-batched-tokens 2096 --kv-cache-dtype fp8"
echo ""
echo "  # Unsloth fine-tuning:"
echo "  from unsloth import FastLanguageModel"
echo "  model = FastLanguageModel.from_pretrained('Qwen/Qwen3.5-3B')"
echo ""
echo "  # Check GPU:"
echo "  nvidia-smi"
