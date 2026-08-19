#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERVER_BIN="${PROJECT_DIR}/llama.cpp/build/bin/llama-server"
MODEL_DIR="${PROJECT_DIR}/models/Qwen3.8-27B-GGUF"
MODEL_FILE="${QWEN_MODEL_FILE:-${MODEL_DIR}/Qwen3.8-27B-UD-Q6_K_L.gguf}"
MMPROJ_FILE="${QWEN_MMPROJ_FILE:-${MODEL_DIR}/mmproj-F16.gguf}"
MTP_FILE="${QWEN_MTP_FILE:-${MODEL_DIR}/MTP/mtp-Qwen3.8-27B-Q4_0.gguf}"
API_HOST="${QWEN_API_HOST:-127.0.0.1}"
API_PORT="${QWEN_API_PORT:-30000}"
CTX_SIZE="${QWEN_CTX_SIZE:-65536}"

for path in "${SERVER_BIN}" "${MODEL_FILE}" "${MMPROJ_FILE}" "${MTP_FILE}"; do
  if [[ ! -e "${path}" ]]; then
    echo "Missing required file: ${path}" >&2
    echo "Run ./scripts/build.sh and ./scripts/download-model.sh first." >&2
    exit 1
  fi
done

# DGX Spark uses unified CPU/GPU memory. This prevents CUDA from reserving a
# host-memory safety margin that is unnecessary for this dedicated workload.
export CUDA_DEVICE_MIN_SYS_MEM_MB="${CUDA_DEVICE_MIN_SYS_MEM_MB:-0}"

exec "${SERVER_BIN}" \
  --model "${MODEL_FILE}" \
  --mmproj "${MMPROJ_FILE}" \
  --model-draft "${MTP_FILE}" \
  --alias Qwen/Qwen3.8-27B \
  --host "${API_HOST}" \
  --port "${API_PORT}" \
  --cors-origins localhost \
  --no-cors-credentials \
  --ctx-size "${CTX_SIZE}" \
  --parallel 1 \
  --n-gpu-layers all \
  --n-gpu-layers-draft all \
  --flash-attn on \
  --cache-type-k q8_0 \
  --cache-type-v q8_0 \
  --spec-type draft-mtp \
  --spec-draft-n-max 2 \
  --jinja \
  --reasoning-preserve \
  --metrics
