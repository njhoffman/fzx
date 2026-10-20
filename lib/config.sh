#!/usr/bin/env bash
# config: source configuration layers in order; later layers override earlier ones.

# fzx::config_load [module_dir] [module]
fzx::config_load() {
  local module_dir="${1:-}" module="${2:-}" layer
  local layers=("$FZX_ROOT/config/defaults.sh" "$FZX_CONFIG_DIR/config.sh")
  [[ -n "$module_dir" ]] && layers+=("$module_dir/config.sh")
  [[ -n "$module" ]] && layers+=("$FZX_CONFIG_DIR/modules/$module/config.sh")

  for layer in "${layers[@]}"; do
    [[ -f "$layer" ]] || continue
    # shellcheck source=/dev/null
    source "$layer" || fzx::die 1 "config layer failed: $layer"
    fzx::log debug "config loaded $layer"
  done
}
