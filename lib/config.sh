#!/usr/bin/env bash
# config: source configuration layers in order; later layers override earlier ones.
#   1. <repo>/config/defaults.sh          fzx defaults
#   2. <module dir>/config.sh             the module's own defaults (its keys, colors, persist policy)
#   3. ~/.config/fzx/config.sh            the user, for every module
#   4. ~/.config/fzx/modules/<m>/config.sh the user, for one module
# Module defaults come before the user's config so a global user setting is never undone by a module.

# fzx::config_load [module_dir] [module]; records the loaded files in FZX_CONFIG_LOADED
fzx::config_load() {
  local module_dir="${1:-}" module="${2:-}" layer
  local layers=("$FZX_ROOT/config/defaults.sh")
  [[ -n "$module_dir" ]] && layers+=("$module_dir/config.sh")
  layers+=("$FZX_CONFIG_DIR/config.sh")
  [[ -n "$module" ]] && layers+=("$FZX_CONFIG_DIR/modules/$module/config.sh")

  FZX_CONFIG_LOADED=()
  for layer in "${layers[@]}"; do
    [[ -f "$layer" ]] || continue
    # shellcheck source=/dev/null
    source "$layer" || fzx::die 1 "config layer failed: $layer"
    FZX_CONFIG_LOADED+=("$layer")
    fzx::log debug "config loaded $layer"
  done
  fzx::_sorted_sgr
}

# fzx::_sorted_sgr: FZX_COLORS[sorted] from FZX_SORTED_STYLE and FZX_SORTED_UNDERLINE_COLOR, unless a layer
# set it. Sources splice it after other parameters ("38;5;45;" hl), so nothing to add is 24 (underline
# off) rather than empty, which would read as a reset.
fzx::_sorted_sgr() {
  [[ -n "${FZX_COLORS[sorted]:-}" ]] && return 0
  local _d _sgr=() _ul="" _c="${FZX_SORTED_UNDERLINE_COLOR:-}"
  for _d in ${FZX_SORTED_STYLE-underdashed}; do
    case "$_d" in
      bold) _sgr+=(1) ;;
      dim) _sgr+=(2) ;;
      italic) _sgr+=(3) ;;
      underline) _sgr+=(4) _ul=1 ;;
      blink) _sgr+=(5) ;;
      reverse) _sgr+=(7) ;;
      overline) _sgr+=(53) ;;
      underdouble) _sgr+=(4:2) _ul=1 ;;
      undercurl) _sgr+=(4:3) _ul=1 ;;
      underdotted) _sgr+=(4:4) _ul=1 ;;
      underdashed) _sgr+=(4:5) _ul=1 ;;
      *) fzx::log warn "FZX_SORTED_STYLE: unknown decoration $_d (skipped)" ;;
    esac
  done
  if [[ -n "$_ul" && -n "$_c" ]]; then
    if [[ "$_c" =~ ^#([0-9a-fA-F]{2})([0-9a-fA-F]{2})([0-9a-fA-F]{2})$ ]]; then
      _sgr+=("58;2;$((16#${BASH_REMATCH[1]}));$((16#${BASH_REMATCH[2]}));$((16#${BASH_REMATCH[3]}))")
    elif [[ "$_c" =~ ^[0-9]+$ ]] && ((_c < 256)); then
      _sgr+=("58;5;$_c")
    else
      fzx::log warn "FZX_SORTED_UNDERLINE_COLOR: not #rrggbb or 0-255: $_c (ignored)"
    fi
  fi
  local IFS=';'
  FZX_COLORS[sorted]="${_sgr[*]:-24}"
}

# fzx::config_show [module]: the resolved configuration, for `fzx config`
fzx::config_show() {
  local module="${1:-}" dir="" key var
  if [[ -n "$module" ]]; then
    dir="$(fzx::module_find "$module")" || fzx::die 2 "module not found: $module"
  fi
  fzx::config_load "$dir" "$module"

  printf '# layers (later wins)\n'
  printf '  %s\n' "${FZX_CONFIG_LOADED[@]}"
  printf '\n# FZX_KEYS\n'
  for key in $(printf '%s\n' "${!FZX_KEYS[@]}" | sort); do
    printf '  %-20s %s\n' "$key" "${FZX_KEYS[$key]}"
  done
  printf '\n# FZX_COLORS\n'
  for key in $(printf '%s\n' "${!FZX_COLORS[@]}" | sort); do
    printf '  %-20s \e[%sm%s\e[0m\n' "$key" "${FZX_COLORS[$key]}" "${FZX_COLORS[$key]}"
  done
  printf '\n# FZX_FZF_OPTS\n'
  printf '  %s\n' "${FZX_FZF_OPTS[@]}"
  printf '\n# settings\n'
  for var in $(compgen -v FZX_ | sort); do
    case "$var" in
      FZX_KEYS | FZX_COLORS | FZX_FZF_OPTS | FZX_CONFIG_LOADED | FZX_SESSIONS_DIR) continue ;;
    esac
    [[ "$(declare -p "$var" 2> /dev/null)" == "declare -"[aA]* ]] && continue
    printf '  %-24s %s\n' "$var" "${!var}"
  done
}
