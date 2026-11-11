#!/usr/bin/env bash
# tmux menu entries; the summaries describe the running server (the reference entries have none)

tmux::manifest() {
  fzx::entry tmux 'Tmux sessions (alt-s switches or attaches)'
  fzx::entry tmux:windows 'Tmux windows across all sessions'
  fzx::entry tmux:panes 'Tmux panes across all sessions'
  fzx::entry tmux:buffers 'Tmux paste buffers'
  fzx::entry tmux:keys 'Tmux key bindings'
  fzx::entry tmux:commands 'Tmux command signatures'
  fzx::entry tmux:options 'Tmux options and values'
  fzx::entry tmux:variables 'Tmux format variables and values'
  fzx::entry tmux:styles 'Tmux styles'
  fzx::entry tmux:formats 'Tmux format templates and rendered samples'
  fzx::entry tmux:status 'Tmux status line samples'
  fzx::entry tmux:hooks 'Tmux hooks by scope'
}

tmux::applicable() { command -v tmux > /dev/null && command -v python3 > /dev/null; }

tmux::summary() {
  command tmux list-sessions > /dev/null 2>&1 || { printf 'no server running\n'; return 0; }
  case "$1" in
    tmux)
      command tmux list-sessions -F '#{session_attached}' |
        awk "$FZX_AWK_PLURAL"'{ n++; if ($1 > 0) a++ } END { printf "%s, %d attached\n", plural(n, "session"), a }'
      ;;
    tmux:windows)
      command tmux list-windows -a -F '#{session_id}' |
        awk "$FZX_AWK_PLURAL"'{ n++; if (!seen[$1]++) s++ } END { print plural(n, "window") " across " plural(s, "session") }'
      ;;
    tmux:panes)
      command tmux list-panes -a -F '#{window_id}' |
        awk "$FZX_AWK_PLURAL"'{ n++; if (!seen[$1]++) w++ } END { print plural(n, "pane") " across " plural(w, "window") }'
      ;;
    tmux:buffers) printf '%s\n' "$(fzx::plural "$(command tmux list-buffers -F x | wc -l)" buffer)" ;;
    tmux:keys) command tmux list-keys | tmux::summary_keys ;;
    tmux:commands | tmux:options | tmux:variables | tmux:styles | tmux:formats | tmux:status | tmux:hooks)
      # the mode's own list, as its rows count them
      local mode="${1#tmux:}" word
      # shellcheck source=./source.sh
      source "$(dirname "${BASH_SOURCE[0]}")/source.sh" || :
      case "$mode" in status) word=sample ;; *) word="${mode%s}" ;; esac
      printf '%s\n' "$(fzx::plural "$(FZX_MODE="$mode" tmux::source 2> /dev/null | wc -l)" "$word")"
      ;;
    *) return 0 ;;
  esac
}

# tmux::summary_keys: `tmux list-keys` lines -> "N bindings in M tables" ("1 binding" for one)
tmux::summary_keys() {
  awk "$FZX_AWK_PLURAL"'{ for (i = 1; i < NF; i++) if ($i == "-T") { n++; if (!seen[$(i + 1)]++) t++; break } }
    END { print plural(n, "binding") " in " plural(t, "table") }'
}
