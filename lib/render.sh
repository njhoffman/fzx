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
# nvcat starts Neovim, 0.3-1.2s a file, so its output is kept (FZX_PREVIEW_NVCAT_CACHE, default 1) in
# $FZX_CACHE_DIR/preview/nvcat, keyed by the file's path, mtime and size, the width, the filetype and the
# stamp of what nvcat draws with (fzx::nvcat_stamp: Neovim's config, nvcat, nvim), taken once per launch.

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

# fzx::nvcat_stamp <var>: what nvcat's output depends on besides the file: the newest mtime under Neovim's
# config ($XDG_CONFIG_HOME/nvim, .git and node_modules left out), then nvcat's and nvim's own
fzx::nvcat_stamp() {
  local _s _bin
  _s="$(find "${XDG_CONFIG_HOME:-$HOME/.config}/nvim" \( -name .git -o -name node_modules \) -prune -o -type f \
    -printf '%T@\n' 2> /dev/null | awk '$1 > m { m = $1 } END { printf "%d", m }')"
  for _bin in nvcat nvim; do
    _bin="$(command -v "$_bin")" && _s+=" $(stat -L -c %Y -- "$_bin" 2> /dev/null)"
  done
  printf -v "$1" '%s' "$_s"
}

# fzx::nvcat_stamp_save <session dir>: at a launch, the stamp into meta/nvcat_stamp, read by every preview of
# the screen; only when nvcat is there and its cache on (a few ms: one find over Neovim's config)
fzx::nvcat_stamp_save() {
  [[ "${FZX_PREVIEW_NVCAT_CACHE:-1}" == 1 ]] && command -v nvcat > /dev/null || return 0
  local _s
  fzx::nvcat_stamp _s
  printf '%s\n' "$_s" > "$1/meta/nvcat_stamp"
}

# fzx::_render_nvcat <columns> <filetype> <file>: the whole file through nvcat, without its pager or its
# own bat fallback (the callers fall back, and name what drew the preview)
fzx::_render_nvcat() {
  local cols="$1" ft="$2" file="$3" path st stamp="" key="" cache rc
  # the cache needs the file's mtime and size, a key and a directory; without any of them nvcat runs as is
  if [[ "${FZX_PREVIEW_NVCAT_CACHE:-1}" != 1 || -z "${FZX_CACHE_DIR:-}" ]] ||
    ! st="$(stat -L -c '%Y %s' -- "$file" 2> /dev/null)"; then
    fzx::_render_nvcat_run "$cols" "$ft" "$file"
    return
  fi
  [[ "$file" == /* ]] && path="$file" || path="$PWD/$file"
  if [[ -n "${FZX_SESSION_DIR:-}" && -r "$FZX_SESSION_DIR/meta/nvcat_stamp" ]]; then
    IFS= read -r stamp < "$FZX_SESSION_DIR/meta/nvcat_stamp"
  else
    fzx::nvcat_stamp stamp
  fi
  key="$(printf '%s\0' "$path" "$st" "$cols" "$ft" "$stamp" | md5sum 2> /dev/null)" || key=""
  cache="$FZX_CACHE_DIR/preview/nvcat/${key%% *}"
  if [[ -z "$key" ]] || ! mkdir -p -- "${cache%/*}" 2> /dev/null; then
    fzx::_render_nvcat_run "$cols" "$ft" "$file"
    return
  fi
  if [[ -s "$cache" ]]; then
    # used: gc removes cache files by age, so an entry in use stays
    touch -- "$cache" 2> /dev/null
    cat -- "$cache"
    return 0
  fi
  fzx::_render_nvcat_run "$cols" "$ft" "$file" > "$cache.$$"
  rc=$?
  # a failed render keeps nothing (the caller falls back to bat), nor does an empty one
  if ((rc == 0)) && [[ -s "$cache.$$" ]] && mv -f -- "$cache.$$" "$cache" 2> /dev/null; then
    cat -- "$cache"
    return 0
  fi
  ((rc == 0)) && cat -- "$cache.$$"
  rm -f -- "$cache.$$"
  return "$rc"
}

# fzx::_render_nvcat_cached <columns> <filetype> <file> <spool>: a spooled stdin (a new temporary file each
# time) is not worth keeping
fzx::_render_nvcat_cached() {
  if [[ -n "$4" ]]; then
    FZX_PREVIEW_NVCAT_CACHE=0 fzx::_render_nvcat "$1" "$2" "$3"
  else
    fzx::_render_nvcat "$1" "$2" "$3"
  fi
}

fzx::_render_nvcat_run() {
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
      _FZX_PV_RENDERER=nvcat && fzx::_render_nvcat_cached "$width" markdown "$file" "$tmp"; then
      rc=0
    else
      FZF_PREVIEW_COLUMNS="$width" fzx::render_text --language markdown --style "${FZX_PREVIEW_BAT_STYLE:-plain}" --wrap "$file" && rc=0
    fi
  }
  [[ -n "$tmp" ]] && rm -f -- "$tmp"
  return "$rc"
}
