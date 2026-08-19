#!/usr/bin/env bash
set -euo pipefail

API_HOST="${DEEPSEEK_API_HOST:-127.0.0.1}"
API_PORT="${DEEPSEEK_API_PORT:-30001}"

curl -fsS "http://${API_HOST}:${API_PORT}/v1/chat/completions" \
  -H 'Content-Type: application/json' \
  -d '{
    "model": "deepseek-ai/DeepSeek-V4-Flash-0731",
    "messages": [{"role": "user", "content": "Reply with exactly: DeepSeek Spark ready"}],
    "thinking": false,
    "temperature": 0,
    "max_tokens": 128
  }'
echo
