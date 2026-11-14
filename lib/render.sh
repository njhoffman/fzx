#!/usr/bin/env bash
# render: text and markdown drawn for previews, shared by lib/preview.sh (the files module, `fzx preview`)
# and the modules' own previews, so the renderers and FZX_PREVIEW_VIEWERS work the same everywhere.
# Self-contained (no core.sh): module previews run as scripts of their own; source it by path.
#
#   fzx::render_text [--language L] [--name NAME] [--style S] [--line N] [--mark N]... [--wrap] [FILE]
#   fzx::render_markdown [--width N] [FILE]
#
# FILE absent or "-": stdin. Both honor NO_COLOR and FZF_PREVIEW_COLUMNS, and set _FZX_PV_RENDERER to
# the tool that drew the text. A user's FZX_PREVIEW_VIEWERS command takes over markdown always, and text
# when --name names the file (a glob key on the name, else the text type or FZX_PREVIEW_TEXT); snippets
# with only a --language (commands, man pages, logs) always go to bat, which highlights them by language.
# nvcat (Neovim, Tree-sitter, render-markdown) draws markdown, and the files `nvcat-dispatch --print` claims
# (config formats bat has no syntax for: kitty, tmux, systemd units, justfiles, ...), except with a --line
# (a grep hit), which bat highlights, and files over FZX_PREVIEW_NVCAT_MAX_LINES source lines (default 300):
# nvcat's complete output stops at 1000 screen rows, and failing there took seconds; those go to bat.

# fzx::preview_viewer <path> <type> <var>: the user's command for this file (FZX_PREVIEW_VIEWERS; text also
# FZX_PREVIEW_TEXT), empty when there is none
fzx::preview_viewer() {
  local _name="${1##*/}" _type="$2" _entry _key _glob="" _bytype="" _entries
  IFS=';' read -r -a _entries <<< "${FZX_PREVIEW_VIEWERS:-}"
  for _entry in "${_entries[@]}"; do
    [[ "$_entry" == *=* ]] || continue
    _key="${_entry%%=*}"
    _key="${_key//[[:space:]]/}"
    if [[ "$_key" == *[*?[]* ]]; then
      # shellcheck disable=SC2053  # the key is a glob
      [[ -z "$_glob" && "$_name" == $_key ]] && _glob="${_entry#*=}"
    elif [[ -z "$_bytype" && "$_key" == "$_type" ]]; then
      _bytype="${_entry#*=}"
    fi
  done
  [[ -z "$_glob$_bytype" && "$_type" == text ]] && _bytype="${FZX_PREVIEW_TEXT:-}"
  printf -v "$3" '%s' "${_glob:-$_bytype}"
}

# fzx::_preview_user <command> <path>: a user command, through bash so it may hold options and pipes; the
# path replaces {} or is appended. No stdin: some viewers (glow) read a stdin that is no terminal even when
# given a file, and a preview's open pipe would never end.
fzx::_preview_user() {
  local cmd="$1"
  if [[ "$cmd" == *"{}"* ]]; then
    cmd="${cmd//\{\}/\"\$1\"}"
  else
    # shellcheck disable=SC2016  # $1 is the inner bash's
    cmd+=' "$1"'
  fi
  bash -c "$cmd" fzx-preview "$2" < /dev/null
}

# fzx::_render_spool <suffix> <var>: stdin into a new temporary file (the caller removes it), for the tools
# that open their input by name (nvcat's filetype detection, user viewers)
fzx::_render_spool() {
  local _tmp
  _tmp="$(mktemp --suffix="$1" "${FZX_SESSION_DIR:-${TMPDIR:-/tmp}}/render.XXXXXX")" || return
  cat > "$_tmp"
  printf -v "$2" '%s' "$_tmp"
}

fzx::render_text() {
  local language="" name="" style="${FZX_PREVIEW_BAT_STYLE:-}" line="" wrap="" marks=() file="-" viewer tmp=""
  while (($#)); do
    case "$1" in
      --language) language="$2" && shift ;;
      --name) name="$2" && shift ;;
      --style) style="$2" && shift ;;
      --line) line="$2" && shift ;;
      --mark) marks+=(--highlight-line "$2") && shift ;;
      --wrap) wrap=1 ;;
      --) shift && file="${1:--}" && break ;;
      *) file="$1" ;;
    esac
    shift
  done
  if [[ -n "$name" ]]; then
    fzx::preview_viewer "$name" text viewer
    if [[ -n "$viewer" ]]; then
      _FZX_PV_RENDERER="user: $viewer"
      if [[ "$file" == - ]]; then
        fzx::_render_spool ".${name##*.}" tmp || return
        fzx::_preview_user "$viewer" "$tmp"
        local rc=$?
        rm -f -- "$tmp"
        return "$rc"
      fi
      fzx::_preview_user "$viewer" "$file"
      return
    fi
  fi
  # a file nvcat has a filetype for, matched by the name it goes by (a github blob's repository path)
  local ft
  if [[ "$file" != - && -z "$language$line" && -z "${NO_COLOR:+x}" ]] && command -v nvcat-dispatch > /dev/null &&
    command -v nvcat > /dev/null && fzx::_render_short "$file" &&
    ft="$(command nvcat-dispatch --print "${name:-$file}" 2> /dev/null)" && [[ -n "$ft" ]]; then
    _FZX_PV_RENDERER="nvcat:$ft"
    fzx::_render_nvcat "${FZF_PREVIEW_COLUMNS:-80}" "$ft" "$file" && return 0
  fi
  if command -v bat > /dev/null; then
    local args=(--color=always --paging=never)
    [[ -n "${NO_COLOR:+x}" ]] && args[0]=--color=never
    [[ -n "$style" ]] && args+=("--style=$style")
    [[ -n "$language" ]] && args+=("--language=$language")
    [[ -n "$name" ]] && args+=("--file-name=$name")
    [[ -n "${FZF_PREVIEW_COLUMNS:-}" ]] && args+=("--terminal-width=$FZF_PREVIEW_COLUMNS")
    [[ -n "$wrap" ]] && args+=(--wrap=auto)
    [[ "$line" =~ ^[0-9]+$ ]] && args+=(--highlight-line "$line" --line-range "$((line > 10 ? line - 10 : 1)):")
    _FZX_PV_RENDERER=bat
    if [[ "$file" == - ]]; then
      command bat "${args[@]}" "${marks[@]}" && return 0
      # stdin is spent: nothing to fall back with
      return 1
    fi
    command bat "${args[@]}" "${marks[@]}" -- "$file" && return 0
  fi
  _FZX_PV_RENDERER="cat"
  if [[ "$file" == - ]]; then command cat; else command cat -- "$file"; fi
}

