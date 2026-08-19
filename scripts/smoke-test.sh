#!/usr/bin/env bash
set -euo pipefail

API_HOST="${QWEN_API_HOST:-127.0.0.1}"
API_PORT="${QWEN_API_PORT:-30000}"

curl -fsS "http://${API_HOST}:${API_PORT}/v1/chat/completions" \
  -H 'Content-Type: application/json' \
  -d '{
    "model": "Qwen/Qwen3.8-27B",
    "messages": [{"role": "user", "content": "Reply with exactly: DGX Spark ready"}],
    "temperature": 0,
    "max_tokens": 128,
    "chat_template_kwargs": {"enable_thinking": false}
  }'
echo
