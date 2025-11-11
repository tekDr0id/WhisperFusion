# Docker Build Fix - Final Version

## Problems Found

### 1. PyAV Compilation Error
`faster-whisper==0.9.0` forces `av==10.*`, which fails to compile with modern Cython.

### 2. Torch Version Conflict  
Dependencies were upgrading torch to 2.9.0, but `tensorrt_llm==0.10.0` requires `torch>=2.2.0,<2.4.0`.

### 3. Missing huggingface-cli
The forced upgrade of huggingface_hub was breaking the CLI tool.

## Solutions Applied

### Fix 1: Install PyAV First with Prebuilt Wheels
```bash
pip install --no-cache-dir --only-binary=:all: 'av>=12.0.0'
```
- Forces use of prebuilt wheels (no compilation)
- Installed before faster-whisper to prevent downgrade

### Fix 2: Pin Torch Version
```bash
pip install 'torch>=2.2.0,<2.4.0' --index-url https://download.pytorch.org/whl/cu124
```
- Pins torch to version compatible with tensorrt_llm
- Prevents dependencies from upgrading it

### Fix 3: Install faster-whisper Last
```bash
pip install 'faster-whisper>=1.0.0' || pip install --no-deps faster-whisper==0.9.0
```
- Tries newer version first (supports av 12.x)
- Falls back to 0.9.0 without deps (uses already-installed av 12.x)

### Fix 4: Remove Forced Upgrades
- Removed the forced upgrade of huggingface_hub and tokenizers
- Let pip manage versions according to transformers requirements

## Installation Order (Critical!)

```
1. Upgrade pip/setuptools/wheel
2. Pin torch to 2.2.0-2.3.0 range
3. Install av>=12.0.0 (prebuilt wheels only)
4. Install other requirements (except faster-whisper)
5. Install faster-whisper (newer version or 0.9.0 without deps)
6. Download models
```

## Files Modified

### `docker/scripts/setup-whisperfusion.sh`
Complete rewrite with proper installation order.

### `requirements.txt`
```diff
- faster-whisper==0.9.0
+ # faster-whisper will be installed separately to handle av compatibility
```

## Rebuild Command

```bash
cd D:\_GitHub\WhisperFusion
docker-compose build --no-cache
```

**Important**: Use `--no-cache` to ensure changes are applied!

## Expected Outcome

After successful build, versions should be:
- `av`: 12.x.x or higher ✅
- `torch`: 2.2.x or 2.3.x ✅
- `faster-whisper`: 1.x.x or 0.9.0 ✅
- `tensorrt_llm`: 0.10.0 ✅
- `transformers`: 4.40.2 ✅

## Verification Commands

```bash
# Check av version
docker run --rm whisperfusion python3 -c "import av; print(f'av: {av.__version__}')"

# Check torch version
docker run --rm whisperfusion python3 -c "import torch; print(f'torch: {torch.__version__}')"

# Check faster-whisper
docker run --rm whisperfusion python3 -c "import faster_whisper; print(f'faster-whisper: {faster_whisper.__version__}')"

# Check all work together
docker run --rm whisperfusion python3 -c "import av, torch, faster_whisper, tensorrt_llm; print('✅ All imports successful')"
```

## Why This Works

1. **PyAV 12.x has prebuilt wheels** - No compilation needed, no Cython issues
2. **Installation order matters** - Installing av first prevents pip from downgrading it
3. **Torch version pinning** - Keeps tensorrt_llm happy
4. **No forced upgrades** - Respects dependency constraints from transformers
5. **--no-deps for faster-whisper** - Prevents it from forcing av==10.*

## Troubleshooting

If build still fails:

### Issue: "huggingface-cli: command not found"
**Solution**: The huggingface_hub package should provide this. Check if transformers is installing correctly.

### Issue: Torch version conflict
**Solution**: The torch pinning should handle this. If not, check what's pulling in torch 2.9.0.

### Issue: av still trying to compile
**Solution**: Make sure `--only-binary=:all:` flag is present and pip is upgraded.

## Date Applied
October 30, 2025 - Final Version
