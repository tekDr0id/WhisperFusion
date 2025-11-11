# Use PyTorch base with CUDA 12.4 that matches TensorRT-LLM 0.10.0 requirements
ARG BASE_IMAGE=nvcr.io/nvidia/pytorch
ARG BASE_TAG=24.03-py3

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
# Install TensorRT-LLM 0.10.0 and required packages using the same base as NGC containers
RUN /root/.local/bin/uv pip install --system "nvidia-ml-py>=12.535.0,<13" && \
    /root/.local/bin/uv pip install --system -U tensorrt_llm==0.10.0 --extra-index-url https://pypi.nvidia.com

# Clone TensorRT-LLM examples
RUN git clone -b v0.10.0 --depth 1 https://github.com/NVIDIA/TensorRT-LLM.git && \
    mv TensorRT-LLM/examples ./TensorRT-LLM-examples && \
    rm -rf TensorRT-LLM

FROM devel AS release
WORKDIR /root/
COPY scripts/setup-whisperfusion.sh /root/
RUN ./setup-whisperfusion.sh && \
    /root/.local/bin/uv pip uninstall --system pynvml && \
    /root/.local/bin/uv pip install --system "nvidia-ml-py>=12.535.0,<13"
