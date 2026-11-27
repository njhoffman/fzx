#!/usr/bin/env bash
# displays actions. Outputs (names): power, primary, place, rotate; modes: set <output> <WxH> <rate>;
# profiles (displayd): apply, default <name>; any screen: save, rescue, daemon.

# shellcheck source=./source.sh
source "$(dirname "${BASH_SOURCE[0]}")/source.sh"

# displays::_on: the outputs with a mode on screen, one per line
displays::_on() { displays::outputs | awk -F'\t' '$2 == "on" { print $1 }'; }

# displays::_state <output> <var>: on, off or disconnected (empty for no such output)
displays::_state() {
  printf -v "$2" '%s' "$(displays::outputs | awk -F'\t' -v o="$1" '$1 == o { print $2 }')"
}

# displays::_key <prompt> <keys> <var>: one key typed on the terminal (FZX_TTY in tests), lowercased; fails
# on a key not among keys
displays::_key() {
  local _k_tty="${FZX_TTY:-/dev/tty}" _k_ans=""
  printf '\n\e[1m%s\e[0m ' "$1" >> "$_k_tty"
  IFS= read -rsn1 _k_ans < "$_k_tty" || :
  printf '\n' >> "$_k_tty"
  _k_ans="${_k_ans,,}"
  [[ -n "$_k_ans" && "$2" == *"$_k_ans"* ]] || return 1
  printf -v "$3" '%s' "$_k_ans"
}

# displays::power <output>: on (its preferred mode, right of an output already on) or off; the last output on
# stays on (a dark screen cannot be put back from here)
displays::power() {
  local out="$1" _st on=()
  displays::_state "$out" _st
  mapfile -t on < <(displays::_on)
  case "$_st" in
    on)
      if ((${#on[@]} < 2)); then
        printf 'displays: %s is the only output on; turn another on first\n' "$out" >&2
        return 1
      fi
      command xrandr --output "$out" --off
      ;;
    off)
      if ((${#on[@]})); then
        command xrandr --output "$out" --auto --right-of "${on[-1]}"
      else
        command xrandr --output "$out" --auto
      fi
      ;;
    disconnected)
      printf 'displays: %s is not connected\n' "$out" >&2
      return 1
      ;;
    *)
      printf 'displays: no output %s\n' "$out" >&2
      return 2
      ;;
  esac
}

# displays::place <output>: next to another output that is on, asking where (right of, left of, above,
# below, the same as) and, with more than one, next to which
displays::place() {
  local out="$1" where rel others=() o i k
  for o in $(displays::_on); do [[ "$o" != "$out" ]] && others+=("$o"); done
  ((${#others[@]})) || { printf 'displays: no other output is on to place %s next to\n' "$out" >&2; return 1; }
  displays::_key "place $out: [r]ight of, [l]eft of, [a]bove, [b]elow, [s]ame as (mirror)?" rlabs k || return 0
  case "$k" in r) where=--right-of ;; l) where=--left-of ;; a) where=--above ;; b) where=--below ;; s) where=--same-as ;; esac
  rel="${others[0]}"
  if ((${#others[@]} > 1)); then
    local list="" keys=""
    for ((i = 0; i < ${#others[@]} && i < 9; i++)); do list+=" [$((i + 1))] ${others[i]}" keys+="$((i + 1))"; done
    displays::_key "${where#--} which?$list" "$keys" k || return 0
    rel="${others[k - 1]}"
  fi
  command xrandr --output "$out" --auto "$where" "$rel"
}

# displays::rotate <output>: asks the rotation (normal, left, right, inverted)
displays::rotate() {
  local k rot
  displays::_key "rotate $1: [n]ormal, [l]eft, [r]ight, [i]nverted?" nlri k || return 0
  case "$k" in n) rot=normal ;; l) rot=left ;; r) rot=right ;; i) rot=inverted ;; esac
  command xrandr --output "$1" --rotate "$rot"
}

# displays::save: the layout on screen as a displayd profile, under a name typed on the terminal, optionally
# the default for the monitors connected now
displays::save() {
  local name k=""
  fzx::require ask
  fzx::ask "$FZX_STATE_DIR/displays/profile-names" "save the layout on screen as the displayd profile:" name || return 0
  displays::_key "make it the default for the monitors connected now? [y/n]" yn k || k=n
  if [[ "$k" == y ]]; then command "${FZX_DISPLAYS_DISPLAYD:-displayd}" save "$name" --default; else command "${FZX_DISPLAYS_DISPLAYD:-displayd}" save "$name"; fi
}

# displays::daemon: stop the displayd daemon when it runs, else start it
displays::daemon() {
  if command "${FZX_DISPLAYS_DISPLAYD:-displayd}" status 2> /dev/null | grep -q '^daemon *running'; then
    command "${FZX_DISPLAYS_DISPLAYD:-displayd}" stop && printf 'displayd stopped (until start or the next login)\n'
  else
    command "${FZX_DISPLAYS_DISPLAYD:-displayd}" start && printf 'displayd started\n'
  fi
}

# displays::action <name> [args...]
displays::action() {
  local action="${1:-}" o rc=0
  shift
  case "$action" in
    power | primary | place | rotate)
      (($#)) || return 0
      for o; do
        case "$action" in
          power) displays::power "$o" || rc=$? ;;
          primary) command xrandr --output "$o" --primary || rc=$? ;;
          place) displays::place "$o" || rc=$? ;;
          rotate) displays::rotate "$o" || rc=$? ;;
        esac
      done
      ;;
    set)
      # set <output> <WxH> <rate>
      [[ -n "${1:-}" && -n "${2:-}" ]] || return 0
      command xrandr --output "$1" --mode "$2" ${3:+--rate "$3"} || rc=$?
      ;;
    apply | default)
      [[ -n "${1:-}" ]] || return 0
      command "${FZX_DISPLAYS_DISPLAYD:-displayd}" "$action" "$1" || rc=$?
      ;;
    save) displays::save || rc=$? ;;
    rescue) command "${FZX_DISPLAYS_DISPLAYD:-displayd}" rescue || rc=$? ;;
    daemon) displays::daemon || rc=$? ;;
    *)
      printf 'displays: unknown action: %s\n' "$action" >&2
      return 2
      ;;
  esac
  return "$rc"
}

[[ "${BASH_SOURCE[0]}" == "$0" ]] && {
  source "$(dirname "${BASH_SOURCE[0]}")/../../lib/core.sh"
  fzx::require log config
  fzx::config_load "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" displays
  displays::action "$@"
}
