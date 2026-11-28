#!/usr/bin/env bash
# colors preview: a swatch the preview's width, sample text in the color on the terminal's background, a
# dark and a light one, and the color's values and codes

# shellcheck source=./source.sh
source "$(dirname "${BASH_SOURCE[0]}")/source.sh"

# colors::gradient: a rainbow in true color, 1 column per step: banding means the terminal (or tmux) maps it
# to the 256 palette, and the names mode's colors are approximations
colors::gradient() {
  local cols="${FZF_PREVIEW_COLUMNS:-60}"
  awk -v w="$((cols - 12))" -v D=$'\e[38;5;244m' -v R=$'\e[0m' 'BEGIN {
    if (w < 8) exit
    printf "%strue color%s  ", D, R
    for (i = 0; i < w; i++) {
      h = i * 6 / w; x = int(255 * (1 - (h % 2 - 1 < 0 ? 1 - h % 2 : h % 2 - 1)))
      if (h < 1) { r = 255; g = x; b = 0 } else if (h < 2) { r = x; g = 255; b = 0 } else if (h < 3) { r = 0; g = 255; b = x }
      else if (h < 4) { r = 0; g = x; b = 255 } else if (h < 5) { r = x; g = 0; b = 255 } else { r = 255; g = 0; b = x }
      printf "\033[48;2;%d;%d;%dm \033[0m", r, g, b }
    printf "\n" }'
}

# colors::theme_preview <id> <value> <sgr>: a setting: what it colors, its value, a sample in it, the keys
colors::theme_preview() {
  local id="$1" value="$2" sgr="$3" key="${1#*:}" desc="" parent="" cols="${FZF_PREVIEW_COLUMNS:-60}" line
  local D=$'\e[38;5;244m' R=$'\e[0m' text="The quick brown fox jumps over the lazy dog"
  if [[ "$id" == fzf:* ]]; then
    IFS=$'\t' read -r _ parent desc < <(awk -F'\t' -v k="$key" '$1 == k' <<< "$COLORS_FZF_KEYS")
    printf '%sfzf --color%s %s\n%s\n' "$D" "$R" "$key" "$desc"
    [[ "$parent" != - && -n "$parent" ]] && printf '%swhen unset it is drawn as %s%s\n' "$D" "$parent" "$R"
  else
    printf '%sfzx%s FZX_COLORS[%s]\n' "$D" "$R" "$key"
  fi
  printf '\n%svalue%s   %s\n%ssgr%s     %s\n\n' "$D" "$R" "${value:-(not set)}" "$D" "$R" "${sgr:-}"
  if [[ -n "$sgr" ]]; then
    if [[ "$id" == fzf:* ]] && colors::_is_bg "$key"; then
      printf -v line '%*s' "$cols" ''
      for _ in 1 2 3; do printf '\e[%sm%s\e[0m\n' "$sgr" "$line"; done
      printf '\e[%sm  %s\e[0m\n\n' "$sgr" "$text"
    else
      printf '  \e[%sm%s\e[0m\n' "$sgr" "$text"
      printf '  \e[%s;48;5;236m %s \e[0m\n' "$sgr" "$text"
      printf '  \e[%s;48;5;254m %s \e[0m\n\n' "$sgr" "$text"
    fi
  fi
  printf '%senter%s change it  %salt-x%s reset  %salt-k%s save  %salt-p%s sample\n' "$D" "$R" "$D" "$R" "$D" "$R" "$D" "$R"
}