# fzx::_render_short <file>: at most FZX_PREVIEW_NVCAT_MAX_LINES lines (reads no further than that)
fzx::_render_short() {
  local _max="${FZX_PREVIEW_NVCAT_MAX_LINES:-300}" _lines=()
  mapfile -t -n "$((_max + 1))" _lines < "$1" 2> /dev/null
  ((${#_lines[@]} <= _max))
}

# fzx::_render_nvcat <columns> <filetype> <file>: the whole file through nvcat, without its pager or its
# own bat fallback (the callers fall back, and name what drew the preview)
fzx::_render_nvcat() {
  command nvcat --columns "$1" --all --cat --fallback none --filetype "$2" -- "$3" 2> /dev/null < /dev/null
}

# markdown: the user's viewer, else nvcat, else bat as markdown in plain style, else cat; under
# NO_COLOR, or over FZX_PREVIEW_NVCAT_MAX_LINES lines, straight to bat (or cat)
fzx::render_markdown() {
  local width="${FZF_PREVIEW_COLUMNS:-80}" file="-" tmp="" viewer rc=1
  while (($#)); do
    case "$1" in
      --width) width="$2" && shift ;;
      --) shift && file="${1:--}" && break ;;
      *) file="$1" ;;
    esac
    shift
  done
  if [[ "$file" == - ]]; then
    fzx::_render_spool .md tmp || return
    file="$tmp"
  fi
  {
    local draw=1
    [[ -n "${NO_COLOR:+x}" ]] && draw=""
    [[ -n "$draw" ]] && ! fzx::_render_short "$file" && draw=""
    fzx::preview_viewer "$file" markdown viewer
    if [[ -n "$viewer" ]]; then
      _FZX_PV_RENDERER="user: $viewer"
      fzx::_preview_user "$viewer" "$file" && rc=0
    elif [[ -n "$draw" ]] && command -v nvcat > /dev/null &&
      _FZX_PV_RENDERER=nvcat && fzx::_render_nvcat "$width" markdown "$file"; then
      rc=0
    else
      FZF_PREVIEW_COLUMNS="$width" fzx::render_text --language markdown --style "${FZX_PREVIEW_BAT_STYLE:-plain}" --wrap "$file" && rc=0
    fi
  }
  [[ -n "$tmp" ]] && rm -f -- "$tmp"
  return "$rc"
}
