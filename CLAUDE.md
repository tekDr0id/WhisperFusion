# CLAUDE.md - AI Assistant Guide for WhisperFusion Project

**Version:** 1.0  
**Last Updated:** November 9, 2025  
**Project:** WhisperFusion - Real-time Speech-to-Speech AI Pipeline

---

## AI Assistant System Prompt

When working on the WhisperFusion project, use this context to maintain, troubleshoot, and build correctly:

---

### Project Overview

**WhisperFusion** is a real-time speech-to-speech AI pipeline that combines:
- **Whisper** (OpenAI) - Speech recognition using TensorRT
- **Phi-3 / Mistral** - Language model (LLM) using TensorRT-LLM
- **WhisperSpeech** - Text-to-speech synthesis
- **Docker** - Containerized deployment with NVIDIA GPU support

**Tech Stack:**
- Python 3.10
- CUDA 12.4.0
- TensorRT-LLM 0.10.0
- PyTorch 2.2.x-2.3.x
- Docker with GPU support
- WebSocket communication

---

### Critical Installation Order

**The order of package installation is CRITICAL for this project. Follow this sequence:**

1. **System Dependencies First**
   - FFmpeg and audio libraries
   - Development headers for av/PyAV

2. **Pin torch to 2.2.0-2.3.x BEFORE anything else**
   ```bash
   uv pip install --system 'torch>=2.2.0,<2.4.0' --index-url https://download.pytorch.org/whl/cu124
   ```
   **Why:** tensorrt_llm 0.10.0 requires torch<2.4.0, other deps try to install 2.9.0

3. **Install PyAV 12.0.0+ with prebuilt wheels BEFORE faster-whisper**
   ```bash
   uv pip install --system --only-binary=:all: 'av>=12.0.0'
   ```
   **Why:** faster-whisper 0.9.0 forces av==10.* which fails to compile with modern Cython

4. **Install requirements.txt EXCLUDING faster-whisper**
   ```bash
   grep -v "faster-whisper" requirements.txt > /tmp/requirements-temp.txt
   uv pip install --system -r /tmp/requirements-temp.txt
   ```

5. **Install faster-whisper LAST**
   ```bash
   uv pip install --system 'faster-whisper>=1.0.0' || uv pip install --system --no-deps faster-whisper==0.9.0
   ```
   **Why:** Prevents downgrade of av to 10.x

**⚠️ NEVER change this order or the build will fail!**

---

### Common Build Issues & Solutions

#### Issue: `uv: not found`
**Cause:** Wrong PATH for uv package manager  
**Solution:** 
- uv installs to `/root/.local/bin` NOT `/root/.cargo/bin`
- Use full path: `/root/.local/bin/uv` in RUN commands
- Set: `ENV PATH="/root/.local/bin:$PATH"`

#### Issue: PyAV Compilation Errors (Cython)
**Cause:** av 10.x doesn't compile with modern Cython  
**Solution:** 
- MUST use av>=12.0.0 with `--only-binary=:all:`
- Install BEFORE faster-whisper
- Never let pip/uv install av 10.x

#### Issue: Torch Version Conflict
**Cause:** Dependencies upgrading torch to 2.9.0  
**Solution:** 
- Pin torch FIRST: `torch>=2.2.0,<2.4.0`
- Install from cu124 index
- tensorrt_llm 0.10.0 requires torch<2.4.0

#### Issue: `huggingface-cli: command not found`
**Cause:** Forced version upgrades breaking dependencies  
**Solution:** 
- Do NOT force upgrade huggingface_hub or tokenizers
- Let transformers manage versions
- Use `hf download` with fallback to `huggingface-cli`

#### Issue: `ImportError: cannot import name 'cudart' from 'cuda'`
**Cause:** Wrong base image - using runtime instead of devel  
**Solution:** 
- Change base image to `12.4.0-devel-ubuntu22.04`
- TensorRT-LLM requires CUDA development libraries for JIT compilation
- The devel image includes headers, nvcc, and development tools
- Size increase: ~1.4 GB → ~3.5 GB (necessary trade-off)

#### Issue: Git Merge Conflicts
**Symptoms:** Syntax errors, `unexpected token '<<<'`  
**Solution:** 
- Check for `<<<<<<<`, `=======`, `>>>>>>>` markers
- Remove ALL merge conflict markers
- Files to check: Dockerfile, setup-whisperfusion.sh, all shell scripts

---

### Key Architecture Components

