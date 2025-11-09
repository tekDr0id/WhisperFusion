#!/bin/bash -e

## Change working dir to the [whisper example dir](https://github.com/NVIDIA/TensorRT-LLM/tree/main/examples/whisper) in TensorRT-LLM.
cd /root/TensorRT-LLM-examples/whisper

# the small.en model weights
if [ ! -f assets/small.en.pt ]; then
    echo "Downloading PyTorch weights for small.en model"
    wget --directory-prefix=assets https://openaipublic.azureedge.net/main/whisper/models/f953ad0fd29cacd07d5a9eda5624af0f6bcf2258be67c92b79389873d91e0872/small.en.pt > /dev/null 2>&1
else
    echo "PyTorch weights for small.en model already exist, skipping download."
fi

echo "Building Whisper TensorRT Engine..."
uv pip install --system -r requirements.txt > /dev/null 2>&1

<<<<<<< Updated upstream
=======
# Fix: Ensure torch and torchaudio versions remain compatible after requirements install
# The whisper requirements.txt might change versions, so we force them back
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

>>>>>>> Stashed changes
python3 build.py --output_dir whisper_small_en --use_gpt_attention_plugin --use_gemm_plugin  --use_bert_attention_plugin --enable_context_fmha --model_name small.en

mkdir -p /root/scratch-space/models
cp -r whisper_small_en /root/scratch-space/models
rm -rf whisper_small_en
