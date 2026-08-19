#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERVER_BIN="${PROJECT_DIR}/llama.cpp/build/bin/llama-server"
MODEL_DIR="${PROJECT_DIR}/models/DeepSeek-V4-Flash-0731-GGUF"
MODEL_FILE="${DEEPSEEK_MODEL_FILE:-${MODEL_DIR}/DeepSeek-V4-Flash-0731-Q2_K_S-00001-of-00002.gguf}"
API_HOST="${DEEPSEEK_API_HOST:-127.0.0.1}"
API_PORT="${DEEPSEEK_API_PORT:-30001}"
CTX_SIZE="${DEEPSEEK_CTX_SIZE:-8192}"

for path in "${SERVER_BIN}" "${MODEL_FILE}"; do
  if [[ ! -e "${path}" ]]; then
    echo "Missing required file: ${path}" >&2
    echo "Run ./scripts/build.sh and ./scripts/download-deepseek.sh first." >&2
    exit 1
  fi
done

# V4 Flash is a tight fit in 128 GB. Avoid weight repacking and warmup copies,
# and use the conservative attention paths while current V4 CUDA bugs settle.
export CUDA_DEVICE_MIN_SYS_MEM_MB="${CUDA_DEVICE_MIN_SYS_MEM_MB:-0}"

exec "${SERVER_BIN}" \
  --model "${MODEL_FILE}" \
  --alias deepseek-ai/DeepSeek-V4-Flash-0731 \
  --host "${API_HOST}" \
  --port "${API_PORT}" \
  --cors-origins localhost \
  --no-cors-credentials \
  --ctx-size "${CTX_SIZE}" \
  --parallel 1 \
  --n-gpu-layers all \
  --fit off \
  --no-repack \
  --no-warmup \
  --flash-attn off \
  --cache-type-k f16 \
  --cache-type-v f16 \
  --batch-size 2048 \
  --ubatch-size 512 \
  --temp 1.0 \
  --top-p 1.0 \
  --min-p 0.0 \
  --jinja \
  --reasoning-format deepseek \
  --reasoning-preserve \
  --metrics
