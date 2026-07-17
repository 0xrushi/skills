---
name: blackwell-torch-vllm-installer
description: Installs PyTorch (cu128 / CUDA 12.8) and vLLM nightly in a uv project, targeting NVIDIA Blackwell GPUs. Handles the full chain: pyproject.toml configuration, numpy version conflicts, prerelease flags, missing CUDA shared-library wheels (cusparseLt, nvshmem), and environment-restriction to Linux. Use when the user asks about installing vLLM or PyTorch with CUDA 12.8/cu128 via uv, hitting dependency resolution errors with vllm nightly, or getting ImportError on libcusparseLt / libnvshmem.
---

# Blackwell PyTorch + vLLM Installer (cu128 / uv)

This skill guides installing PyTorch CUDA 12.8 and vLLM nightly in a `uv` project on Linux (targeting NVIDIA Blackwell and other CUDA 12.8 capable GPUs).

---

## Step 1: Configure pyproject.toml

Add the vLLM nightly index and restrict the resolver to the target platform to avoid Windows resolution failures:

```toml
[project]
dependencies = [
  "numpy<2.4",   # vLLM/mistral-common requires numpy<2.4; pin explicitly
  "vllm",
  "torch",
  "torchvision",
  "torchaudio",
]

[tool.uv]
# Restrict to Linux Python 3.12 — prevents resolver from checking Windows/other envs
environments = ["sys_platform == 'linux' and python_full_version >= '3.12' and python_full_version < '3.13'"]
torch-backend = "cu128"   # CUDA 12.8 for Blackwell (RTX 5xxx, H100, B100, etc.)

[[tool.uv.index]]
name = "vllm-nightly"
url = "https://wheels.vllm.ai/nightly"
explicit = false
```

**Why `numpy<2.4`**: vLLM's `mistral-common` dependency pins `numpy>=1.25,<2.4`. If your project has `numpy==2.4.x`, resolution fails.

---

## Step 2: Install PyTorch cu128

```bash
UV_TORCH_BACKEND=cu128 uv add torch torchvision torchaudio
uv sync
```

Or use the `pyproject.toml` `torch-backend` key and just:

```bash
uv add torch torchvision torchaudio
uv sync
```

---

## Step 3: Install vLLM Nightly

vLLM nightly builds are prereleases and may only be on the nightly index, so pass both flags:

```bash
UV_TORCH_BACKEND=cu128 uv add vllm \
  --prerelease=allow \
  --index-strategy unsafe-best-match
```

**Why `--prerelease=allow`**: vLLM nightly versions are tagged as prerelease (e.g. `0.23.1rc1.dev205+...`); uv skips them by default.

**Why `--index-strategy unsafe-best-match`**: By default uv only looks at the first index that contains a package. This flag allows the resolver to pick the best version across all indexes.

---

## Step 4: Fix Missing CUDA Shared Libraries

After install, `import torch` may fail with `ImportError` on missing `.so` files. Fix them in order:

### `libcusparseLt.so.0`

```bash
uv add nvidia-cusparselt-cu12
uv sync
```

### `libnvshmem_host.so.3`

```bash
uv add nvidia-nvshmem-cu12
uv sync
```

Add both proactively to avoid multiple restart cycles:

```bash
uv add nvidia-cusparselt-cu12 nvidia-nvshmem-cu12
uv sync
```

---

## Step 5: Verify Installation

```bash
uv run python -c "import torch; print(torch.__version__); print(torch.version.cuda); print(torch.cuda.is_available())"
```

Expected output:
```
2.x.x+cu128
12.8
True
```

Full verification:

```python
import torch
print(f"torch:          {torch.__version__}")
print(f"CUDA version:   {torch.version.cuda}")
print(f"CUDA available: {torch.cuda.is_available()}")
print(f"Device count:   {torch.cuda.device_count()}")
print(f"Device name:    {torch.cuda.get_device_name(0)}")

x = torch.randn(3, 3, device='cuda')
print(f"Tensor on GPU:  {x.device}")
```

---

## GGUF Support

To enable GGUF model loading in vLLM, install the plugin:

```bash
uv add vllm-gguf-plugin
```

### Serving a GGUF Model

GGUF repos on HuggingFace use the format `owner/repo:quantization` (e.g. `:Q4_K_M`). You must also point vLLM at the original model for its config and tokenizer:

```bash
uv run -- vllm serve \
    "owner/model-name-GGUF:Q4_K_M" \
    --hf-config-path "owner/model-name" \
    --tokenizer "owner/model-name" \
    --dtype float16 \
    --gpu-memory-utilization 0.88 \
    --max-model-len 32768 \
    --served-model-name "model-name-Q4_K_M"
```

- `"owner/model-name-GGUF:Q4_K_M"` — the GGUF repo and quant level to load
- `--hf-config-path` — the original (non-GGUF) repo, needed for `config.json`
- `--tokenizer` — the original repo's tokenizer
- `--dtype float16` — use float16 precision; Blackwell GPUs also support `bfloat16` (default) or `float32`
- `--gpu-memory-utilization 0.88` — fraction of VRAM to use for weights + KV cache (default 0.90); lower if KV cache allocation fails
- `--max-model-len 32768` — cap the context window; some models declare enormous defaults (e.g. 262144) that exhaust VRAM on KV cache allocation even on 32 GB cards; 32768 is a practical cap for most single-GPU setups
- `--served-model-name` — alias used in the OpenAI-compatible API responses

> The `NCCL destroy_process_group` warning printed after a failed startup is cleanup noise — not the root cause.

