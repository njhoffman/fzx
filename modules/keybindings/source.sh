#!/usr/bin/env bash
# keybindings source. Lines are "id<TAB>display<TAB>data", by mode:
#   zsh   id: a bindkey line (bindkey -M viins "^R" fzx-history-widget); data: the widget
#   tmux  the tmux module's keys rows (id: the bind-key line; data: its metadata)
#   fzf   id: the key; data: where the binding comes from (yours, fzf)
# Mode from $FZX_MODE (default zsh).

KEYS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# keybindings::zsh_dump_path <var>
keybindings::zsh_dump_path() {
  printf -v "$1" '%s/keybindings/zsh.tsv' "$FZX_STATE_DIR"
}

# keybindings::zsh_dump: the shell's bindings and user widgets (dump.zsh): the dump shell/fzx.zsh keeps
# while it is younger than FZX_KEYBINDINGS_ZSH_TTL, else a fresh one from an interactive zsh (kept too)
keybindings::zsh_dump() {
  local file age
  keybindings::zsh_dump_path file
  if [[ -s "$file" ]]; then
    age=$(($(date +%s) - $(stat -c %Y -- "$file")))
    ((age < ${FZX_KEYBINDINGS_ZSH_TTL:-86400})) && { command cat -- "$file"; return 0; }
  fi
  command -v zsh > /dev/null || {
    printf 'keybindings: zsh not found\n' >&2
    return 2
  }
  mkdir -p -- "${file%/*}"
  # the marker cuts whatever the user's startup files print. setsid: an interactive zsh takes the terminal
  # (its foreground process group), which would stop fzf; in a new session it has no terminal to take
  timeout 20 setsid -w zsh -ic "source ${KEYS_DIR@Q}/dump.zsh; print -r -- @@FZX@@; fzx-keys-dump" < /dev/null 2> /dev/null |
    sed '0,/^@@FZX@@$/d' > "$file.$$"
  if [[ -s "$file.$$" ]]; then
    mv -f -- "$file.$$" "$file"
    command cat -- "$file"
  else
    rm -f -- "$file.$$"
    printf 'keybindings: could not read the bindings from zsh -ic\n' >&2
    return 1
  fi
}

# keybindings::zle_docs: "widget<TAB>first sentence<TAB>description" for zsh's standard widgets, from the
# STANDARD WIDGETS section of zshzle(1); cached until the man page changes
keybindings::zle_docs() {
  local cache="$FZX_CACHE_DIR/keybindings/zle.tsv" page
  page="$(command man -w zshzle 2> /dev/null)" || return 0
  if [[ ! -s "$cache" || "$page" -nt "$cache" ]]; then
    mkdir -p -- "${cache%/*}"
    MANWIDTH=1000 command man zshzle 2> /dev/null | command col -bx | awk '
      function flush(   first) {
        if (name == "") return
        gsub(/  +/, " ", text); sub(/^ /, "", text)
        first = text; if (match(first, /\. /)) first = substr(first, 1, RSTART)
        print name "\t" first "\t" text; name = ""; text = ""
      }
      /^STANDARD WIDGETS/ { on = 1; next }
      on && /^[A-Z]/ { flush(); on = 0 }
      !on { next }
      /^       [a-z][a-z0-9-]*( |$)/ { flush(); name = $1; next }
      /^              / && name != "" { text = text " " $0 }
      END { flush() }' > "$cache.$$" && mv -f -- "$cache.$$" "$cache"
  fi
  command cat -- "$cache"
}

