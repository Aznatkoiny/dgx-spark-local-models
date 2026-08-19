#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODEL_DIR="${PROJECT_DIR}/models/DeepSeek-V4-Flash-0731-GGUF"
REPO="ggml-org/DeepSeek-V4-Flash-0731-GGUF"
REVISION="f559fd6005309e5f6bd650342ee8711ff189b3b8"
MODEL_PART_1="DeepSeek-V4-Flash-0731-Q2_K_S-00001-of-00002.gguf"
MODEL_PART_2="DeepSeek-V4-Flash-0731-Q2_K_S-00002-of-00002.gguf"
MIN_FREE_KIB=110000000

if ! command -v hf >/dev/null 2>&1; then
  echo "The Hugging Face CLI is required (command: hf)." >&2
  exit 1
fi

mkdir -p "${MODEL_DIR}"
FREE_KIB="$(df -Pk "${MODEL_DIR}" | awk 'NR == 2 {print $4}')"
if [[ ! "${FREE_KIB}" =~ ^[0-9]+$ ]] || (( FREE_KIB < MIN_FREE_KIB )); then
  echo "DeepSeek-V4-Flash-0731 Q2_K_S needs about 99 GB." >&2
  echo "At least 110 GB of free disk space is required before download." >&2
  exit 1
fi

echo "Downloading the experimental 98.6 GB Q2_K_S DeepSeek V4 Flash model."
echo "The latest V4 Pro checkpoint cannot fit on a single 128 GB DGX Spark."

hf download "${REPO}" \
  "${MODEL_PART_1}" \
  "${MODEL_PART_2}" \
  --revision "${REVISION}" \
  --local-dir "${MODEL_DIR}" \
  --max-workers 2

echo "Downloaded model to ${MODEL_DIR}"
