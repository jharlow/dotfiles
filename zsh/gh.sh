#!/usr/bin/env zsh

script_dir=${0:A:h}

if [[ ${1:-} == pr && ${2:-} == l ]]; then
  exec "$script_dir/prl.sh" "${@:3}"
fi

exec gh "$@"
