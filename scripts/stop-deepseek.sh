#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PID_FILE="${PROJECT_DIR}/run/deepseek-v4-flash.pid"

if [[ ! -f "${PID_FILE}" ]]; then
  echo "No DeepSeek server PID file found."
  exit 0
fi

SERVER_PID="$(<"${PID_FILE}")"
if kill -0 "${SERVER_PID}" 2>/dev/null; then
  kill "${SERVER_PID}"
  for _ in $(seq 1 30); do
    if ! kill -0 "${SERVER_PID}" 2>/dev/null; then
      break
    fi
    sleep 1
  done
fi

rm -f "${PID_FILE}"
echo "Stopped DeepSeek server."
