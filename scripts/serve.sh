#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${PROJECT_DIR}/.env"

# shellcheck source=scripts/lib/load-env.sh
source "${PROJECT_DIR}/scripts/lib/load-env.sh"
load_env_defaults "${ENV_FILE}" \
  QWEN_SERVER_BIN \
  QWEN_MODEL_FILE \
  QWEN_MMPROJ_FILE \
  QWEN_MTP_FILE \
  QWEN_API_HOST \
  QWEN_API_PORT \
  QWEN_CTX_SIZE \
  QWEN_BATCH_SIZE \
  QWEN_UBATCH_SIZE \
  QWEN_MTP_DRAFT_N_MAX \
  QWEN_LOAD_MODE \
  QWEN_BACKEND_SAMPLING \
  QWEN_CUDA_GRAPH_OPT

SERVER_BIN="${QWEN_SERVER_BIN:-${PROJECT_DIR}/llama.cpp/build/bin/llama-server}"
MODEL_DIR="${PROJECT_DIR}/models/Qwen3.8-27B-GGUF"
MODEL_FILE="${QWEN_MODEL_FILE:-${MODEL_DIR}/Qwen3.8-27B-UD-Q5_K_M.gguf}"
MMPROJ_FILE="${QWEN_MMPROJ_FILE:-${MODEL_DIR}/mmproj-F16.gguf}"
MTP_FILE="${QWEN_MTP_FILE:-${MODEL_DIR}/MTP/mtp-Qwen3.8-27B-Q4_0.gguf}"
API_HOST="${QWEN_API_HOST:-127.0.0.1}"
API_PORT="${QWEN_API_PORT:-30000}"
CTX_SIZE="${QWEN_CTX_SIZE:-65536}"
BATCH_SIZE="${QWEN_BATCH_SIZE:-2048}"
UBATCH_SIZE="${QWEN_UBATCH_SIZE:-512}"
MTP_DRAFT_N_MAX="${QWEN_MTP_DRAFT_N_MAX:-3}"
LOAD_MODE="${QWEN_LOAD_MODE:-auto}"
BACKEND_SAMPLING="${QWEN_BACKEND_SAMPLING:-0}"

for value_name in CTX_SIZE BATCH_SIZE UBATCH_SIZE MTP_DRAFT_N_MAX; do
  value="${!value_name}"
  if [[ ! "${value}" =~ ^[1-9][0-9]*$ ]]; then
    echo "${value_name} must be a positive integer." >&2
    exit 1
  fi
done

if (( UBATCH_SIZE > BATCH_SIZE )); then
  echo "QWEN_UBATCH_SIZE cannot exceed QWEN_BATCH_SIZE." >&2
  exit 1
fi

case "${LOAD_MODE}" in
  auto|none|mmap|mlock|mmap+mlock|dio) ;;
  *)
    echo "QWEN_LOAD_MODE must be one of: auto, none, mmap, mlock, mmap+mlock, dio." >&2
    exit 1
    ;;
esac

case "${BACKEND_SAMPLING}" in
  0) BACKEND_SAMPLING_ARGS=() ;;
  1) BACKEND_SAMPLING_ARGS=(--backend-sampling) ;;
  *)
    echo "QWEN_BACKEND_SAMPLING must be 0 or 1." >&2
    exit 1
    ;;
esac

case "${QWEN_CUDA_GRAPH_OPT:-0}" in
  0|1) ;;
  *)
    echo "QWEN_CUDA_GRAPH_OPT must be 0 or 1." >&2
    exit 1
    ;;
esac

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
export GGML_CUDA_GRAPH_OPT="${QWEN_CUDA_GRAPH_OPT:-0}"

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
  --batch-size "${BATCH_SIZE}" \
  --ubatch-size "${UBATCH_SIZE}" \
  --parallel 1 \
  --n-gpu-layers all \
  --n-gpu-layers-draft all \
  --flash-attn on \
  --cache-type-k q8_0 \
  --cache-type-v q8_0 \
  --spec-type draft-mtp \
  --spec-draft-n-max "${MTP_DRAFT_N_MAX}" \
  --load-mode "${LOAD_MODE}" \
  "${BACKEND_SAMPLING_ARGS[@]}" \
  --jinja \
  --reasoning-preserve \
  --metrics