# colors::preset_preview <slug>: a preset: its 16 colors, a small fzf drawn in them, the keys it sets
colors::preset_preview() {
  local row slug name author key hex i w="${FZF_PREVIEW_COLUMNS:-60}" D=$'\e[38;5;244m' R=$'\e[0m'
  local -a c=()
  local -A v=()
  colors::preset_row "$1" row || return 0
  IFS=$'\t' read -r slug name author _ <<< "$row"
  IFS=$'\t' read -r -a c <<< "$(cut -f4- <<< "$row")"
  while IFS=$'\t' read -r key hex; do v[$key]="$hex"; done < <(colors::preset_items "$slug")
  # one color as SGR: fg or bg (38/48) of a key's value
  _sgr() { local h="${v[$2]:-${2}}"; h="${h#\#}"; printf '%s;2;%d;%d;%d' "$1" "$((16#${h:0:2}))" "$((16#${h:2:2}))" "$((16#${h:4:2}))"; }
  printf '%s\n%s%s%s\n\n' "$name" "$D" "$author" "$R"
  for i in 0 8; do
    local j line=""
    for ((j = i; j < i + 8; j++)); do line+=$'\e['"$(_sgr 48 "${c[j]}")m    $R "; done
    printf ' %s\n' "$line"
    line=""
    for ((j = i; j < i + 8; j++)); do printf -v hex '%02X' "$j" && line+="$D  $hex $R"; done
    printf ' %s\n' "$line"
  done
  # the sample: lines w-2 wide on bg, each part in its key's colors
  ((w > 46)) && w=46
  local bg fill B
  bg=$'\e['"$(_sgr 48 bg)m"
  B=$'\e['"$(_sgr 38 border)m"
  _line() {
    # _line <text with escapes> <visible width>: padded to the sample's width, on bg, inside the border
    printf ' %s%s│%s%s%*s%s%s│%s\n' "$bg" "$B" "$bg" "$1" "$((w - 4 - $2))" '' "$bg" "$B" "$R"
  }
  printf -v fill '%*s' "$((w - 4))" ''
  printf '\n %s%s╭%s╮%s\n' "$bg" "$B" "${fill// /─}" "$R"
  _line $'\e['"$(_sgr 38 prompt)m> "$'\e['"$(_sgr 38 query)man"$'\e['"$(_sgr 38 info)m  3/15"$'\e['"$(_sgr 38 separator)m ───" 14
  _line $'\e['"$(_sgr 38 header)mthe header" 10
  _line $'\e['"$(_sgr 48 bg+);$(_sgr 38 pointer)m▌"$'\e['"$(_sgr 38 fg+)m b"$'\e['"$(_sgr 38 hl+)man"$'\e['"$(_sgr 38 fg+)mana bread  $bg" 16
  _line $'\e['"$(_sgr 48 gutter);$(_sgr 38 marker)m┃"$'\e['"$(_sgr 48 selected-bg);$(_sgr 38 selected-fg)m c"$'\e['"$(_sgr 38 selected-hl)man"$'\e['"$(_sgr 38 selected-fg)mtaloupe  $bg" 14
  _line $'\e['"$(_sgr 48 gutter)m $bg"$'\e['"$(_sgr 38 fg)m or"$'\e['"$(_sgr 38 hl)man"$'\e['"$(_sgr 38 fg)mge marmalade" 18
  _line $'\e['"$(_sgr 48 gutter)m $bg"$'\e['"$(_sgr 38 fg)m p"$'\e['"$(_sgr 38 hl)ma"$'\e['"$(_sgr 38 fg)mp"$'\e['"$(_sgr 38 hl)ma"$'\e['"$(_sgr 38 fg)mya salsa" 14
  _line $'\e['"$(_sgr 38 spinner)m⠋ "$'\e['"$(_sgr 38 footer)mthe footer" 12
  printf ' %s%s╰%s╯%s\n\n' "$bg" "$B" "${fill// /─}" "$R"
  printf '%sit sets%s\n' "$D" "$R"
  while IFS=$'\t' read -r key _; do
    hex="${v[$key]}"
    if colors::_is_bg "$key"; then
      printf '  \e[%sm      %s %-12s %s\n' "$(_sgr 48 "$key")" "$R" "$key" "$hex"
    else
      printf '  \e[%sm Abc  %s %-12s %s\n' "$(_sgr 38 "$key")" "$R" "$key" "$hex"
    fi
  done < <(colors::preset_items "$slug")
  printf '\n%senter: set these (pending until alt-k saves); the theme'"'"'s other fzf keys are reset%s\n' "$D" "$R"
}

