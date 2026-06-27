#!/usr/bin/env bash
# patch-vllm-cuda12.sh
# Fix vLLM C extensions for CUDA 13.0 systems
#
# Problem: vLLM's compiled .so files link against libcudart.so.12
# but CUDA 13 systems only provide libcudart.so.13
#
# Solution: Install nvidia-cuda-runtime-cu12 and patch RPATH

set -euo pipefail

echo "=== vLLM CUDA 12 Compatibility Patch ==="

# Step 1: Install backward-compatible CUDA 12 runtime
echo "[1/3] Installing nvidia-cuda-runtime-cu12..."
pip install nvidia-cuda-runtime-cu12 2>/dev/null || uv pip install nvidia-cuda-runtime-cu12 2>/dev/null || {
    echo "Warning: Could not install nvidia-cuda-runtime-cu12 via pip/uv"
    echo "  Try: uv pip install nvidia-cuda-runtime-cu12"
    echo "  Or: pip install nvidia-cuda-runtime-cu12"
}

# Step 2: Find all vLLM .so files
echo "[2/3] Finding vLLM C extension .so files..."

VLLM_SO_FILES=()

# Method 1: Try to get from Python import
PYTHON_SO=$(python3 -c "
import vllm._custom_ops as ops
import os
print(os.path.dirname(ops.__file__))
" 2>/dev/null)

if [ -n "$PYTHON_SO" ] && [ -d "$PYTHON_SO" ]; then
    mapfile -t VLLM_SO_FILES < <(find "$PYTHON_SO" -maxdepth 2 -name "*.so" -type f 2>/dev/null)
    echo "  Found .so files in: $PYTHON_SO"
fi

# Method 2: Fallback to site-packages search
if [ ${#VLLM_SO_FILES[@]} -eq 0 ]; then
    echo "  Searching site-packages for vLLM .so files..."
    SITE_PKGS=$(python3 -c "import site; print(site.getsitepackages()[0])" 2>/dev/null)
    if [ -n "$SITE_PKGS" ]; then
        mapfile -t VLLM_SO_FILES < <(find "$SITE_PKGS" -path "*vllm*" -name "*.so" -type f 2>/dev/null)
    fi
fi

if [ ${#VLLM_SO_FILES[@]} -eq 0 ]; then
    echo "  No vLLM .so files found. Attempting broader search..."
    mapfile -t VLLM_SO_FILES < <(find / -path "*vllm*" -name "*.so" -type f 2>/dev/null | head -50)
fi

echo "  Found ${#VLLM_SO_FILES[@]} .so files"

# Step 3: Patch RPATH on each .so file
echo "[3/3] Patching RPATH on .so files..."

PATCHED=0
for so in "${VLLM_SO_FILES[@]}"; do
    if [ ! -f "$so" ]; then continue; fi
    
    # Get the directory of the .so file for $ORIGIN rpath
    SO_DIR=$(dirname "$so")
    
    # Check if libcudart.so.12 exists in the nvidia package
    CUDA12_LIB=$(find "$HOME/.cache/uv" -name "libcudart.so.12" 2>/dev/null | head -1)
    if [ -z "$CUDA12_LIB" ]; then
        CUDA12_LIB=$(find "$HOME/.local" -name "libcudart.so.12" 2>/dev/null | head -1)
    fi
    if [ -z "$CUDA12_LIB" ]; then
        CUDA12_LIB=$(find /usr -name "libcudart.so.12*" 2>/dev/null | head -1)
    fi
    
    if [ -n "$CUDA12_LIB" ]; then
        CUDA12_DIR=$(dirname "$CUDA12_LIB")
        patchelf --set-rpath "\$ORIGIN:$CUDA12_DIR:$SO_DIR" "$so" 2>/dev/null && {
            echo "  Patched: $so (rpath=$CUDA12_DIR)"
            PATCHED=$((PATCHED + 1))
        }
    else
        # Fallback: just set $ORIGIN
        patchelf --set-rpath "\$ORIGIN:$SO_DIR" "$so" 2>/dev/null && {
            echo "  Patched: $so (rpath=\$ORIGIN:$SO_DIR)"
            PATCHED=$((PATCHED + 1))
        }
    fi
done

echo ""
echo "=== Patching Complete ==="
echo "  Patched $PATCHED .so files"
echo ""
echo "Test vLLM import:"
python3 -c "import vllm; print('vLLM imported successfully!')" 2>&1 || {
    echo "  vLLM import still failing. Check that nvidia-cuda-runtime-cu12 is installed."
}
