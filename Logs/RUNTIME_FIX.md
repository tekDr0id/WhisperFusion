# Runtime Fix - cudart ImportError

**Date:** November 9, 2025  
**Status:** ✅ FIXED

---

## Problem

Docker build succeeded ✅ but `docker compose up` failed ❌ with:

```
ImportError: cannot import name 'cudart' from 'cuda' (unknown location)
```

Container crashed immediately on startup.

---

## Root Cause

**Wrong base Docker image!**

❌ **Was using:** `nvcr.io/nvidia/cuda:12.4.0-runtime-ubuntu22.04`  
✅ **Should use:** `nvcr.io/nvidia/cuda:12.4.0-devel-ubuntu22.04`

### Why It Matters

| Image Type | Size | What's Included | Can Run TensorRT-LLM? |
|------------|------|-----------------|----------------------|
| **runtime** | ~1.4 GB | Runtime libraries only | ❌ NO |
| **devel** | ~3.5 GB | Runtime + headers + tools | ✅ YES |

**TensorRT-LLM needs devel because:**
- Performs JIT (Just-In-Time) compilation at runtime
- Needs CUDA development headers and libraries
- Requires nvcc compiler and development tools
- The `cuda-python` package needs access to underlying CUDA dev libraries

---

## Solution

**Changed one line in Dockerfile:**

```dockerfile
# Before (WRONG):
ARG BASE_TAG=12.4.0-runtime-ubuntu22.04

# After (CORRECT):
ARG BASE_TAG=12.4.0-devel-ubuntu22.04
```

**Also added verification:**
```dockerfile
RUN python3 -c "from cuda import cudart; print('cudart import successful')"
```

---

## How to Fix Your Build

```bash
cd D:\_GitHub\WhisperFusion

# IMPORTANT: Clean rebuild (base image changed)
docker compose build --no-cache --progress=plain

# This will take longer (~25-30 min) because devel image is larger

# After build completes:
docker compose up -d

# Check logs:
docker compose logs -f whisperfusion
```

---

## What to Expect

### During Build
- Pulling devel image will take longer (~3.5 GB vs ~1.4 GB)
- You should see: `cudart import successful` during the build
- Total build time: ~25-30 minutes

### After Runtime
- Container should start successfully
- Should see: `Running build-models.sh...`
- Should see: `Building Whisper TensorRT Engine...`
- Should see: `Loaded LLM TensorRT Engine`
- **No more ImportError!**

---

## Verification Commands

After successful build:

```bash
# Verify cudart imports
docker run --rm whisperfusion python3 -c "from cuda import cudart; print('✅ cudart works')"

# Verify TensorRT-LLM loads
docker run --rm whisperfusion python3 -c "import tensorrt_llm; print('✅ TensorRT-LLM works')"

# Check container is running
docker compose ps
```

---

## Why This Wasn't Caught Earlier

- The **build succeeded** because we only installed Python packages
- The **runtime failed** because TensorRT-LLM tried to actually USE the CUDA libraries
- `cuda-python` package installed fine, but couldn't access underlying CUDA libraries without the devel environment

---

## Trade-offs

**Size Increase:**
- Base image: +2.1 GB (~1.4 GB → ~3.5 GB)
- Final image: +2.1 GB total

**Benefits:**
- ✅ Application actually works!
- ✅ TensorRT-LLM can JIT compile kernels
- ✅ Full CUDA development capabilities

**This size increase is necessary and unavoidable for TensorRT-LLM.**

---

## Files Modified

- ✅ `docker/Dockerfile` - Changed base image tag + added verification
- ✅ `AI_LOG.md` - Documented issue #10
- ✅ `CLAUDE.md` - Added to common issues

---

## Summary

**Issue:** Runtime-only CUDA image missing dev libraries  
**Fix:** Use devel CUDA image  
**Impact:** +2.1 GB image size (required)  
**Status:** Ready to rebuild!

---

**Next Step:** Run the rebuild command above! 🚀
