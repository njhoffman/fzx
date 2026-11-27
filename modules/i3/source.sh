#!/usr/bin/env bash
# i3 source (i3-msg's tree and workspaces, through jq). Modes from $FZX_MODE:
#   windows     "con id<TAB>display": every window of every workspace (docks left out): its workspace, class and
#               title, and marks for the focused, floating and urgent ones
#   workspaces  "name<TAB>display": the workspaces with their output, whether they show, and their windows
#   scratchpad  "con id<TAB>display": the windows on the scratchpad

# i3::tree_windows: "id US workspace US output US class US title US flags" every window, US \x1f, flags of f (focused),
# F (floating), u (urgent); the scratchpad's workspace is __i3_scratch
i3::tree_windows() {
  command i3-msg -t get_tree 2> /dev/null | command jq -r '
    .nodes[] as $o | $o.nodes[] | select(.type == "con") | .nodes[] | select(.type == "workspace") as $w
    | $w | .. | objects | select(.window != null and (.type == "con" or .type == "floating_con"))
    | [.id, $w.name, $o.name, (.window_properties.class // "?"), (.name // ""),
       ((if .focused then "f" else "" end) + (if (.floating // "" | test("on")) then "F" else "" end)
        + (if .urgent then "u" else "" end))]
    | map(tostring | gsub("[\u001f\t\n]"; " ")) | join("\u001f")'
}

# i3::workspaces: "name US output US num US flags US windows" a workspace (flags: v visible, f focused, u urgent)
i3::workspaces() {
  local -A count=()
  local id ws _
  while IFS=$'\x1f' read -r id ws _; do count[$ws]=$((${count[$ws]:-0} + 1)); done < <(i3::tree_windows)
  command i3-msg -t get_workspaces 2> /dev/null | command jq -r '.[] |
    [.name, .output, .num, ((if .visible then "v" else "" end) + (if .focused then "f" else "" end) + (if .urgent then "u" else "" end))]
    | map(tostring) | join("\u001f")' | while IFS=$'\x1f' read -r ws out num flags; do
    printf '%s\x1f%s\x1f%s\x1f%s\x1f%s\n' "$ws" "$out" "$num" "$flags" "${count[$ws]:-0}"
  done
}

# i3::source
i3::source() {
  local id ws out cls title flags num n mark c
  local cur=$'\e['"${FZX_COLORS[i3_focused]:-38;5;114}m" dim=$'\e['"${FZX_COLORS[i3_dim]:-38;5;244}m" urg=$'\e['"${FZX_COLORS[i3_urgent]:-38;5;203}m" r=$'\e[0m'
  [[ -n "${NO_COLOR:+x}" ]] && cur="" dim="" urg="" r=""
  case "${FZX_MODE:-windows}" in
    windows | scratchpad)
      # titles are other people's text (fzx::glyphs_plain, whole lines: the ids have none)
      # shellcheck disable=SC2119
      i3::tree_windows | while IFS=$'\x1f' read -r id ws out cls title flags; do
        if [[ "${FZX_MODE:-windows}" == scratchpad ]]; then [[ "$ws" == __i3_scratch ]] || continue
        else [[ "$ws" == __i3_scratch ]] && continue; fi
        mark=" " c=""
        [[ "$flags" == *F* ]] && mark="◇"
        [[ "$flags" == *f* ]] && mark="●" c="$cur"
        [[ "$flags" == *u* ]] && mark="!" c="$urg"
        [[ "$ws" == __i3_scratch ]] && ws=scratch out=""
        printf '%s\t%s%s %-8s%s %s%-6s%s %-16.16s %s\n' "$id" "$c" "$mark" "$ws" "$r" "$dim" "$out" "$r" "$cls" "$title"
      done | fzx::glyphs_plain
      ;;
    workspaces)
      i3::workspaces | while IFS=$'\x1f' read -r ws out num flags n; do
        [[ "$ws" == __i3_scratch ]] && continue
        mark=" " c=""
        [[ "$flags" == *v* ]] && mark="○"
        [[ "$flags" == *f* ]] && mark="●" c="$cur"
        [[ "$flags" == *u* ]] && mark="!" c="$urg"
        printf '%s\t%s%s %-12s%s %s%-6s%s %s\n' "$ws" "$c" "$mark" "$ws" "$r" "$dim" "$out" "$r" "$(fzx::plural "$n" window)"
      done
      ;;
    *)
      printf 'i3: unknown mode: %s\n' "$FZX_MODE" >&2
      return 2
      ;;
  esac
}

[[ "${BASH_SOURCE[0]}" == "$0" ]] && {
  source "$(dirname "${BASH_SOURCE[0]}")/../../lib/core.sh"
  fzx::require log config
  fzx::config_load "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" i3
  i3::source "$@"
}
