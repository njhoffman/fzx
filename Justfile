default:
    @just --list

# run the bats test suite, every CPU at once when GNU parallel is installed (bats -j needs it; moreutils'
# parallel is another program); FZX_TEST_JOBS=1 runs it serially
test *ARGS:
    #!/usr/bin/env bash
    set -euo pipefail
    jobs="${FZX_TEST_JOBS:-$(nproc)}"
    if ((jobs > 1)) && parallel --version 2> /dev/null | grep -q '^GNU parallel'; then
      exec bats --jobs "$jobs" {{ ARGS }} test
    fi
    exec bats {{ ARGS }} test

# shellcheck every bash file, executable components.tsv tables included (.bats files excluded: their
# idioms trip most checks)
lint:
    #!/usr/bin/env bash
    set -euo pipefail
    files=()
    while IFS= read -r -d '' f; do
      case "$f" in
        # reference material (untracked), not fzx's code
        resources/*) ;;
        *.sh | *.bash | bin/fzx) files+=("$f") ;;
        */components.tsv) [[ -x "$f" ]] && files+=("$f") ;;
      esac
    done < <(git ls-files -z --cached --others --exclude-standard)
    shellcheck "${files[@]}"

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
