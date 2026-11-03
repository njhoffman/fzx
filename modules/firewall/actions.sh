#!/usr/bin/env bash
# firewall actions through sudo (in the foreground, so it can ask for the password); a failure stays on
# screen until a key

# shellcheck source=./source.sh
source "$(dirname "${BASH_SOURCE[0]}")/source.sh"

# firewall::wait: keep a failure on screen until a key (foreground actions return to fzf at once)
firewall::wait() {
  [[ -t 1 ]] || return 0
  printf '\n\e[2m(press a key)\e[0m'
  read -rsn1 < /dev/tty || :
}

# firewall::_as_root <args...>: ufw as root: directly when root, else through sudo (which may ask)
firewall::_as_root() {
  if ((EUID == 0)); then command ufw "$@"; else command sudo ufw "$@"; fi
}

# firewall::_words <spec> [keep]: FIREWALL_WORDS, a rule as `ufw show added` prints it, split into words as
# the shell would ('Postfix SMTPS' is one); a comment is left out (delete matches the rule without it)
# unless keep is given
firewall::_words() {
  declare -ga FIREWALL_WORDS
  local _s="$1" _w="" _q="" _c _i _have=0
  FIREWALL_WORDS=()
  [[ -n "${2:-}" ]] || _s="${_s%% comment *}"
  for ((_i = 0; _i < ${#_s}; _i++)); do
    _c="${_s:_i:1}"
    if [[ -n "$_q" ]]; then
      if [[ "$_c" == "$_q" ]]; then _q=""; else _w+="$_c"; fi
    elif [[ "$_c" == "'" || "$_c" == '"' ]]; then
      _q="$_c" _have=1
    elif [[ "$_c" == " " ]]; then
      ((_have)) && FIREWALL_WORDS+=("$_w")
      _w="" _have=0
    else
      _w+="$_c" _have=1
    fi
  done
  ((_have)) && FIREWALL_WORDS+=("$_w")
  return 0
}

# firewall::rule_history: where the typed rules are kept (newest last)
firewall::rule_history() { printf '%s/firewall/rule_history' "$FZX_STATE_DIR"; }

# firewall::_add <position|""> <rule>: check the rule with `ufw --dry-run`, then add it (at the position:
# `ufw insert N`). A rule starts with allow, deny, reject or limit; a leading "ufw" is dropped
firewall::_add() {
  local pos="$1" rule="$2" out pre=()
  rule="${rule#"${rule%%[![:space:]]*}"}"
  rule="${rule#ufw }"
  firewall::_words "$rule" keep
  case "${FIREWALL_WORDS[0]:-}" in
    allow | deny | reject | limit) ;;
    *)
      printf 'firewall: a rule starts with allow, deny, reject or limit: %s\n' "$rule" >&2
      return 2
      ;;
  esac
  [[ -n "$pos" ]] && pre=(insert "$pos")
  if ! out="$(firewall::_as_root --dry-run "${pre[@]}" "${FIREWALL_WORDS[@]}" 2>&1)"; then
    printf '%s\n' "$out" >&2
    return 1
  fi
  firewall::_as_root "${pre[@]}" "${FIREWALL_WORDS[@]}"
}

# firewall::_ask_add <position|"">: read a rule on the terminal (readline, the history), then add it
firewall::_ask_add() {
  local rule prompt="ufw"
  fzx::require ask
  [[ -n "$1" ]] && prompt+=" insert $1"
  printf '\e[2me.g. allow 8080/tcp, allow from 192.168.1.0/24 to any port 22 proto tcp, deny out 25 comment '"'"'mail'"'"'\e[0m\n'
  fzx::ask "$(firewall::rule_history)" "$prompt" rule "${FZX_FIREWALL_RULE_HISTORY:-100}" || return 0
  firewall::_add "$1" "$rule"
}

# firewall::action <action> <id...>
firewall::action() {
  local action="${1:-}" mode="${FZX_MODE:-rules}" id rc=0 ids=()
  shift
  for id; do [[ -n "$id" && "$id" != - ]] && ids+=("$id"); done
  case "$action:$mode" in
    delete:rules)
      # rules added while ufw is off go by the rule itself; numbers shift down after a delete: the
      # highest first
      for id in "${ids[@]}"; do
        [[ "$id" == added:* ]] || continue
        firewall::_words "${id#added:}"
        firewall::_as_root delete "${FIREWALL_WORDS[@]}" || rc=$?
      done
      mapfile -t ids < <(printf '%s\n' "${ids[@]}" | grep -E '^[0-9]+$' | sort -rn)
      for id in "${ids[@]}"; do firewall::_as_root --force delete "$id" || rc=$?; done
      ;;
    allow:apps | deny:apps)
      for id in "${ids[@]}"; do firewall::_as_root "$action" "$id" || rc=$?; done
      ;;
    add:*) firewall::_ask_add "" || rc=$? ;;
    insert:rules)
      # above the first selected rule; rules added while ufw is off have no number to insert at
      id="$(printf '%s\n' "${ids[@]}" | grep -m1 -E '^[0-9]+$')" || id=""
      if [[ -z "$id" ]]; then
        printf 'firewall: insert goes above a numbered rule (ufw on): focus one\n' >&2
        rc=2
      else
        firewall::_ask_add "$id" || rc=$?
      fi
      ;;
    enable:*) firewall::_as_root --force enable || rc=$? ;;
    disable:*) firewall::_as_root disable || rc=$? ;;
    delete:* | allow:* | deny:* | insert:*)
      printf 'firewall: %s does not apply to %s\n' "$action" "$mode" >&2
      return 2
      ;;
    *)
      printf 'firewall: unknown action: %s\n' "$action" >&2
      return 2
      ;;
  esac
  ((rc)) && firewall::wait
  return "$rc"
}

[[ "${BASH_SOURCE[0]}" == "$0" ]] && {
  source "$(dirname "${BASH_SOURCE[0]}")/../../lib/core.sh"
  fzx::require log config
  fzx::config_load "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" firewall
  firewall::action "$@"
}