---

## Full One-Shot Install (fresh project)

```bash
# 1. Configure pyproject.toml as shown in Step 1

# 2. Install all at once
UV_TORCH_BACKEND=cu128 uv add \
  torch torchvision torchaudio \
  nvidia-cusparselt-cu12 nvidia-nvshmem-cu12 \
  vllm vllm-gguf-plugin \
  --prerelease=allow \
  --index-strategy unsafe-best-match

uv sync
```

---

## Nuclear Reset (when resolution is badly broken)

If the lockfile is in a bad state or packages were installed in the wrong order:

```bash
rm -rf .venv uv.lock

UV_TORCH_BACKEND=cu128 uv sync \
  --prerelease=allow \
  --index-strategy unsafe-best-match
```

---

## Cross-filesystem Warning

If `uv` warns about failing to hardlink:

```
warning: Failed to hardlink files; falling back to full copy.
```

Suppress with:

```bash
export UV_LINK_MODE=copy
```

Or add to your shell profile. This is benign but slows installs when cache and venv are on different filesystems.

---

## Common Errors and Fixes

| Error | Cause | Fix |
|---|---|---|
| `numpy==2.4.x` conflicts with `vllm` | `mistral-common` pins `numpy<2.4` | Change `numpy` dep to `numpy<2.4` in `pyproject.toml` |
| `No solution found … sys_platform == 'win32'` | Resolver checking Windows env | Add `tool.uv.environments` to restrict to Linux |
| `vllm was found on nightly, but not at requested version` | Nightly only has prerelease versions | Add `--prerelease=allow --index-strategy unsafe-best-match` |
| `ImportError: libcusparseLt.so.0` | Missing `nvidia-cusparselt-cu12` wheel | `uv add nvidia-cusparselt-cu12` |
| `ImportError: libnvshmem_host.so.3` | Missing `nvidia-nvshmem-cu12` wheel | `uv add nvidia-nvshmem-cu12` |
| `torch.cuda.is_available()` returns `False` | Wrong CUDA wheel or driver mismatch | Verify driver supports CUDA 12.8; check `nvidia-smi` |
| `nvcc fatal: Unsupported gpu architecture 'compute_1.'` while building `vllm==0.2.5` (or another ancient version) from source | Unpinned `vllm`/`torch` deps. Every modern vLLM release pins an exact `torch==X.Y.Z`; if your own `torch` dep is unpinned, the resolver walks newest→oldest vLLM hunting for a version whose torch pin matches whatever it already picked, backtracking through unrelated conflicts (e.g. `nvidia-cusparselt-cu12` version mismatches) along the way. It eventually bottoms out at an ancient vLLM with *no* torch pin — nothing left to conflict on — but that release predates Blackwell's compute capability 12.0, so its build script mangles "12.0" into garbage and nvcc rejects it. Confirm via `uv.lock`: `registry = "https://pypi.org/simple"` + a suspiciously old `vllm` version is the tell | Pin `vllm` to a recent explicit version, find what exact `torch`/`torchvision`/`torchaudio` versions *that* release requires (`rm uv.lock && uv lock -v > /tmp/lock.log 2>&1`, then `grep "Adding transitive dependency for vllm==X: torch"`), and pin those to match exactly. A single valid resolution point can't backtrack into a decade-old fallback. Prebuilt wheels resolved this way never touch nvcc — if `uv sync` is invoking `nvcc`/`ninja` for vLLM at all, something upstream is still unpinned. |

**Debug resolution with the resolver's own reasoning, don't guess-and-edit**: `rm uv.lock && uv lock -v > /tmp/lock.log 2>&1`, then `grep -n "Recording dependency conflict\|Selecting:\|Backtracked" /tmp/lock.log`. This shows exactly which package/version pairs got rejected and why.

**`--prerelease=allow` / `--index-strategy unsafe-best-match` are project-scoped — keep them in `[tool.uv]` in that project's own `pyproject.toml`, not as ad-hoc CLI flags.** A `uv lock`/`uv add` invoked with these flags from the wrong shell cwd (e.g. after a `cd` that didn't stick, or a persistent-shell cwd silently resetting) will happily pull prerelease versions of totally unrelated dependencies in a sibling/parent project — e.g. `httpx` resolving to `1.0.dev3` or `pydantic` to `2.14.0a1` — silently corrupting that project's lockfile. Before any `rm uv.lock` / `uv lock` / `uv sync`, run `pwd` first if there's any doubt which project's directory the shell is actually in, especially in a monorepo with a nested vLLM subproject.

---

## pyproject.toml Quick Reference

```toml
[tool.uv]
environments = ["sys_platform == 'linux' and python_full_version >= '3.12' and python_full_version < '3.13'"]
torch-backend = "cu128"

[[tool.uv.index]]
name = "vllm-nightly"
url = "https://wheels.vllm.ai/nightly"
explicit = false
```

## Workflow Summary

When invoked, follow these steps:
1. Check if `pyproject.toml` exists; if not, create one with `uv init`
2. Add the vllm-nightly index and environment restriction to `pyproject.toml` (Step 1)
3. Set `numpy<2.4` in dependencies if numpy is pinned to 2.4+
4. Run the torch cu128 install (Step 2)
5. Run the vLLM nightly install with prerelease + unsafe-best-match flags (Step 3)
6. Proactively add both missing CUDA library wheels (Step 4)
7. Verify with `uv run python -c "import torch; print(torch.cuda.is_available())"` (Step 5)
8. If anything is broken, offer the nuclear reset (Step 6)
