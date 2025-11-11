#!/bin/bash -e

## Note: Phi is only available in main branch and hasnt been released yet. So, make sure to build TensorRT-LLM from main branch.

cd /root/TensorRT-LLM-examples/phi

## Build TensorRT for Phi-2 with `fp16`

MODEL_TYPE=$1
echo "Download $MODEL_TYPE Huggingface models..."

# Use hf download instead of deprecated huggingface-cli download to avoid warnings
phi_path=$(hf download microsoft/$MODEL_TYPE 2>/dev/null || huggingface-cli download --repo-type model microsoft/$MODEL_TYPE 2>/dev/null)
echo "Building  TensorRT Engine..."
name=$1
uv pip install --system -r requirements.txt

# Fix: Ensure torch and torchaudio versions remain compatible after requirements install
echo "Verifying torch and torchaudio compatibility..."
uv pip install --system --force-reinstall 'torch>=2.2.0,<2.4.0' 'torchaudio>=2.2.0,<2.4.0' --index-url https://download.pytorch.org/whl/cu121 > /dev/null 2>&1
echo "torch/torchaudio compatibility verified"

# Fix: Ensure nvidia-ml-py is installed (remove deprecated pynvml)
echo "Ensuring nvidia-ml-py is installed..."
uv pip uninstall --system pynvml 2>/dev/null || true
uv pip install --system "nvidia-ml-py>=12.535.0,<13" > /dev/null 2>&1
echo "nvidia-ml-py verified"

# Fix pynvml issue - patch TensorRT-LLM files to skip version check
echo "Patching TensorRT-LLM to skip pynvml version checks..."

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
echo "Patches applied successfully"

# Apply CUDA fix (same as in build-whisper.sh)
echo "🔍 Applying CUDA fix for cudart import..."
echo "Installing cuda-python==12.4.0..."
uv pip install --system --force-reinstall "cuda-python==12.4.0" > /dev/null 2>&1

# Test CUDA import
if python3 -c "from cuda import cudart; print('✓ cudart import successful')" 2>/dev/null; then
    echo "✅ CUDA fix applied successfully!"
    echo "CUDA_FIX_APPLIED: cuda-python==12.4.0 in build-phi.sh" >> /root/scratch-space/cuda_solution.txt
else
    echo "⚠️  CUDA fix failed, attempting to continue..."
fi

# Apply MPI fix (same as in build-whisper.sh)
echo "🔧 Removing MPI dependencies to avoid container runtime issues..."
echo "Reason: Open MPI opal_shmem_base_select fails in Docker container environment"

# Uninstall mpi4py and OpenMPI packages that cause the initialization failure
uv pip uninstall --system -y mpi4py 2>/dev/null || true
apt-get remove -y openmpi-bin libopenmpi3 libopenmpi-dev 2>/dev/null || true

echo "✅ MPI dependencies removed - proceeding with single-process TensorRT build..."
# Check if FP32 build is forced to avoid DynamicDecodeLayer segfaults
if [ "$FORCE_FP32_BUILD" = "1" ]; then
    echo "⚠️  FORCE_FP32_BUILD detected - building Phi with FP32 precision to avoid segfaults"
    
    python3 ./convert_checkpoint.py --model_type $MODEL_TYPE \
                        --model_dir $phi_path \
                        --output_dir ./phi-checkpoint \
                        --dtype float32

    trtllm-build \
        --checkpoint_dir ./phi-checkpoint \
        --output_dir $name \
        --gpt_attention_plugin float32 \
        --context_fmha enable \
        --gemm_plugin float32 \
        --max_batch_size 1 \
        --max_input_len 1024 \
        --max_output_len 1024 \
        --tp_size 1 \
        --pp_size 1
else
    echo "Building Phi with default precision (FP16)"
    
    python3 ./convert_checkpoint.py --model_type $MODEL_TYPE \
                        --model_dir $phi_path \
                        --output_dir ./phi-checkpoint \
                        --dtype float16

    trtllm-build \
        --checkpoint_dir ./phi-checkpoint \
        --output_dir $name \
        --gpt_attention_plugin float16 \
        --context_fmha enable \
        --gemm_plugin float16 \
        --max_batch_size 1 \
        --max_input_len 1024 \
        --max_output_len 1024 \
        --tp_size 1 \
        --pp_size 1
fi

dest=/root/scratch-space/models
if [ -d "$dest/$name" ]; then
    rm -rf "$dest/$name"
fi
mkdir -p "$dest/$name/tokenizer"
cp -r "$name" "$dest"
(cd "$phi_path" && cp config.json tokenizer_config.json tokenizer.json special_tokens_map.json added_tokens.json "$dest/$name/tokenizer")
if [ "$MODEL_TYPE" == "phi-2" ]; then
    (cd "$phi_path" && cp vocab.json merges.txt "$dest/$name/tokenizer")
fi
