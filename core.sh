#!/bin/bash

source "./variables.sh"

tl_run() {
  tl_set_variables

  systemd-cat -t tinylinux printf 'Running: %s\n\n' "$*"

  systemd-cat \
    --level-prefix=TRUE \
    -t tinylinux \
    "$@" || exit 1
  systemd-cat -t tinylinux printf '\n\n'
}

tl_mkdir() {
  systemd-cat -t tinylinux mkdir -p -v "$@"

}

tl_jq() {
  tl_set_variables

  local input_file
  input_file="$1"

  # If the file does not exist, exit with a descriptive error message
  if [ ! -f "$input_file" ]; then
    tl_log 'File "%s" not found\n' "$input_file"
    exit 1
  fi

  tl_log 'Running jq on %s\n' "$input_file"

  shift
  jq "$@" <"$input_file"
}

tl_download() {
  tl_set_variables

  cd "$srcdir" || exit 1

  wget_args=(
    --continue
  )

  for arg in "$@"; do
    wget_args+=("$arg")
  done

  tl_run wget "${wget_args[@]}" || exit 1
}

tl_log() {
  local printf_args=()

  for arg in "$@"; do
    printf_args+=("$arg")
  done

  tl_run printf "${printf_args[@]}"
}
