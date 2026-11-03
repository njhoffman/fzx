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

# fzx::_sgr_decor <setting> <decorations> <array var>: SGR parameters for decoration names (bold dim italic
# underline blink reverse overline underdouble undercurl underdotted underdashed) appended to the array;
# returns 0 when one of them is an underline
fzx::_sgr_decor() {
  local _d _ul=1
  local -n _sd_out="$3"
  for _d in $2; do
    case "$_d" in
      bold) _sd_out+=(1) ;;
      dim) _sd_out+=(2) ;;
      italic) _sd_out+=(3) ;;
      underline) _sd_out+=(4) _ul=0 ;;
      blink) _sd_out+=(5) ;;
      reverse) _sd_out+=(7) ;;
      overline) _sd_out+=(53) ;;
      underdouble) _sd_out+=(4:2) _ul=0 ;;
      undercurl) _sd_out+=(4:3) _ul=0 ;;
      underdotted) _sd_out+=(4:4) _ul=0 ;;
      underdashed) _sd_out+=(4:5) _ul=0 ;;
      *) fzx::log warn "$1: unknown decoration $_d (skipped)" ;;
    esac
  done
  return "$_ul"
}

# fzx::_sgr_color <setting> <color> <38|58> <array var>: a #rrggbb or 0-255 color as SGR parameters (38: the
# text, 58: the underline) appended to the array; "" adds nothing, anything else is skipped with a warning
fzx::_sgr_color() {
  local -n _sc_out="$4"
  [[ -n "$2" ]] || return 0
  if [[ "$2" =~ ^#([0-9a-fA-F]{2})([0-9a-fA-F]{2})([0-9a-fA-F]{2})$ ]]; then
    _sc_out+=("$3;2;$((16#${BASH_REMATCH[1]}));$((16#${BASH_REMATCH[2]}));$((16#${BASH_REMATCH[3]}))")
  elif [[ "$2" =~ ^[0-9]+$ ]] && (($2 < 256)); then
    _sc_out+=("$3;5;$2")
  else
    fzx::log warn "$1: not #rrggbb or 0-255: $2 (ignored)"
  fi
}

# fzx::_sgr_join <array var> <empty value> <var>: the parameters joined with ";", or the value for none
fzx::_sgr_join() {
  local -n _sj_in="$1"
  local IFS=';'
  printf -v "$3" '%s' "${_sj_in[*]:-$2}"
}

# fzx::_sorted_sgr: the sort marking's colors, unless a layer set them.
#   FZX_COLORS[sorted]         rows: FZX_SORTED_STYLE and FZX_SORTED_UNDERLINE_COLOR; 24 (underline off,
#                              which adds nothing) under FZX_SORTED_SHOW=header, whatever a layer set.
#                              Sources splice it after other parameters ("38;5;45;" hl), so nothing to add
#                              is 24 rather than empty, which would read as a reset.
#   FZX_COLORS[header_column]  a header row's other columns: FZX_HEADER_COLUMN_COLOR; empty leaves fzf's
#                              header color
#   FZX_COLORS[header_sorted]  its sorted column and arrow: FZX_SORTED_HEADER_STYLE and FZX_SORTED_HEADER_COLOR
fzx::_sorted_sgr() {
  local _sgr=()
  case "${FZX_SORTED_SHOW:-header}" in
    rows | header | both) ;;
    *)
      fzx::log warn "FZX_SORTED_SHOW: not header, rows or both: $FZX_SORTED_SHOW (header)"
      FZX_SORTED_SHOW=header
      ;;
  esac
  if [[ "${FZX_SORTED_SHOW:-header}" == header ]]; then
    printf -v 'FZX_COLORS[sorted]' '%s' 24
  elif [[ -z "${FZX_COLORS[sorted]:-}" ]]; then
    fzx::_sgr_decor FZX_SORTED_STYLE "${FZX_SORTED_STYLE-underdashed}" _sgr &&
      fzx::_sgr_color FZX_SORTED_UNDERLINE_COLOR "${FZX_SORTED_UNDERLINE_COLOR:-}" 58 _sgr
    fzx::_sgr_join _sgr 24 "FZX_COLORS[sorted]"
  fi
  if [[ -z "${FZX_COLORS[header_column]+set}" ]]; then
    _sgr=()
    fzx::_sgr_color FZX_HEADER_COLUMN_COLOR "${FZX_HEADER_COLUMN_COLOR-#007e95}" 38 _sgr
    fzx::_sgr_join _sgr "" "FZX_COLORS[header_column]"
  fi
  if [[ -z "${FZX_COLORS[header_sorted]:-}" ]]; then
    _sgr=()
    fzx::_sgr_decor FZX_SORTED_HEADER_STYLE "${FZX_SORTED_HEADER_STYLE-bold underline}" _sgr || :
    fzx::_sgr_color FZX_SORTED_HEADER_COLOR "${FZX_SORTED_HEADER_COLOR-#00d7ff}" 38 _sgr
    fzx::_sgr_join _sgr 1 "FZX_COLORS[header_sorted]"
  fi
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
