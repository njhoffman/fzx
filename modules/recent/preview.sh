#!/usr/bin/env bash
# recent preview: the file, as the files module shows it

# shellcheck source=../files/preview.sh
source "$(dirname "${BASH_SOURCE[0]}")/../files/preview.sh"

recent::preview() { files::preview "$@"; }

[[ "${BASH_SOURCE[0]}" == "$0" ]] && recent::preview "$@"
