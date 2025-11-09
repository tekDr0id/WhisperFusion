ARG BASE_IMAGE=nvcr.io/nvidia/cuda
ARG BASE_TAG=12.4.0-runtime-ubuntu22.04

FROM ${BASE_IMAGE}:${BASE_TAG} as base
ARG CUDA_ARCH
ENV CUDA_ARCH=${CUDA_ARCH}

RUN apt-get update && apt-get install -y \
    python3.10 python3-pip openmpi-bin libopenmpi-dev git wget \
    xz-utils curl && \
    rm -rf /var/lib/apt/lists/*

# Install uv - fast Python package installer
RUN curl -LsSf https://astral.sh/uv/install.sh | sh && \
    echo 'export PATH="/root/.cargo/bin:$PATH"' >> /root/.bashrc
ENV PATH="/root/.cargo/bin:$PATH"

FROM base AS devel
WORKDIR /root/
<<<<<<< Updated upstream
RUN pip3 install --no-cache-dir cuda-python~=12.4.0 && \
    pip3 install --no-cache-dir -U tensorrt_llm==0.10.0 --extra-index-url https://pypi.nvidia.com
=======
RUN uv pip install --system cuda-python~=12.4.0 && \
    uv pip install --system "nvidia-ml-py>=12.535.0,<13" && \
    uv pip install --system -U tensorrt_llm==0.10.0 --extra-index-url https://pypi.nvidia.com
>>>>>>> Stashed changes
RUN git clone -b v0.10.0 --depth 1 https://github.com/NVIDIA/TensorRT-LLM.git && \
    mv TensorRT-LLM/examples ./TensorRT-LLM-examples && \
    rm -rf TensorRT-LLM

FROM devel AS release
WORKDIR /root/
COPY scripts/setup-whisperfusion.sh /root/
<<<<<<< Updated upstream
RUN ./setup-whisperfusion.sh
=======
RUN ./setup-whisperfusion.sh && \
    uv pip uninstall --system pynvml && \
    uv pip install --system "nvidia-ml-py>=12.535.0,<13"
>>>>>>> Stashed changes
