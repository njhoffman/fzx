#!/usr/bin/env bash
# shell actions on the selected names: edit (a function's file or a command's script in $EDITOR), help (the
# tldr or man page in the pager; a builtin's zshbuiltins entry), value (copy the parameters' values);
# completions: rescan (zsh-complete's list again) and status (zsh-complete status in the pager)

# shellcheck source=./preview.sh
source "$(dirname "${BASH_SOURCE[0]}")/preview.sh"

# shell::_say <message>: under fzf, shown until a key is pressed
shell::_say() {
  printf '%s\n' "$1"
  [[ -n "${FZX_SESSION_DIR:-}" ]] || return 0
  printf 'press a key '
  IFS= read -rsn1 < /dev/tty || :
}

# shell::edit_at <file> <name>: the file in $EDITOR, at the name's definition when the editor is a vi
shell::edit_at() {
  local editor="${EDITOR:-vi}"
  case "${editor##*/}" in
    vi | vim | nvim) command "$editor" "+/\\v^\\s*(function\\s+)?\\V$2\\v(\\s*\\(\\))?\\s*\\{" -- "$1" ;;
    *) command "$editor" -- "$1" ;;
  esac
}

# shell::action <edit|help|value|rescan|status> <names...>
shell::action() {
  local action="${1:-}" name line file kind dir p value values=() _k _n _a _t
  shift
  (($#)) || return 0
  case "$action:${FZX_MODE:-commands}" in
    edit:functions)
      name="$1"
      line="$(shell::dump_line function "$name")" || return 0
      shell::split "$line" _k _n file _a
      if [[ -f "$file" ]]; then
        shell::edit_at "$file" "$name"
      else
        # defined at the prompt or by eval: its definition, read-only
        shell::dump_dir dir
        file="$(mktemp --suffix=.zsh)"
        awk -v n="$name" '$0 == n " () {" { on = 1 } on { print } on && $0 == "}" { exit }' "$dir/functions.zsh" > "$file"
        chmod a-w -- "$file"
        "${EDITOR:-vi}" -- "$file"
        rm -f -- "$file"
      fi
      ;;
    edit:commands)
      p="$(type -P -- "$1")" || { shell::_say "shell: $1 is no file on PATH"; return 0; }
      if grep -qI . -- "$p" 2> /dev/null; then
        "${EDITOR:-vi}" -- "$(readlink -f -- "$p")"
      else
        shell::_say "shell: $p is a binary"
      fi
      ;;
    edit:completions)
      name="$1"
      file="$(shell::completions_rows | awk -F'\t' -v n="$name" '$1 == n { print $4; exit }')"
      [[ -r "$file" ]] || { shell::_say "shell: no completion file for $name"; return 0; }
      shell::edit_at "$file" "_$name"
      ;;
    rescan:completions)
      printf '\e[2masking zsh-complete for every completion binding (this takes a while)...\e[0m\n'
      shell::completions_refresh || shell::_say "shell: zsh-complete failed: the old list stays"
      ;;
    status:completions)
      shell::zsh_complete p || { shell::_say "shell: zsh-complete not found"; return 0; }
      printf '\e[2mzsh-complete status %s...\e[0m\n' "$1"
      (cd ~ && "$p" status "$1") 2>&1 | ${PAGER:-less -R}
      ;;
    rescan:* | status:*) shell::_say "shell: $action is the completions mode's" ;;
    edit:*) shell::_say "shell: edit opens functions and scripts (zsh records no file for aliases)" ;;
    help:*)
      name="$1"
      # an alias: the command it runs
      if [[ "${FZX_MODE:-commands}" == aliases ]] && line="$(shell::dump_line alias "$name")" && [[ -n "$line" ]]; then
        shell::split "$line" _k _t _n value
        value="$(shell::unquote "$value")"
        name="${value%%[[:space:]]*}"
      fi
      if line="$(shell::dump_line builtin "$name")" && [[ -n "$line" ]]; then
        MANPAGER="less -p '^       $name'" command man zshbuiltins
      elif command -v tldr > /dev/null && command tldr --color always -- "$name" > /dev/null 2>&1; then
        command tldr --color always -- "$name" | ${PAGER:-less -R}
      elif ! command man -- "$name" 2> /dev/null; then
        shell::_say "shell: no tldr or man page for $name"
      fi
      ;;
    value:params)
      fzx::require builtin
      for name; do
        shell::split "$(shell::param_rows | awk -F'\t' -v n="$name" '$1 == n { print; exit }')" _n kind value p
        [[ -n "$kind" ]] || continue
        [[ "$p" == 1 ]] && continue
        if [[ "$value" == $'\001'* ]]; then
          values+=("$(printf '%b' "${value#$'\001'}")")
        else
          values+=("$(shell::unquote "$value" "${kind%%-*}")")
        fi
      done
      ((${#values[@]})) && printf '%s\n' "${values[@]}" | fzx::clip
      ;;
    value:*) ;;
    *)
      printf 'shell: unknown action: %s\n' "$action" >&2
      return 2
      ;;
  esac
}

[[ "${BASH_SOURCE[0]}" == "$0" ]] && {
  source "$(dirname "${BASH_SOURCE[0]}")/../../lib/core.sh"
  fzx::require log config
  fzx::config_load "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" shell
  shell::action "$@"
}
