#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LLAMA_DIR="${PROJECT_DIR}/llama.cpp"
JOBS="${QWEN_BUILD_JOBS:-$(nproc)}"

for tool in cmake git nvcc gcc g++; do
  if ! command -v "${tool}" >/dev/null 2>&1; then
    echo "Missing required command: ${tool}" >&2
    exit 1
  fi
done

if [[ ! -d "${LLAMA_DIR}/.git" ]]; then
  git clone --depth 1 https://github.com/ggml-org/llama.cpp.git "${LLAMA_DIR}"
fi

cmake -S "${LLAMA_DIR}" -B "${LLAMA_DIR}/build" \
  -DGGML_NATIVE=ON \
  -DGGML_CUDA=ON \
  -DGGML_CURL=OFF \
  -DGGML_RPC=ON \
  -DLLAMA_BUILD_UI=OFF \
  -DLLAMA_USE_PREBUILT_UI=OFF \
  -DCMAKE_CUDA_ARCHITECTURES=121a-real \
  -DCMAKE_BUILD_TYPE=Release

cmake --build "${LLAMA_DIR}/build" \
  --config Release \
  --target llama-server \
  -j "${JOBS}"

"${LLAMA_DIR}/build/bin/llama-server" --version
