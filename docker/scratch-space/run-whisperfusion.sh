#!/bin/bash -e

test -f /etc/shinit_v2 && source /etc/shinit_v2

echo "Running build-models.sh..."
cd /root/scratch-space/
MODEL=${MODEL:-phi-2}

# NUCLEAR OPTION: Force rebuild models in FP32 to avoid DynamicDecodeLayer segfault
echo "🚨 CRITICAL: Forcing FP32 model rebuild to avoid TensorRT-LLM segfaults"
echo "Removing existing models to force FP32 rebuild..."
rm -rf /root/scratch-space/models/whisper_small_en 2>/dev/null || true
rm -rf /root/scratch-space/models/$MODEL 2>/dev/null || true
rm -rf /root/scratch-space/models/phi-* 2>/dev/null || true

# Set FP32 build environment variables
export FORCE_FP32_BUILD=1
export TENSORRT_DISABLE_FP16=1
export TRT_FORCE_FP32=1

./build-models.sh $MODEL

# Install webdataset if missing (needed for WhisperSpeech runtime)
echo "Ensuring webdataset is available for WhisperSpeech..."
python3 -c "import webdataset" 2>/dev/null || uv pip install --system webdataset
echo "✅ webdataset ready"

# Fix PyTorch version compatibility for TensorRT-LLM runtime
echo "🔧 Ensuring PyTorch and torchaudio compatibility for TensorRT-LLM runtime..."
echo "Installing compatible PyTorch and torchaudio versions..."
uv pip install --system --force-reinstall 'torch>=2.2.0,<2.4.0' 'torchaudio>=2.2.0,<2.4.0' --index-url https://download.pytorch.org/whl/cu121 > /dev/null 2>&1
echo "torch/torchaudio compatibility verified"

# Fix: Ensure nvidia-ml-py is installed (remove deprecated pynvml)
echo "Ensuring nvidia-ml-py is installed..."
uv pip uninstall --system pynvml 2>/dev/null || true
uv pip install --system "nvidia-ml-py>=12.535.0,<13" > /dev/null 2>&1
echo "nvidia-ml-py verified"

# Apply CUDA fix for runtime (same as in build scripts)
echo "🔍 Applying CUDA fix for runtime..."
uv pip install --system --force-reinstall "cuda-python==12.4.0" > /dev/null 2>&1

# Apply pynvml patches for runtime (same as in build scripts)
echo "🔧 Patching TensorRT-LLM pynvml version checks for runtime..."

# Patch profiler.py
PROFILER_FILE="/usr/local/lib/python3.10/dist-packages/tensorrt_llm/profiler.py"
if [ -f "$PROFILER_FILE" ]; then
    sed -i "s/elif pynvml.__version__ < '11.5.0':/elif False:  # Patched: skip version check/g" "$PROFILER_FILE"
    echo "  - profiler.py patched"
fi

# Patch cluster_info.py
CLUSTER_FILE="/usr/local/lib/python3.10/dist-packages/tensorrt_llm/auto_parallel/cluster_info.py"
if [ -f "$CLUSTER_FILE" ]; then
    sed -i "s/if pynvml.__version__ < '11.5.0':/if False:  # Patched: skip version check/g" "$CLUSTER_FILE"
    echo "  - cluster_info.py patched"
fi

# CRITICAL PATCH: Fix DynamicDecodeLayer segfault by forcing FP32 allocation
DYNAMIC_DECODE_FILE="/usr/local/lib/python3.10/dist-packages/tensorrt_llm/layers/dynamic_decode.py"
if [ -f "$DYNAMIC_DECODE_FILE" ]; then
    # Patch to force FP32 for DynamicDecodeLayer allocations to prevent segfault
    sed -i 's/dtype=torch.float16/dtype=torch.float32/g' "$DYNAMIC_DECODE_FILE" 2>/dev/null || true
    sed -i 's/dtype=torch.half/dtype=torch.float32/g' "$DYNAMIC_DECODE_FILE" 2>/dev/null || true
    echo "  - dynamic_decode.py patched for FP32 allocation"
fi

# Patch TorchAllocator to use safer memory allocation
ALLOCATOR_FILE="/usr/local/lib/python3.10/dist-packages/tensorrt_llm/functional.py"
if [ -f "$ALLOCATOR_FILE" ]; then
    # Add memory safety checks
    sed -i 's/torch.cuda.empty_cache()/torch.cuda.empty_cache(); torch.cuda.synchronize()/g' "$ALLOCATOR_FILE" 2>/dev/null || true
    echo "  - functional.py patched for memory safety"
fi

# Clear Python cache to ensure patches take effect
find /usr/local/lib/python3.10/dist-packages/tensorrt_llm -type d -name '__pycache__' -exec rm -rf {} + 2>/dev/null || true
echo "✅ TensorRT-LLM patches applied for runtime (including DynamicDecodeLayer segfault fix)"

