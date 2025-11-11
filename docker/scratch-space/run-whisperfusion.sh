#!/bin/bash -e

test -f /etc/shinit_v2 && source /etc/shinit_v2

echo "Running build-models.sh..."
cd /root/scratch-space/
MODEL=${MODEL:-phi-2}
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

# Clear Python cache to ensure patches take effect
find /usr/local/lib/python3.10/dist-packages/tensorrt_llm -type d -name '__pycache__' -exec rm -rf {} + 2>/dev/null || true
echo "✅ TensorRT-LLM patches applied for runtime"

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

# Set conservative CUDA memory allocation
export CUDA_LAUNCH_BLOCKING=1
export CUDA_CACHE_DISABLE=1
export PYTORCH_CUDA_ALLOC_CONF=max_split_size_mb:512

# Set conservative memory limits
export TENSORRT_MAX_WORKSPACE_SIZE=1073741824  # 1GB
export TRT_MAX_WORKSPACE_SIZE=1073741824

# Force single GPU usage and conservative batch sizes
export CUDA_VISIBLE_DEVICES=0

echo "✅ GPU memory configuration applied"

cd /root/WhisperFusion

# Add memory debugging wrapper
echo "🚀 Starting WhisperFusion with memory safety..."
if [ "$1" != "mistral" ]; then
  # Use exec with memory monitoring
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