#### 1. Multi-Process Architecture
```
main.py
├── whisper_process (TranscriptionServer) - Port 6006
│   └── Outputs to: transcription_queue
├── llm_process (TensorRTLLMEngine)
│   ├── Reads from: transcription_queue
│   └── Outputs to: llm_queue, audio_queue
└── tts_process (WhisperSpeechTTS) - Port 8888
    ├── Reads from: audio_queue
    └── WebSocket output to clients
```

#### 2. Queue Flow
```
User Speech → Whisper → transcription_queue → LLM → llm_queue → WebSocket
                                                  ↓
                                            audio_queue → TTS → Audio Output
```

#### 3. Docker Multi-Stage Build
```
base stage:
  - CUDA runtime
  - System packages
  - uv installer

devel stage:
  - CUDA Python bindings
  - TensorRT-LLM
  - TensorRT examples

release stage:
  - WhisperFusion setup
  - Model downloads
  - Final configuration
```

---

### Known Code Issues

#### Critical Fixes Applied (Do NOT reintroduce)

1. **main.py Lines 45-58**: Dead code after raise statements
   ```python
   # WRONG (will confuse developers):
   raise ValueError("Error message")
   import sys
   sys.exit(0)
   
   # CORRECT:
   raise ValueError("Error message")
   ```

2. **llm_service.py Line 308**: String operation on list
   ```python
   # WRONG (crashes with AttributeError):
   output[0] = output.split("Instruct:")[0]
   
   # CORRECT:
   output[0] = output[0].split("Instruct:")[0]
   ```

#### Areas Needing Improvement (Low Priority)

- **Queue Operations**: Add timeout to prevent blocking
  ```python
  # Instead of:
  data = queue.get()
  
  # Use:
  try:
      data = queue.get(timeout=1.0)
  except queue.Empty:
      continue
  ```

- **WebSocket Error Handling**: Be specific with exceptions
  ```python
  # Instead of:
  except Exception as e:
  
  # Use:
  except (ConnectionClosed, ConnectionClosedError) as e:
      logging.warning(f"WebSocket closed: {e}")
  ```

- **Hardcoded Paths**: Use environment variables
  ```python
  # Instead of:
  default="/root/TensorRT-LLM/examples/whisper/whisper_small_en"
  
  # Use:
  default=os.environ.get('WHISPER_PATH', '/root/TensorRT-LLM/...')
  ```

---

### File Structure & Purpose

```
WhisperFusion/
├── docker/
│   ├── Dockerfile                    # Multi-stage build (base → devel → release)
│   ├── scripts/
│   │   ├── setup-whisperfusion.sh   # CRITICAL: Package installation order
│   │   ├── build-whisper.sh         # Build Whisper TensorRT engine
│   │   ├── build-phi.sh             # Build Phi TensorRT engine
│   │   └── run-whisperfusion.sh     # Runtime entrypoint
│   └── scratch-space/               # Build artifacts and models
├── main.py                          # Multiprocess orchestrator
├── llm_service.py                   # TensorRT-LLM inference
├── tts_service.py                   # WhisperSpeech TTS
├── requirements.txt                 # Python dependencies (NOTE: faster-whisper excluded)
├── docker-compose.yml               # Service orchestration
└── AI_LOG.md                        # Comprehensive fix history
```

---

### Docker Build Process

#### Standard Build Command
```bash
docker compose build --no-cache --progress=plain
```

**Flags Explained:**
- `--no-cache`: Essential! Forces rebuild with new changes
- `--progress=plain`: Shows detailed output for debugging

#### Build Stages Timeline
1. **Stage 1: base** (~5 min)
   - Pull CUDA base image (1.4 GB)
   - Install system packages
   - Install uv package manager

2. **Stage 2: devel** (~2 min)
   - Install CUDA Python bindings
   - Install TensorRT-LLM 0.10.0
   - Clone TensorRT examples

3. **Stage 3: release** (~10-15 min)
   - Run setup-whisperfusion.sh
   - Install torch (specific version)
   - Install PyAV with prebuilt wheels
   - Install all Python dependencies
   - Download models from HuggingFace (~2 GB)
   - Verify all imports

**Total Build Time:** ~20-25 minutes (first build)

---

### Verification & Testing

#### Post-Build Verification
```bash
# 1. Check uv is accessible
docker run --rm whisperfusion which uv
# Expected: /root/.local/bin/uv

# 2. Verify package versions
docker run --rm whisperfusion python3 -c "
import av, torch, faster_whisper, tensorrt_llm
print(f'av: {av.__version__}')           # Should be 12.x.x+
print(f'torch: {torch.__version__}')     # Should be 2.2.x or 2.3.x
print(f'faster-whisper: {faster_whisper.__version__}')  # 1.x.x or 0.9.0
print('✅ All packages verified')
"

# 3. Test critical imports
docker run --rm whisperfusion python3 -c "
import webdataset, whisperspeech, cuda
print('✅ All critical imports successful')
"

# 4. Check Python syntax (if modifying code)
python3 -m py_compile main.py
python3 -m py_compile llm_service.py
python3 -m py_compile tts_service.py
```

