# keybindings: the zsh side. Sourced by shell/fzx.zsh (and by the module's `zsh -ic` fallback); defines
# fzx-keys-dump, which prints the shell's bindings and user widgets as tab-separated lines:
#   bind<TAB>KEYMAP<TAB>a `bindkey -M KEYMAP` line ("^A" beginning-of-line)
#   user<TAB>WIDGET<TAB>FUNCTION<TAB>the file it was defined in (may be empty)
# fzx-keys-dump-file writes them to the file the module reads, $FZX_STATE_DIR/keybindings/zsh.tsv.

fzx-keys-dump() {
  emulate -L zsh
  zmodload zsh/zleparameter zsh/parameter 2> /dev/null
  local m line w f
  for m in $(bindkey -l); do
    # .safe is zle's fallback map; main is a link to emacs or viins
    [[ "$m" == .safe || "$m" == main ]] && continue
    bindkey -M "$m" | while IFS= read -r line; do print -r -- "bind"$'\t'"$m"$'\t'"$line"; done
  done
  for w in ${(k)widgets}; do
    [[ "$widgets[$w]" == user:* ]] || continue
    f="${widgets[$w]#user:}"
    print -r -- "user"$'\t'"$w"$'\t'"$f"$'\t'"${functions_source[$f]:-}"
  done
}

fzx-keys-dump-file() {
  emulate -L zsh
  local dir="${FZX_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/fzx}/keybindings"
  [[ -d "$dir" ]] || mkdir -p -- "$dir" || return
  fzx-keys-dump > "$dir/zsh.tsv.$$" && mv -f -- "$dir/zsh.tsv.$$" "$dir/zsh.tsv"
}
