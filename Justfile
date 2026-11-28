default:
    @just --list

# test-progress (~/.shell) shows the run live and keeps it (~/.local/state/test-progress); without it, plain
# bats. TEST_PROGRESS_MODE=pane|events|bar|plain picks its view
tp := if path_exists(home_directory() / ".shell/scripts/test-progress") == "true" { home_directory() / ".shell/scripts/test-progress run --" } else { "" }

# run the bats test suite, every CPU at once when GNU parallel is installed (bats -j needs it; moreutils'
# parallel is another program); FZX_TEST_JOBS=1 runs it serially
test *ARGS:
    #!/usr/bin/env bash
    set -euo pipefail
    jobs="${FZX_TEST_JOBS:-$(nproc)}"
    if ((jobs > 1)) && parallel --version 2> /dev/null | grep -q '^GNU parallel'; then
      exec {{ tp }} bats --jobs "$jobs" {{ ARGS }} test
    fi
    exec {{ tp }} bats {{ ARGS }} test

# docker and systemd against the real daemon and user manager (test/live.bats; skipped in `just test`):
# makes and removes a container, volume, network and user unit named fzx-live-*
test-live *ARGS:
    FZX_TEST_LIVE=1 bats {{ ARGS }} test/live.bats

# shellcheck every bash file, executable components.tsv tables included (.bats files excluded: their
# idioms trip most checks)
lint:
    #!/usr/bin/env bash
    set -euo pipefail
    # a missing linter is not a lint failure: say what to install instead of xargs' exit 127
    if ! command -v shellcheck > /dev/null; then
      echo "just lint: shellcheck is not installed (apt install shellcheck, or https://github.com/koalaman/shellcheck)" >&2
      exit 2
    fi
    files=()
    while IFS= read -r -d '' f; do
      case "$f" in
        # reference material (untracked), not fzx's code
        resources/*) ;;
        *.sh | *.bash | bin/fzx) files+=("$f") ;;
        */components.tsv) [[ -x "$f" ]] && files+=("$f") ;;
      esac
    done < <(git ls-files -z --cached --others --exclude-standard)
    # batches across every core: one shellcheck over all of them took two minutes, each file re-reading what it
    # sources (xargs exits 123 when any batch finds something, so CI still fails)
    printf '%s\0' "${files[@]}" | xargs -0 -P "$(nproc)" -n 8 shellcheck

# regenerate the colors module's base16 presets from a checkout of base16-fzf
# (https://github.com/tinted-theming/base16-fzf)
presets DIR:
    bash modules/colors/presets-gen.sh {{ DIR }} > modules/colors/presets.tsv

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
