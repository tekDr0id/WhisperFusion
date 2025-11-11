#!/bin/bash -e

cd /root/TensorRT-LLM-examples/llama

## Build TensorRT for Mistral with `fp16`

# Apply CUDA fix (same as in build-whisper.sh and build-phi.sh)
echo "🔍 Applying CUDA fix for cudart import..."
echo "Installing cuda-python==12.4.0..."
uv pip install --system --force-reinstall "cuda-python==12.4.0" > /dev/null 2>&1

# Test CUDA import
if python3 -c "from cuda import cudart; print('✓ cudart import successful')" 2>/dev/null; then
    echo "✅ CUDA fix applied successfully!"
    echo "CUDA_FIX_APPLIED: cuda-python==12.4.0 in build-mistral.sh" >> /root/scratch-space/cuda_solution.txt
else
    echo "⚠️  CUDA fix failed, attempting to continue..."
fi

# Apply MPI fix (same as in build-whisper.sh and build-phi.sh)
echo "🔧 Removing MPI dependencies to avoid container runtime issues..."
echo "Reason: Open MPI opal_shmem_base_select fails in Docker container environment"

# Uninstall mpi4py and OpenMPI packages that cause the initialization failure
uv pip uninstall --system -y mpi4py 2>/dev/null || true
apt-get remove -y openmpi-bin libopenmpi3 libopenmpi-dev 2>/dev/null || true

echo "✅ MPI dependencies removed - proceeding with single-process TensorRT build..."

python build.py --model_dir teknium/OpenHermes-2.5-Mistral-7B \
                --dtype float16 \
                --remove_input_padding \
                --use_gpt_attention_plugin float16 \
                --enable_context_fmha \
                --use_gemm_plugin float16 \
                --output_dir ./tmp/mistral/7B/trt_engines/fp16/1-gpu/ \
                --max_input_len 5000 \
                --max_batch_size 1

mkdir -p /root/scratch-space/models
cp -r tmp/mistral/7B/trt_engines/fp16/1-gpu /root/scratch-space/models/mistral
