#!/usr/bin/env bash
# systemd defaults; override in ~/.config/fzx/config.sh or ~/.config/fzx/modules/systemd/config.sh
# Actions on system units run through sudo when fzx is not root (in the foreground, so it can prompt).

# shellcheck disable=SC2034  # settings here are read by lib/ and the module
declare -gA FZX_KEYS

FZX_KEYS[systemd.start]=alt-s
FZX_KEYS[systemd.stop]=ctrl-x
FZX_KEYS[systemd.restart]=alt-R
FZX_KEYS[systemd.enable]=alt-e
FZX_KEYS[systemd.disable]=alt-d
FZX_KEYS[systemd.journal]=ctrl-l # follow the unit's journal (ctrl-c returns to the list)
FZX_KEYS[systemd.edit]=ctrl-e    # systemctl edit (drop-in override)
