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
        awk '{ n++; if ($1 > 0) a++ } END { printf "%d sessions, %d attached\n", n, a }'
      ;;
    tmux:windows)
      command tmux list-windows -a -F '#{session_id}' |
        awk '{ n++; if (!seen[$1]++) s++ } END { printf "%d windows across %d sessions\n", n, s }'
      ;;
    tmux:panes)
      command tmux list-panes -a -F '#{window_id}' |
        awk '{ n++; if (!seen[$1]++) w++ } END { printf "%d panes across %d windows\n", n, w }'
      ;;
    tmux:buffers) printf '%s buffers\n' "$(command tmux list-buffers -F x | wc -l)" ;;
    tmux:keys) command tmux list-keys | tmux::summary_keys ;;
    *) return 0 ;;
  esac
}

# tmux::summary_keys: `tmux list-keys` lines -> "N bindings in M tables"
tmux::summary_keys() {
  awk '{ for (i = 1; i < NF; i++) if ($i == "-T") { n++; if (!seen[$(i + 1)]++) t++; break } }
    END { printf "%d bindings in %d tables\n", n, t }'
}
