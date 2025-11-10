# Use official TensorRT-LLM container as base
ARG BASE_IMAGE=nvcr.io/nvidia/tensorrt-llm
ARG BASE_TAG=0.10.0-trtllm-devel

FROM ${BASE_IMAGE}:${BASE_TAG} as base
ARG CUDA_ARCH
ENV CUDA_ARCH=${CUDA_ARCH}

# Install additional packages needed for WhisperFusion
RUN apt-get update && apt-get install -y \
    ffmpeg portaudio19-dev libavformat-dev libavcodec-dev libavdevice-dev \
    libavutil-dev libavfilter-dev libswscale-dev libswresample-dev pkg-config \
    openmpi-bin libopenmpi-dev wget xz-utils curl && \
    rm -rf /var/lib/apt/lists/*

# Install uv - fast Python package installer
RUN curl -LsSf https://astral.sh/uv/install.sh | sh
# Add uv to PATH for all subsequent stages
ENV PATH="/root/.local/bin:$PATH"

FROM base AS devel
WORKDIR /root/
# TensorRT-LLM and CUDA are already properly configured in the NGC container
# Just install additional required packages for WhisperFusion
RUN /root/.local/bin/uv pip install --system "nvidia-ml-py>=12.535.0,<13"

# Clone TensorRT-LLM examples (they should already exist, but ensure we have v0.10.0)
RUN if [ ! -d "/root/TensorRT-LLM-examples" ]; then \
        git clone -b v0.10.0 --depth 1 https://github.com/NVIDIA/TensorRT-LLM.git && \
        mv TensorRT-LLM/examples ./TensorRT-LLM-examples && \
        rm -rf TensorRT-LLM; \
    fi

FROM devel AS release
WORKDIR /root/
COPY scripts/setup-whisperfusion.sh /root/
RUN ./setup-whisperfusion.sh && \
    /root/.local/bin/uv pip uninstall --system pynvml && \
    /root/.local/bin/uv pip install --system "nvidia-ml-py>=12.535.0,<13"
