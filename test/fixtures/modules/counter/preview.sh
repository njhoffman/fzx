#!/usr/bin/env bash

counter::preview() {
  printf 'preview:%s\n' "$*"
}

[[ "${BASH_SOURCE[0]}" == "$0" ]] && counter::preview "$@"
