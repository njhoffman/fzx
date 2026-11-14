#!/usr/bin/env bash
# files: find files and directories, or grep their contents. `fzx -m files[:dirs|:grep] [DIR]`.
# Enter prints absolute paths (path:line for grep). In grep mode ctrl-t switches between grepping as you type
# and fzf filtering the matches (the grep term frozen), and back (files::transform).

FZX_MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/core.sh
source "${FZX_ROOT:-$FZX_MODULE_DIR/../..}/lib/core.sh"
# shellcheck source=./source.sh
source "$FZX_MODULE_DIR/source.sh"

# shellcheck disable=SC2034  # FZX_ACTION_ARGS*: read by lib/actions.sh
files::opts() {
  local tool="" flags="" label="" view=""
  files::args "${FZX_ARGS[@]}" || return
  files::base "$FILES_DIR" || return
  # undo takes no rows: fzf runs no command naming a row ({+1}) when nothing matches, as after a replacement
  FZX_ACTION_ARGS_FOR['undo']='{q}'

  if [[ "$FZX_MODE" == args ]]; then
    files::opts_flags
    return
  fi
  # alt-a's flags for this mode's tool: shown in the header, and part of the cache key (meta/view), so rows
  # cached without them (or with others) are never served
  files::mode_tool "$FZX_MODE" tool
  [[ -n "$tool" ]] && files::flags_get "$tool" flags
  files::flags_label "$tool" "$flags" label
  if fzx::in_session; then
    [[ -n "$flags" ]] && view="$tool$(printf '%s' "$flags" | cksum | cut -d' ' -f1)"
    fzx::meta_set view "$view"
    # alt-up and into find this session again by its resolved directory (fzx::_nav_goto --ancestor)
    fzx::session_goto_args "$FILES_BASE"
  fi
  FZX_OPTS+=(
    --delimiter=$'\t'
    "--preview-window=right,55%,nohidden"
    "--header=$label${FILES_BASE/#$HOME/\~}"
  )
  if [[ "$FZX_MODE" == replace ]]; then
    # the query is the replacement: rows and preview follow it, enter applies it
    FZX_OPTS+=(
      --with-nth=3
      --accept-nth='{1}:{2}'
      --disabled
      --multi
      --bind "change:reload:sleep 0.1; $(fzx::cb search)"
      --preview "$(fzx::cb preview '{1}' '{2}' '{q}')"
      "--header=$label${FILES_BASE/#$HOME/\~}  replace: $FILES_TERM  (type the replacement; \$1 is a group, \$\$ a dollar; enter applies to the selected or every match)"
    )
    FZX_ACTION_ARGS_FOR['apply']='{q} {+1} -- {+2}'
    FZX_ACTION_ARGS_FOR['edit']='{1} {2}'
    if fzx::in_session; then
      local act flags
      fzx::require actions
      fzx::comp_field action apply flags flags 2> /dev/null || flags=foreground,asks,restart
      fzx::_action_bind_string apply "$flags" act
      fzx::bind enter "$act" "apply the replacement to the selected matches (all when none are selected)"
    fi
    return 0
  fi
  if [[ "$FZX_MODE" == grep ]]; then
    FZX_OPTS+=(
      --with-nth=3
      --accept-nth='{1}:{2}'
      --disabled
      --bind "change:reload:sleep 0.1; $(fzx::cb search)"
      --preview "$(fzx::cb preview '{1}' '{2}')"
    )
    FZX_ACTION_ARGS='{1} {2}'
    # trash takes the files of every selected match
    FZX_ACTION_ARGS_FOR['trash']='{+1}'
  else
    FZX_OPTS+=(
      --with-nth=2
      --keep-right
      --accept-nth=1
      --scheme=path
      --preview "$(fzx::cb preview '{1}')"
    )
    if [[ "$FZX_MODE" == locate ]]; then
      # the query is locate's words: the database answers, fzf does not filter
      local db="" age=""
      files::locate_db db && files::_age "$db" age
      FZX_OPTS+=(--disabled --bind "change:reload:sleep 0.1; $(fzx::cb search)"
        "--header=$label${FILES_BASE/#$HOME/\~}  locate${age:+ (database $age old: updatedb refreshes it)}")
    fi
  fi
  if [[ "$FZX_MODE" == grep ]] && fzx::in_session; then
    # grep starts grepping: a filter left on by an earlier visit to the mode is dropped
    fzx::state_set files_grep_filter ""
    fzx::bind "${FZX_KEYS[files.filter]}" "transform:$(fzx::cb transform filter)" \
      "grep: filter the matches with fzf (the grep term frozen), and back to grepping"
    command -v rg > /dev/null &&
      fzx::bind "${FZX_KEYS[files.replace]}" "transform:$(fzx::cb transform replace)" \
        "grep: replace the term's matches (the query becomes the replacement)"
  fi
  if [[ -n "$tool" ]] && fzx::in_session; then
    fzx::bind "${FZX_KEYS[files.flags]}" "transform:$(fzx::cb transform flags)" \
      "files, dirs, grep: the $tool flags to add (a screen: type them, enter applies)"
  fi
  if fzx::in_session; then
    local parent="${FILES_BASE%/*}"
    fzx::bind "${FZX_KEYS[files.into]}" "transform:$(fzx::cb nav goto --ancestor "files:$FZX_MODE" '{1}')" \
      "browse the directory under the cursor"
    fzx::bind "${FZX_KEYS[files.up]}" "transform:$(fzx::cb nav goto --ancestor "files:$FZX_MODE" "$(printf '%q' "${parent:-/}")")" \
      "browse the parent directory"
  fi
}

# files::opts_flags: the args screen (alt-a, a child of the screen it edits): the rows list the flags allowed,
# the query is the flags (it starts with the saved ones), the preview checks them as you type, enter saves
# them and returns, esc returns without saving
files::opts_flags() {
  local saved where="${FILES_BASE/#$HOME/\~}"
  [[ -n "$FILES_TOOL" ]] || {
    printf 'files: args needs --tool rg|fd\n' >&2
    return 2
  }
  files::flags_get "$FILES_TOOL" saved
  fzx::meta_set view ""
  FZX_OPTS+=(
    --delimiter=$'\t'
    --with-nth=2
    --disabled
    --no-sort
    "--query=$saved"
    "--preview-window=up,3,nohidden,border-bottom"
    --preview "$(fzx::cb preview '{q}')"
    --bind "change:refresh-preview"
    "--header=$where  $FILES_TOOL flags: type them, enter applies, esc leaves them as they were (words split on blanks)"
  )
  if fzx::in_session; then
    fzx::bind enter "transform:$(fzx::cb transform flags-apply)" "apply the flags and go back"
  fi
}

fzx::module_main "$@"