# colors::preview <id> <hex> <sgr> (theme: <id> <value> <sgr>)
colors::preview() {
  local id="${1:-}" hex="${2:-}" sgr="${3:-}" cols="${FZF_PREVIEW_COLUMNS:-60}" bg="" line rgb name hsl
  case "${FZX_MODE:-}" in
    theme) colors::theme_preview "$id" "$hex" "$sgr" && return ;;
    presets) colors::preset_preview "$id" && return ;;
  esac
  local fg_re='(^|;)38;(5;[0-9]+|2;[0-9]+;[0-9]+;[0-9]+)($|;)'
  local D=$'\e[38;5;244m' R=$'\e[0m' text="The quick brown fox jumps over the lazy dog"
  [[ -n "$id" && -n "$sgr" ]] || return 0
  # the background twin of a foreground color: 38;5;N -> 48;5;N, 38;2;R;G;B -> 48;2;R;G;B
  [[ "$sgr" =~ $fg_re ]] && bg="48;${BASH_REMATCH[2]}"
  # the 16: the background is the code + 10
  [[ "${FZX_MODE:-}" == 16 && "$sgr" =~ ^(3|9)[0-7]$ ]] && bg="$((sgr + 10))"
  if [[ -n "$bg" ]]; then
    printf -v line '%*s' "$cols" ''
    for _ in 1 2 3 4; do printf '\e[%sm%s\e[0m\n' "$bg" "$line"; done
  fi
  printf '\n  \e[%sm%s\e[0m\n' "$sgr" "$text"
  printf '  \e[%s;48;5;236m %s \e[0m\n' "$sgr" "$text"
  printf '  \e[%s;48;5;254m %s \e[0m\n' "$sgr" "$text"
  printf '  \e[1;%sm%s\e[0m\n\n' "$sgr" "$text"
  case "${FZX_MODE:-256}" in
    256 | pick)
      IFS=$'\t' read -r _ name _ rgb hsl < <(awk -F'\t' -v n="$id" '$1 == n' "$COLORS_DIR/xterm-256.tsv")
      printf '%snumber%s  %s\n%sname%s    %s\n%shex%s     %s\n%srgb%s     %s\n%shsl%s     %s\n' \
        "$D" "$R" "$id" "$D" "$R" "$name" "$D" "$R" "$hex" "$D" "$R" "${rgb#rgb}" "$D" "$R" "${hsl#hsl}"
      ;;
    16)
      local a
      printf '%scode%s    %s (%s, 256-color index %s)\n%sbg%s      %s\n\n' "$D" "$R" "$id" \
        "$([[ "$id" == 9* ]] && echo bright || echo normal)" "$(( id < 90 ? id - 30 : id - 82 ))" "$D" "$R" "$bg"
      for a in "0:normal" "1:bold" "2:faint" "3:italic" "4:underline" "7:invert" "9:strike"; do
        printf '  \e[%s;%sm%-10s\e[0m %s\\e[%s;%sm%s\n' "${a%%:*}" "$sgr" "${a#*:}" "$D" "${a%%:*}" "$sgr" "$R"
      done
      printf '\n'
      ;;
    names)
      rgb="${sgr#38;2;}"
      printf '%sname%s    %s\n%shex%s     %s\n%srgb%s     (%s)\n' "$D" "$R" "$id" "$D" "$R" "$hex" "$D" "$R" "${rgb//;/,}"
      awk -v rgb="$rgb" -v D="$D" -v R="$R" "$COLORS_AWK_PALETTE"'
        BEGIN { palette(); split(rgb, c, ";"); n = nearest(c[1], c[2], c[3])
          printf "%snearest%s \033[48;5;%dm    \033[0m %d (%d,%d,%d)\n", D, R, n, n, pr[n], pg[n], pb[n] }'
      colors::gradient
      ;;
    fzx) printf '%skey%s     FZX_COLORS[%s]\n%svalue%s   %s\n' "$D" "$R" "$id" "$D" "$R" "$sgr" ;;
  esac
  printf '%ssgr%s     %s\n%sescape%s  \\e[%sm%s\n' "$D" "$R" "$sgr" "$D" "$R" "$sgr" "${bg:+  ${D}background$R \\e[${bg}m}"
}

[[ "${BASH_SOURCE[0]}" == "$0" ]] && colors::preview "$@"
