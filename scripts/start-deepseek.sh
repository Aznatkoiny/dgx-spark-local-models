#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUN_DIR="${PROJECT_DIR}/run"
LOG_DIR="${PROJECT_DIR}/logs"
PID_FILE="${RUN_DIR}/deepseek-v4-flash.pid"
LOG_FILE="${LOG_DIR}/deepseek-v4-flash.log"
API_HOST="${DEEPSEEK_API_HOST:-127.0.0.1}"
API_PORT="${DEEPSEEK_API_PORT:-30001}"

mkdir -p "${RUN_DIR}" "${LOG_DIR}"

if [[ -f "${PID_FILE}" ]]; then
  EXISTING_PID="$(<"${PID_FILE}")"
  if kill -0 "${EXISTING_PID}" 2>/dev/null; then
    echo "DeepSeek server is already running (PID ${EXISTING_PID})."
    exit 0
  fi
  rm -f "${PID_FILE}"
fi

nohup "${PROJECT_DIR}/scripts/serve-deepseek.sh" >"${LOG_FILE}" 2>&1 &
SERVER_PID=$!
echo "${SERVER_PID}" >"${PID_FILE}"

echo "Started DeepSeek-V4-Flash-0731 (PID ${SERVER_PID})."
echo "Log: ${LOG_FILE}"
echo "Waiting for http://${API_HOST}:${API_PORT}/health ..."

for _ in $(seq 1 360); do
  if curl -fsS "http://${API_HOST}:${API_PORT}/health" >/dev/null 2>&1; then
    echo "Server is ready at http://${API_HOST}:${API_PORT}/v1"
    exit 0
  fi
  if ! kill -0 "${SERVER_PID}" 2>/dev/null; then
    echo "Server exited during startup. Last log lines:" >&2
    tail -n 100 "${LOG_FILE}" >&2
    exit 1
  fi
  sleep 5
done

echo "Server is still loading. Follow progress with:" >&2
echo "  tail -f ${LOG_FILE}" >&2
exit 1
