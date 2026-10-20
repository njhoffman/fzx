#!/usr/bin/env bash
# logs defaults; override in ~/.config/fzx/config.sh or ~/.config/fzx/modules/logs/config.sh

FZX_KEYS[logs.follow]=ctrl-f # follow the log under the cursor (ctrl-c returns to the list)

# named log files; missing or unreadable ones are skipped
declare -gA FZX_LOGS_FILES=(
  [auth]=/var/log/auth.log
  [dmesg]=/var/log/dmesg
  [kern]=/var/log/kern.log
  [syslog]=/var/log/syslog
  [mpd]="$HOME/.mpd/mpd.log"
)

# globs whose matches are listed by file name
FZX_LOGS_GLOBS=(
  "$HOME/.local/state/nvim/*.log"
  "$HOME/.local/share/nvim/*.log"
  "$HOME/.cache/nvim/*.log"
  "/tmp/*.log"
)

# lines shown in the preview and before following
FZX_LOGS_LINES=200
