#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PID_FILE="${PROJECT_DIR}/run/qwen3.8-27b.pid"

if [[ ! -f "${PID_FILE}" ]]; then
  echo "No Qwen server PID file found."
  exit 0
fi

SERVER_PID="$(<"${PID_FILE}")"
if kill -0 "${SERVER_PID}" 2>/dev/null; then
  kill "${SERVER_PID}"
  for _ in $(seq 1 20); do
    if ! kill -0 "${SERVER_PID}" 2>/dev/null; then
      break
    fi
    sleep 1
  done
fi

rm -f "${PID_FILE}"
echo "Stopped Qwen server."
