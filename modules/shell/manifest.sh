#!/usr/bin/env bash
# shell menu entries

shell::manifest() {
  fzx::entry shell "Commands on PATH and zsh builtins"
  fzx::entry shell:aliases "Shell aliases"
  fzx::entry shell:functions "Shell functions"
  fzx::entry shell:params "Shell parameters and the environment"
  fzx::entry shell:completions "Zsh completions (zsh-complete)"
}

# aliases, functions and parameters are zsh's (from its dump, or zsh -ic)
shell::applicable() {
  case "$1" in
    shell) return 0 ;;
    shell:completions)
      # shellcheck source=./source.sh
      source "$(dirname "${BASH_SOURCE[0]}")/source.sh"
      local z
      shell::zsh_complete z
      ;;
    *) command -v zsh > /dev/null || [[ -s "$FZX_STATE_DIR/shell/dump.tsv" ]] ;;
  esac
}

# shell::summary <target>: counts from the saved dump only (a fresh one would start an interactive zsh);
# commands: how many names PATH has
shell::summary() {
  local dump="$FZX_STATE_DIR/shell/dump.tsv"
  case "$1" in
    shell)
      # shellcheck source=./source.sh
      source "$(dirname "${BASH_SOURCE[0]}")/source.sh"
      shell::path_commands | awk 'END { printf "%d on PATH\n", NR }'
      ;;
    shell:aliases) [[ -s "$dump" ]] && awk -F'\t' "$FZX_AWK_PLURAL"'$1 == "alias" { n++ } END { print plural(n, "alias", "aliases") }' "$dump" ;;
    shell:functions)
      [[ -s "$dump" ]] && awk -F'\t' "$FZX_AWK_PLURAL"'$1 == "function" { n++; if (substr($2, 1, 1) == "_") c++ }
        END { printf "%s, %d for completion\n", plural(n - c, "function"), c }' "$dump"
      ;;
    shell:completions)
      # from the cached list only (making it takes zsh-complete a while)
      local file="${FZX_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/fzx}/shell/completions.tsv"
      [[ -s "$file" ]] && awk -F'\t' "$FZX_AWK_PLURAL"'$1 == "active" { if (!($2 in c)) n++; c[$2] = 1; p[$3] = 1 } END { k = 0; for (x in p) k++; print plural(n, "command") ", " plural(k, "provider") }' "$file"
      ;;
    shell:params)
      [[ -s "$dump" ]] && awk -F'\t' "$FZX_AWK_PLURAL"'$1 == "param" { n++; if ($3 ~ /export/) e++ } END { printf "%s, %d exported\n", plural(n, "parameter"), e }' "$dump"
      ;;
  esac
}
