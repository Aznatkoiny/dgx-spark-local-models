#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODEL_DIR="${PROJECT_DIR}/models/Qwen3.8-27B-GGUF"
REPO="unsloth/Qwen3.8-27B-GGUF"
REVISION="990216cf312573f2ac4060279848e0f4237600c7"

if ! command -v hf >/dev/null 2>&1; then
  echo "The Hugging Face CLI is required (command: hf)." >&2
  exit 1
fi

mkdir -p "${MODEL_DIR}"

hf download "${REPO}" \
  Qwen3.8-27B-UD-Q6_K_L.gguf \
  mmproj-F16.gguf \
  MTP/mtp-Qwen3.8-27B-Q4_0.gguf \
  --revision "${REVISION}" \
  --local-dir "${MODEL_DIR}" \
  --max-workers 3