#### Runtime Testing
```bash
# 1. Check logs for startup errors
docker compose up

# 2. Expected startup sequence:
# - "Loaded LLM TensorRT Engine"
# - "Warming up torch compile model" (3 iterations)
# - "Warmed up Whisper Speech"
# - WebSocket servers on ports 6006, 8888

# 3. Test WebSocket connectivity
# - Connect to ws://localhost:8888 for TTS
# - Connect to ws://localhost:6006 for transcription
```

---

### Environment Variables

```yaml
# Key environment variables in docker-compose.yml
VERBOSE: "false"              # Enable debug logging
MODEL: "phi-2"                # LLM model (phi-2, Phi-3-mini-4k-instruct)
CUDA_ARCH: ""                 # CUDA architecture for compilation
```

#### Model Options
- `phi-2`: Smaller, faster, uses Q&A format
- `Phi-3-mini-4k-instruct`: Larger, more capable, uses ChatML format
- `mistral`: Alternative LLM (requires additional setup)

---

### Debugging Guidelines

#### Build Failures

1. **First: Check for merge conflicts**
   ```bash
   grep -r "<<<<<<" docker/
   grep -r "=======" docker/
   grep -r ">>>>>>>" docker/
   ```

2. **Check installation order in setup-whisperfusion.sh**
   - Verify torch installed first
   - Verify av installed before faster-whisper
   - Check uv path is correct

3. **Verify file paths in Dockerfile**
   - uv should reference `/root/.local/bin/uv`
   - COPY paths should be relative to docker/ directory

4. **Check for package version conflicts**
   ```bash
   # Inside container:
   uv pip list | grep -E "(torch|av|tensorrt)"
   ```

#### Runtime Failures

1. **Check queue sizes** (can indicate blocking)
   ```python
   logging.info(f"Queue size: {transcription_queue.qsize()}")
   ```

2. **Verify GPU availability**
   ```bash
   docker run --rm --gpus all whisperfusion nvidia-smi
   ```

3. **Check model paths**
   ```bash
   docker run --rm whisperfusion ls -la /root/scratch-space/models/
   ```

4. **Verify WebSocket connectivity**
   ```bash
   # Use browser console or wscat
   wscat -c ws://localhost:8888
   ```

---

### Making Changes Safely

#### Before Modifying Code

1. **Read AI_LOG.md** - Understand previous fixes
2. **Read CODE_QUALITY_REVIEW.md** - Know the issues
3. **Check CODE_REVIEW_SUMMARY.md** - See critical areas

#### When Modifying Python Code

