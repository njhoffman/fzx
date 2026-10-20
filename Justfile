default:
    @just --list

# run the bats test suite
test *ARGS:
    bats {{ ARGS }} test

# shellcheck every bash file (.bats files excluded: their idioms trip most checks)
lint:
    git ls-files -z --cached --others --exclude-standard | grep -zE '\.(sh|bash)$|^bin/fzx$' | xargs -0 shellcheck

# print the resolved fzf command for a module
dry-run MODULE *ARGS:
    bin/fzx -m {{ MODULE }} --dry-run {{ ARGS }}

# symlink bin/fzx into ~/.local/bin (or $XDG_BIN_HOME); refuses to replace anything that is not a symlink
install:
    #!/usr/bin/env bash
    set -euo pipefail
    src="$(pwd -P)/bin/fzx"
    dest="${XDG_BIN_HOME:-$HOME/.local/bin}/fzx"
    mkdir -p "${dest%/*}"
    if [[ -e "$dest" && ! -L "$dest" ]]; then
      echo "install: $dest exists and is not a symlink; remove it first" >&2
      exit 1
    fi
    ln -sfn "$src" "$dest"
    echo "$dest -> $src"
    echo "zsh widgets: add 'source $(pwd -P)/shell/fzx.zsh' to your zshrc"
