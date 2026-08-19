#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOOLS_DIR="${PROJECT_DIR}/tools"
JCODE_DIR="${TOOLS_DIR}/jcode"
JCODE_VERSION="v0.78.1"
JCODE_ARCHIVE="jcode-linux-aarch64.tar.gz"
JCODE_URL="https://github.com/1jehuang/jcode/releases/download/${JCODE_VERSION}/${JCODE_ARCHIVE}"
JCODE_SHA256="91ec4fe88f04aab8f6b294ee319e66701e273a9077003d24fcbf17d14562fd56"
DSH_DIR="${TOOLS_DIR}/deepseek-harness"

for tool in curl tar sha256sum node npm npx; do
  if ! command -v "${tool}" >/dev/null 2>&1; then
    echo "Missing required command: ${tool}" >&2
    exit 1
  fi
done

mkdir -p "${TOOLS_DIR}/.cache" "${JCODE_DIR}"
ARCHIVE_PATH="${TOOLS_DIR}/.cache/${JCODE_ARCHIVE}"

if [[ ! -x "${JCODE_DIR}/jcode" ]]; then
  if ! echo "${JCODE_SHA256}  ${ARCHIVE_PATH}" | sha256sum -c - >/dev/null 2>&1; then
    curl -fL --retry 3 --retry-delay 2 "${JCODE_URL}" -o "${ARCHIVE_PATH}"
  fi
  echo "${JCODE_SHA256}  ${ARCHIVE_PATH}" | sha256sum -c -

  TEMP_DIR="$(mktemp -d)"
  trap 'rm -rf "${TEMP_DIR}"' EXIT
  tar -xzf "${ARCHIVE_PATH}" -C "${TEMP_DIR}"
  JCODE_SOURCE="$(find "${TEMP_DIR}" -type f -name 'jcode*' -print -quit)"
  if [[ -z "${JCODE_SOURCE}" ]]; then
    echo "The jcode archive did not contain a jcode binary." >&2
    exit 1
  fi
  install -m 0755 "${JCODE_SOURCE}" "${JCODE_DIR}/jcode"
fi

if [[ ! -x "${DSH_DIR}/node_modules/.bin/dsh" ]]; then
  mkdir -p "${DSH_DIR}"
  cp "${PROJECT_DIR}/harnesses/deepseek-harness/package.json" \
    "${DSH_DIR}/package.json"
  cp "${PROJECT_DIR}/harnesses/deepseek-harness/pnpm-workspace.yaml" \
    "${DSH_DIR}/pnpm-workspace.yaml"
  npx --yes pnpm@11.7.0 install --dir "${DSH_DIR}"
fi

echo "Installed harnesses:"
JCODE_NO_TELEMETRY=1 "${JCODE_DIR}/jcode" --version
"${DSH_DIR}/node_modules/.bin/dsh" --version
