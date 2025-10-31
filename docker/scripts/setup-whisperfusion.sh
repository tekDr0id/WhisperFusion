#!/bin/bash -e

## Clone this repo and install requirements
[ -d "WhisperFusion" ] || git clone https://github.com/Collabora/WhisperFusion.git

cd WhisperFusion
apt update
apt install ffmpeg portaudio19-dev libavformat-dev libavcodec-dev libavdevice-dev libavutil-dev libavfilter-dev libswscale-dev libswresample-dev pkg-config -y

## Upgrade pip, setuptools, and wheel to ensure we can use prebuilt wheels
pip install --upgrade pip setuptools wheel

## Pin torch to version compatible with tensorrt_llm 0.10.0 (requires torch<=2.3.0a,>=2.2.0a)
## This prevents dependencies from upgrading torch to incompatible versions
pip install 'torch>=2.2.0,<2.4.0' --index-url https://download.pytorch.org/whl/cu124

## Install PyAV with a version that has prebuilt wheels (12.0.0+)
## This must be done before faster-whisper to prevent av 10.x from being installed
pip install --no-cache-dir --only-binary=:all: 'av>=12.0.0'

## Install all dependencies except faster-whisper
grep -v "faster-whisper" requirements.txt > /tmp/requirements-temp.txt
pip install -r /tmp/requirements-temp.txt

## Install newer faster-whisper that supports av 12.x (version 1.0.0+)
## If that fails, install 0.9.0 without dependencies since we have av already
pip install 'faster-whisper>=1.0.0' || pip install --no-deps faster-whisper==0.9.0

## Download models using huggingface-cli (already installed via transformers dependency)
huggingface-cli download collabora/whisperspeech t2s-small-en+pl.model s2a-q4-tiny-en+pl.model
huggingface-cli download charactr/vocos-encodec-24khz

mkdir -p /root/.cache/torch/hub/checkpoints/
curl -L -o /root/.cache/torch/hub/checkpoints/encodec_24khz-d7cc33bc.th https://dl.fbaipublicfiles.com/encodec/v0/encodec_24khz-d7cc33bc.th
mkdir -p /root/.cache/whisper-live/
curl -L -o /root/.cache/whisper-live/silero_vad.onnx https://github.com/snakers4/silero-vad/raw/v4.0/files/silero_vad.onnx

python3 -c 'from transformers.utils.hub import move_cache; move_cache()'
