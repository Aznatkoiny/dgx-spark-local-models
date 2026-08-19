#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

case "${1:-}" in
  qwen)
    "${PROJECT_DIR}/scripts/stop-deepseek.sh"
    "${PROJECT_DIR}/scripts/stop.sh"
    exec "${PROJECT_DIR}/scripts/start.sh"
    ;;
  deepseek)
    "${PROJECT_DIR}/scripts/stop.sh"
    "${PROJECT_DIR}/scripts/stop-deepseek.sh"
    exec "${PROJECT_DIR}/scripts/start-deepseek.sh"
    ;;
  *)
    echo "Usage: $0 qwen|deepseek" >&2
    exit 2
    ;;
esac