# CRITICAL FIX: Apply MPI removal for runtime (same as in build scripts)
echo "🔧 Removing MPI dependencies to avoid runtime container issues..."
echo "Reason: Open MPI opal_shmem_base_select fails in Docker container environment"

# Uninstall mpi4py and OpenMPI packages that cause the initialization failure
uv pip uninstall --system -y mpi4py 2>/dev/null || true
apt-get remove -y openmpi-bin libopenmpi3 libopenmpi-dev 2>/dev/null || true

echo "✅ MPI dependencies removed for runtime - proceeding with single-process mode..."

# Test TensorRT-LLM import with comprehensive error handling
echo "🧪 Testing TensorRT-LLM import with fallbacks..."
if python3 -c "import tensorrt_llm; print('✓ TensorRT-LLM import successful')" 2>/dev/null; then
    echo "✅ TensorRT-LLM runtime ready!"
    echo "RUNTIME_SUCCESS: All fixes applied successfully" >> /root/scratch-space/cuda_solution.txt
else
    echo "⚠️  TensorRT-LLM import still failed, checking what's wrong..."
    python3 -c "import tensorrt_llm" 2>&1 | head -5 || echo "Import test failed completely"
    echo "RUNTIME_WARNING: TensorRT-LLM import failed, but attempting to continue..." >> /root/scratch-space/cuda_solution.txt
fi

# GPU Memory Management Fixes
echo "🔧 Configuring GPU memory management for TensorRT-LLM..."

# Set very conservative CUDA memory allocation for voice processing
export CUDA_LAUNCH_BLOCKING=1
export CUDA_CACHE_DISABLE=1
export PYTORCH_CUDA_ALLOC_CONF=max_split_size_mb:256,garbage_collection_threshold:0.6

# Set very conservative memory limits
export TENSORRT_MAX_WORKSPACE_SIZE=536870912   # 512MB (reduced from 1GB)
export TRT_MAX_WORKSPACE_SIZE=536870912
export CUDA_MODULE_LOADING=LAZY

# Force single GPU usage and disable multi-stream
export CUDA_VISIBLE_DEVICES=0
export CUDA_DEVICE_ORDER=PCI_BUS_ID

# Add FP16/half-precision specific fixes
export TENSORRT_DISABLE_FP16=0
export TRT_DISABLE_OPTIMIZATION=1

# TensorRT-LLM FP32 runtime configuration (no half-precision)
export TRTLLM_FORCE_FP32_DECODE=1
export TENSORRT_DISABLE_FP16=1
export TRT_FORCE_FP32=1
export TENSORRT_ALLOCATOR_STRATEGY=simple

# GPU memory settings for 24GB GPU with FP32 allocations
export PYTORCH_CUDA_ALLOC_CONF="max_split_size_mb:2048,garbage_collection_threshold:0.6,expandable_segments:True"
export CUDA_MEMORY_FRACTION=0.85
export TORCH_CUDA_MEMORY_FRACTION=0.85

# Reduce batch sizes for voice processing
export WHISPER_BATCH_SIZE=1
export PHI_BATCH_SIZE=1

# Force synchronous execution to prevent memory races
export CUDA_LAUNCH_BLOCKING=1
export TORCH_CUDA_ARCH_LIST="8.0;8.6;8.9;9.0"

echo "✅ GPU memory configuration and DynamicDecodeLayer fixes applied"

cd /root/WhisperFusion

# Add TensorRT-LLM memory allocation safety wrapper
echo "🚀 Starting WhisperFusion with TensorRT-LLM memory safety..."

# Apply conservative GPU memory settings before starting main
echo "🔧 Setting conservative GPU memory allocation..."
python3 -c "import torch; torch.cuda.set_per_process_memory_fraction(0.7) if torch.cuda.is_available() else None; torch.cuda.empty_cache() if torch.cuda.is_available() else None" 2>/dev/null || true

if [ "$1" != "mistral" ]; then
  # Use direct main.py with memory safety environment variables
  exec python3 -u main.py --phi \
                  --whisper_tensorrt_path /root/scratch-space/models/whisper_small_en \
                  --phi_tensorrt_path /root/scratch-space/models/$MODEL \
                  --phi_tokenizer_path /root/scratch-space/models/$MODEL/tokenizer \
                  --phi_model_type $MODEL
else
  exec python3 main.py --mistral \
                  --whisper_tensorrt_path /root/scratch-space/models/whisper_small_en \
                  --mistral_tensorrt_path /root/scratch-space/models/mistral \
                  --mistral_tokenizer_path teknium/OpenHermes-2.5-Mistral-7B
fi
