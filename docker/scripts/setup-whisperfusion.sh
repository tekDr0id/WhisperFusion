#!/bin/bash -e

## Clone this repo and install requirements
[ -d "WhisperFusion" ] || git clone https://github.com/Collabora/WhisperFusion.git

cd WhisperFusion
apt update
apt install ffmpeg portaudio19-dev libavformat-dev libavcodec-dev libavdevice-dev libavutil-dev libavfilter-dev libswscale-dev libswresample-dev pkg-config -y

## Upgrade pip, setuptools, and wheel using uv
echo "Upgrading pip, setuptools, and wheel..."
uv pip install --system --upgrade pip setuptools wheel

## CRITICAL FIX #1: Pin torch to version compatible with tensorrt_llm 0.10.0
## tensorrt_llm 0.10.0 requires torch>=2.2.0,<2.4.0
## This prevents dependencies from upgrading torch to incompatible versions (like 2.9.0)
echo "Installing torch 2.2.x-2.3.x (compatible with tensorrt_llm)..."
uv pip install --system 'torch>=2.2.0,<2.4.0' --index-url https://download.pytorch.org/whl/cu124

## CRITICAL FIX #2: Install PyAV with prebuilt wheels (v12.0.0+)
## This MUST come before faster-whisper to prevent av 10.x from being installed
## Using --only-binary=:all: forces binary-only installation and bypasses Cython compilation
## PyAV 12.0.0+ provides prebuilt wheels for Python 3.10, completely avoiding compilation errors
echo "Installing PyAV 12.0.0+ with prebuilt wheels only..."
uv pip install --system --only-binary=:all: 'av>=12.0.0'

## Verify PyAV installed successfully
python3 -c "import av; print(f'✓ PyAV {av.__version__} installed successfully')" || \
    { echo "ERROR: PyAV failed to install"; exit 1; }

## Now install all application dependencies from requirements.txt (except faster-whisper)
## We exclude faster-whisper because it forces av==10.* which conflicts with our av 12.x
echo "Installing application dependencies from requirements.txt..."
grep -v "faster-whisper" requirements.txt > /tmp/requirements-temp.txt
uv pip install --system -r /tmp/requirements-temp.txt

## CRITICAL FIX #3: Install faster-whisper with preference for newer version
## Try newer version (1.0.0+) that supports av 12.x first
## Fall back to 0.9.0 with --no-deps if newer version unavailable
echo "Installing faster-whisper..."
uv pip install --system 'faster-whisper>=1.0.0' || uv pip install --system --no-deps faster-whisper==0.9.0

## Verify critical dependencies are installed
echo "Verifying critical dependencies..."
python3 -c "import whisperspeech; print('✓ whisperspeech module verified')" || \
    { echo "ERROR: whisperspeech failed to import"; exit 1; }
python3 -c "import torch; print(f'✓ torch {torch.__version__} verified')" || \
    { echo "ERROR: torch failed to import"; exit 1; }
python3 -c "import av; print(f'✓ av {av.__version__} verified')" || \
    { echo "ERROR: av failed to import"; exit 1; }
python3 -c "import faster_whisper; print(f'✓ faster-whisper {faster_whisper.__version__} verified')" || \
    { echo "ERROR: faster-whisper failed to import"; exit 1; }

## Clear uv cache to save space
echo "Cleaning uv cache..."
uv cache clean

## Download models using huggingface-cli or hf download command
echo "Downloading models from Hugging Face..."
# Try new hf command first, fall back to huggingface-cli
(hf download collabora/whisperspeech t2s-small-en+pl.model s2a-q4-tiny-en+pl.model 2>/dev/null) || \
    (huggingface-cli download collabora/whisperspeech t2s-small-en+pl.model s2a-q4-tiny-en+pl.model)

(hf download charactr/vocos-encodec-24khz 2>/dev/null) || \
    (huggingface-cli download charactr/vocos-encodec-24khz)

## Download additional model files
echo "Downloading additional model files..."
mkdir -p /root/.cache/torch/hub/checkpoints/
curl -L -o /root/.cache/torch/hub/checkpoints/encodec_24khz-d7cc33bc.th https://dl.fbaipublicfiles.com/encodec/v0/encodec_24khz-d7cc33bc.th

mkdir -p /root/.cache/whisper-live/
curl -L -o /root/.cache/whisper-live/silero_vad.onnx https://github.com/snakers4/silero-vad/raw/v4.0/files/silero_vad.onnx

## Organize cached files
echo "Organizing cached files..."
python3 -c 'from transformers.utils.hub import move_cache; move_cache()'

# Install webdataset for WhisperSpeech runtime (after TensorRT builds complete)
echo "Installing webdataset for WhisperSpeech runtime..."
uv pip install --system webdataset

echo "✅ WhisperFusion setup completed successfully!"
echo ""
echo "Installed package versions:"
python3 -c "import av, torch, faster_whisper; print(f'  av: {av.__version__}'); print(f'  torch: {torch.__version__}'); print(f'  faster-whisper: {faster_whisper.__version__}')"
