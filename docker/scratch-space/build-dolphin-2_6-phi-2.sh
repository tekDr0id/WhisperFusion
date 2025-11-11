#!/bin/bash -e

## Note: Phi is only available in main branch and hasnt been released yet. So, make sure to build TensorRT-LLM from main branch.

cd /root/TensorRT-LLM-examples/phi

## Build TensorRT for [Dolphin Phi Finetuned](https://huggingface.co/cognitivecomputations/dolphin-2_6-phi-2) ChatML format with `fp16`

# Apply CUDA fix (same as in build-whisper.sh, build-phi.sh, and build-mistral.sh)
echo "🔍 Applying CUDA fix for cudart import..."
echo "Installing cuda-python==12.4.0..."
uv pip install --system --force-reinstall "cuda-python==12.4.0" > /dev/null 2>&1

# Test CUDA import
if python3 -c "from cuda import cudart; print('✓ cudart import successful')" 2>/dev/null; then
    echo "✅ CUDA fix applied successfully!"
    echo "CUDA_FIX_APPLIED: cuda-python==12.4.0 in build-dolphin.sh" >> /root/scratch-space/cuda_solution.txt
else
    echo "⚠️  CUDA fix failed, attempting to continue..."
fi

# Apply MPI fix (same as in build-whisper.sh, build-phi.sh, and build-mistral.sh)
echo "🔧 Removing MPI dependencies to avoid container runtime issues..."
echo "Reason: Open MPI opal_shmem_base_select fails in Docker container environment"

# Uninstall mpi4py and OpenMPI packages that cause the initialization failure
uv pip uninstall --system -y mpi4py 2>/dev/null || true
apt-get remove -y openmpi-bin libopenmpi3 libopenmpi-dev 2>/dev/null || true

echo "✅ MPI dependencies removed - proceeding with single-process TensorRT build..."

echo "Download Phi2 Huggingface models..."

git lfs install
phi_path=$(huggingface-cli download --repo-type model cognitivecomputations/dolphin-2_6-phi-2)
name=dolphin-2_6-phi-2
echo "Building Phi2 TensorRT engine. This will take some time. Please wait ..."
python3 build.py --dtype=float16                    \
                 --log_level=error                  \
                 --use_gpt_attention_plugin float16 \
                 --use_gemm_plugin float16          \
                 --max_batch_size=1                 \
                 --max_input_len=1024               \
                 --max_output_len=1024              \
                 --output_dir=$name                 \
                 --model_dir="$phi_path" >&1 | tee build.log

dest=/root/scratch-space/models
mkdir -p "$dest/$name/tokenizer"
cp -r "$name" "$dest"
(cd "$phi_path" && cp config.json tokenizer_config.json vocab.json merges.txt "$dest/$name/tokenizer")
cp -r "$phi_path" "$dest/phi-orig-model"
echo "Done building Phi2 TensorRT Engine. Starting the web server ..."
