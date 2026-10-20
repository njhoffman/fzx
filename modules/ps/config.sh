#!/usr/bin/env bash
# ps defaults; override in ~/.config/fzx/config.sh or ~/.config/fzx/modules/ps/config.sh

# shellcheck disable=SC2034  # settings here are read by lib/ and the module
declare -gA FZX_KEYS

FZX_KEYS[ps.term]=ctrl-x    # send SIGTERM to the selected processes
FZX_KEYS[ps.children]=ctrl-o # open the children of the process under the cursor