# the zsh rows: dump lines (stdin) with the zle docs and the user widgets' first comment lines
keybindings::zsh_rows() {
  local m=$'\e['"${FZX_COLORS[keys_map]:-38;5;250}m" k=$'\e['"${FZX_COLORS[keys_key]:-1;38;5;255}m"
  local w=$'\e['"${FZX_COLORS[keys_widget]:-38;5;117}m" u=$'\e['"${FZX_COLORS[keys_user]:-38;5;147}m"
  local d=$'\e['"${FZX_COLORS[dim]:-38;5;244}m" r=$'\e[0m'
  [[ -n "${NO_COLOR+x}" ]] && m="" k="" w="" u="" d="" r=""
  awk -F'\t' -v skip=" ${FZX_KEYBINDINGS_ZSH_SKIP[*]} " -v cm="$m" -v ck="$k" -v cw="$w" -v cu="$u" -v cd="$d" -v r="$r" '
    BEGIN {
      n = split("^[[200~ ^[[1;5A ^[[1;5B ^[[1;5C ^[[1;5D ^[[1;3A ^[[1;3B ^[[1;3C ^[[1;3D ^[[1~ ^[[4~ ^[[3~ ^[[2~ ^[[5~ ^[[6~ ^[[A ^[[B ^[[C ^[[D ^[OA ^[OB ^[OC ^[OD ^[[H ^[[F ^[OH ^[OF ^[[Z", seqs, " ")
      split("paste ctrl-up ctrl-down ctrl-right ctrl-left alt-up alt-down alt-right alt-left home end delete insert pgup pgdn up down right left up down right left home end home end shift-tab", names, " ")
    }
    # a key in bindkey notation ("^X^E", "^[f") -> "ctrl-x ctrl-e", "alt-f"
    function friendly(key,   out, t, alt, i, hit, used) {
      out = ""; alt = 0
      while (key != "") {
        hit = 0
        for (i = 1; i <= n; i++) if (index(key, seqs[i]) == 1) { t = names[i]; key = substr(key, length(seqs[i]) + 1); hit = 1; break }
        if (!hit) {
          if (substr(key, 1, 2) == "^[" && length(key) > 2) { alt = 1; key = substr(key, 3); continue }
          if (substr(key, 1, 3) == "\\M-") { alt = 1; key = substr(key, 4); continue }
          t = substr(key, 1, 2); used = 2
          if (t == "^?") t = "bspace"
          else if (t == "^I") t = "tab"
          else if (t == "^M") t = "enter"
          else if (t == "^[") t = "esc"
          else if (substr(t, 1, 1) == "^" && length(t) == 2) t = "ctrl-" tolower(substr(t, 2, 1))
          else if (substr(t, 1, 1) == "\\" && length(t) == 2) t = substr(t, 2, 1)
          else { t = substr(key, 1, 1); used = 1 }
          key = substr(key, used + 1)
          if (t == " ") t = "space"
        }
        out = out (out == "" ? "" : " ") (alt ? "alt-" : "") t; alt = 0
      }
      return out
    }
    # the comment right above the function definition in its file (or, for a file named after the
    # function, its first comment)
    function comment(fn, file,   line, lines, i, j, def, base, s) {
      if (file == "" || (getline line < file) < 0) return ""
      i = 0; lines[++i] = line
      while ((getline line < file) > 0) lines[++i] = line
      close(file)
      for (j = 1; j <= i; j++) {
        s = lines[j]; sub(/^[ \t]+/, "", s); sub(/^function[ \t]+/, "", s)
        if (index(s, fn) == 1 && substr(s, length(fn) + 1, 1) ~ /^([ \t({]|)$/) { def = j; break }
      }
      if (def) {
        # the comment line nearest the definition with words in it (in dotfiles, unrelated comments and
        # section rules often stack up above a function)
        for (j = def - 1; j >= 1 && lines[j] ~ /^[ \t]*#/; j--)
          if (lines[j] ~ /[[:alpha:]]/ && lines[j] !~ /^[ \t]*#+[ \t]*(--|==)/) { s = lines[j]; sub(/^[ \t]*#+[ \t]*/, "", s); return s }
        return ""
      }
      base = file; sub(/.*\//, "", base)
      if (base != fn) return ""
      for (j = 1; j <= i; j++) if (lines[j] ~ /^[ \t]*#/ && lines[j] !~ /^#!|^#compdef|vim:/) { s = lines[j]; sub(/^[ \t]*#+[ \t]*/, "", s); return s }
      return ""
    }
    FILENAME == "-" && $1 == "user" { ufn[$2] = $3; ufile[$2] = $4; next }
    FILENAME == "-" && $1 == "bind" { binds[++nb] = $2 "\t" $3; next }
    FILENAME != "-" { doc[$1] = $2; next }
    END {
      for (b = 1; b <= nb; b++) {
        split(binds[b], f, "\t"); map = f[1]; line = f[2]
        if (!match(line, /^"([^"\\]|\\.)*"/)) continue
        raw = substr(line, 1, RLENGTH); rest = substr(line, RLENGTH + 1)
        if (substr(rest, 1, 1) == "-") continue          # a range ("^@"-"^I" self-insert)
        sub(/^ /, "", rest); widget = rest
        if (index(skip, " " widget " ")) continue
        key = substr(raw, 2, length(raw) - 2)
        if (substr(widget, 1, 1) == "\"") { shown = "send " widget; desc = "types the string"; c = cd }
        else if (widget in ufn) {
          shown = widget; c = cu
          if (!(widget in udesc)) udesc[widget] = comment(ufn[widget], ufile[widget])
          desc = udesc[widget]; if (desc == "") desc = (ufn[widget] != widget ? "-> " ufn[widget] : "user widget")
        } else { shown = widget; c = cw; desc = doc[widget] }
        printf "bindkey -M %s %s %s\t%s%-8s%s %s%-18s%s %s%-32s%s %s%s%s\t%s\n", map, raw, rest,
          cm, map, r, ck, friendly(key), r, c, shown, r, cd, desc, r, widget
      }
    }' <(keybindings::zle_docs) -
}

# the fzf rows: your bindings (FZF_DEFAULT_OPTS and its file), then the fzf defaults you leave alone
keybindings::fzf_rows() {
  local k=$'\e['"${FZX_COLORS[keys_key]:-1;38;5;255}m" y=$'\e['"${FZX_COLORS[help_global]:-1;38;5;110}m"
  local d=$'\e['"${FZX_COLORS[dim]:-38;5;244}m" r=$'\e[0m'
  [[ -n "${NO_COLOR+x}" ]] && k="" y="" d="" r=""
  fzx::require keys
  awk -F'\t' -v ck="$k" -v cy="$y" -v cd="$d" -v r="$r" '
    NR == FNR { if ($1 != "" && !seen[$1]++) printf "%s\t%s%-14s%s %syours%s %s\tyours\n", $1, ck, $1, r, cy, r, $2; next }
    !($1 in seen) { printf "%s\t%s%-14s%s %sfzf  %s %s\tfzf\n", $1, ck, $1, r, cd, r, $2 }' \
    <(fzx::user_binds 2> /dev/null) <(printf '%s\n' "$FZX_FZF_DEFAULT_BINDS")
}

keybindings::source() {
  case "${FZX_MODE:-zsh}" in
    zsh)
      local dump
      dump="$(keybindings::zsh_dump)" || return
      keybindings::zsh_rows <<< "$dump"
      ;;
    tmux) FZX_MODE=keys "$FZX_ROOT/modules/tmux/source.sh" ;;
    fzf) keybindings::fzf_rows ;;
    *)
      printf 'keybindings: unknown mode: %s\n' "$FZX_MODE" >&2
      return 2
      ;;
  esac
}

[[ "${BASH_SOURCE[0]}" == "$0" ]] && {
  source "$(dirname "${BASH_SOURCE[0]}")/../../lib/core.sh"
  fzx::require log config
  fzx::config_load "$KEYS_DIR" keybindings
  keybindings::source "$@"
}
