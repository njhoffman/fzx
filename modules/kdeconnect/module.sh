#!/usr/bin/env bash
# kdeconnect: KDE Connect devices, their notifications and SMS conversations, and the commands they offer. `fzx -m
# kdeconnect[:notifications|:commands|:sms]`. Enter prints the ids; in sms it opens the thread's chat (`kdeconnect:chat
# --thread DEVICE/THREAD`): its messages, newest next to the prompt, and what you type is the reply.

FZX_MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/core.sh
source "${FZX_ROOT:-$FZX_MODULE_DIR/../..}/lib/core.sh"
# shellcheck source=./source.sh
source "$FZX_MODULE_DIR/source.sh"

kdeconnect::opts() {
  if [[ "${FZX_MODE:-}" == chat ]]; then
    kdeconnect::_chat_opts
    return
  fi
  if [[ "${FZX_MODE:-}" == sms ]] && fzx::in_session; then
    fzx::bind enter "transform:$(fzx::cb transform chat '{1}')" "open the conversation: read it and reply"
  fi
  FZX_OPTS+=(
    --delimiter=$'\t'
    --with-nth=2
    --accept-nth=1
    --tiebreak=index
    --preview "$(fzx::cb preview '{1}' '{3}' '{4}')"
    "--preview-window=down,45%,nohidden"
  )
  # ctrl-y: what the row is called, not the id the commands take
  # shellcheck disable=SC2034  # read by lib/actions.sh
  FZX_ACTION_ARGS_FOR['copy']='{+3}'
}

# the chat screen: the query is the reply (no filtering), the header row names the thread, the newest message
# sits next to the prompt, long ones wrap; no preview, the rows hold the whole text
kdeconnect::_chat_opts() {
  FZX_OPTS+=(
    --delimiter=$'\t'
    --with-nth=2
    --accept-nth=1
    --disabled
    --no-sort
    --header-lines=1
    --wrap
    "--preview-window=hidden"
  )
  # nor does the layout callback open one by the terminal's width
  # shellcheck disable=SC2034  # read by lib/opts.sh
  FZX_PREVIEW_LAYOUTS=()
  fzx::in_session || return 0
  fzx::bind enter "transform:$(fzx::cb transform send)" "send what you typed (the first enter asks)"
  # typing again drops a question still in the header
  FZX_OPTS+=(--bind "change:change-header:")
}

fzx::module_main "$@"
