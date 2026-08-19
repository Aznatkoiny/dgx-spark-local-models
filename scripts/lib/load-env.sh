#!/usr/bin/env bash

# Load defaults from a shell-compatible .env file, then restore variables that
# were explicitly present in the caller's environment.
load_env_defaults() {
  local env_file="$1"
  shift

  [[ -f "${env_file}" ]] || return 0

  local name
  declare -A env_was_set=()
  declare -A env_previous_value=()

  for name in "$@"; do
    if [[ -v "${name}" ]]; then
      env_was_set["${name}"]=1
      env_previous_value["${name}"]="${!name}"
    fi
  done

  set -a
  # shellcheck disable=SC1090
  source "${env_file}"
  set +a

  for name in "${!env_was_set[@]}"; do
    printf -v "${name}" '%s' "${env_previous_value[${name}]}"
    export "${name}"
  done
}