**High-Risk Areas (Change Carefully):**
- Queue operations (can cause deadlocks)
- String operations on lists (common bug pattern)
- Exception handling (don't catch everything)
- Installation order in setup-whisperfusion.sh

**Safe to Modify:**
- Logging statements
- Comments and documentation
- Port numbers (update docker-compose.yml too)
- Timeout values
- Model paths (if using environment variables)

#### After Making Changes

1. **Syntax check**
   ```bash
   python3 -m py_compile <file>.py
   ```

2. **Import check**
   ```bash
   python3 -c "import <module>"
   ```

3. **Rebuild with --no-cache**
   ```bash
   docker compose build --no-cache
   ```

4. **Update AI_LOG.md** with changes

---

### Version Compatibility Matrix

| Package | Version | Constraint | Reason |
|---------|---------|------------|--------|
| **torch** | 2.2.x - 2.3.x | <2.4.0 | tensorrt_llm 0.10.0 requirement |
| **av (PyAV)** | ≥12.0.0 | Must use prebuilt wheels | Cython 3.x compatibility |
| **faster-whisper** | ≥1.0.0 or 0.9.0 | Install last with --no-deps | Prevents av downgrade |
| **tensorrt_llm** | 0.10.0 | Exact version | TensorRT engine compatibility |
| **cuda-python** | ~12.4.0 | Match CUDA version | CUDA 12.4.0 runtime |
| **Python** | 3.10 | System Python | Ubuntu 22.04 default |
| **CUDA** | 12.4.0 | Base image | GPU compute |

**⚠️ Changing any of these versions requires thorough testing!**

---

### Common Patterns & Best Practices

#### Pattern: Multiprocess Communication
```python
# Always use Queue with timeout
try:
    data = queue.get(timeout=1.0)
except queue.Empty:
    continue

# Check queue size before blocking operations
if queue.qsize() > 0:
    continue  # Skip old data
```

#### Pattern: Error Handling
```python
# Be specific with exceptions
try:
    operation()
except SpecificError as e:
    logging.error(f"Operation failed: {e}")
    # Handle or re-raise
except AnotherError as e:
    logging.warning(f"Non-critical error: {e}")
    # Continue
# Don't catch Exception unless absolutely necessary
```

#### Pattern: Resource Cleanup
```python
# WebSocket cleanup
try:
    websocket.close()
except:
    pass  # Already closed

# Process cleanup
process.join(timeout=5.0)
if process.is_alive():
    process.terminate()
```

#### Anti-Pattern: Avoid These
```python
# ❌ DON'T: Unreachable code after raise
raise ValueError("Error")
sys.exit(0)  # Never executes!

# ❌ DON'T: Operate on wrong type
list_var.split()  # Lists don't have split()!

# ❌ DON'T: Catch everything
except Exception:  # Too broad!

# ❌ DON'T: Block forever
queue.get()  # No timeout!

# ❌ DON'T: Rely on qsize() for logic
if queue.qsize() == 0:  # Unreliable in multiprocessing!
```

---

### Emergency Troubleshooting Checklist

When everything breaks, check these in order:

1. ✅ **Merge conflicts?** Search for `<<<<<<<`
2. ✅ **Correct PATH for uv?** Should be `/root/.local/bin`
3. ✅ **Installation order correct?** torch → av → requirements → faster-whisper
4. ✅ **Package versions?** torch<2.4, av≥12.0
5. ✅ **Syntax errors?** Run `python3 -m py_compile`
6. ✅ **Import errors?** Test each module individually
7. ✅ **Build from scratch?** Use `--no-cache`
8. ✅ **GPU available?** Check `nvidia-smi`
9. ✅ **Ports available?** Check 6006, 8888, 8000
10. ✅ **Disk space?** Docker images + models = ~10 GB

---

### Documentation Files Reference

| File | Purpose | When to Read |
|------|---------|--------------|
| **AI_LOG.md** | Complete fix history | Before making ANY changes |
| **CODE_QUALITY_REVIEW.md** | All known issues | Before modifying Python code |
| **CODE_REVIEW_SUMMARY.md** | Executive summary | Quick overview of issues |
| **BUILD_FIX_COMPLETE.md** | Build process details | When build fails |
| **QUICK_START.md** | How to build | First time building |
| **CLAUDE.md** (this file) | AI assistant guide | Always! |

---

### Key Principles for AI Assistants

1. **Always read AI_LOG.md first** - Don't repeat past mistakes
2. **Never change installation order** - It's critical and well-tested
3. **Use --no-cache when rebuilding** - Otherwise changes won't apply
4. **Check for merge conflicts** - Common source of syntax errors
5. **Test changes in isolation** - Don't change multiple things at once
6. **Update documentation** - Keep AI_LOG.md current
7. **Verify before declaring success** - Run the verification commands
8. **Explain the "why"** - Don't just fix, explain the reasoning

---

### Success Criteria

A successful WhisperFusion deployment should:

✅ Build completes without errors (~20-25 minutes)  
✅ All packages at correct versions (torch 2.2-2.3, av 12.x)  
✅ All imports work (no AttributeError, ImportError)  
✅ Models downloaded successfully (~2 GB)  
✅ Services start and listen on correct ports  
✅ WebSocket connections accepted  
✅ Speech → Text → LLM → Speech pipeline works end-to-end  
✅ No crashes with phi-2 model  
✅ GPU utilized correctly (check nvidia-smi)  

---

## Quick Reference Commands

```bash
# Build from scratch
docker compose build --no-cache --progress=plain

# Check versions
docker run --rm whisperfusion python3 -c "import av, torch; print(f'{av.__version__}, {torch.__version__}')"

# Run the application
docker compose up

# Check logs
docker compose logs -f whisperfusion

# Stop everything
docker compose down

# Clean everything (nuclear option)
docker compose down -v
docker system prune -a --volumes
```

---

## Contact & Updates

**Last Comprehensive Review:** November 9, 2025  
**Known Issues:** 13 minor (see CODE_QUALITY_REVIEW.md)  
**Critical Issues:** 0 (all fixed)  
**Build Status:** ✅ Working  

When in doubt, refer to AI_LOG.md for the complete history of fixes and solutions.

---

**Remember:** This project has many moving parts and specific version requirements. When troubleshooting, always start with the most recent AI_LOG.md entry and work backwards. The installation order in setup-whisperfusion.sh is the result of extensive trial and error - respect it!
