#!/usr/bin/env bash
# dirs preview: the recent module's (git branch and change count for a work tree, then the files preview)
# shellcheck source=../recent/preview.sh
source "$(dirname "${BASH_SOURCE[0]}")/../recent/preview.sh"

dirs::preview() { recent::preview "$@"; }

[[ "${BASH_SOURCE[0]}" == "$0" ]] && dirs::preview "$@"
