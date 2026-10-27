#!/usr/bin/env bash
# ps source: one line per process, header first. PID is left-aligned so {1} works with any --delimiter.
# Mode from $FZX_MODE: user (default, own processes), all (every process), tree (forest).
# $FZX_SORT: cpu (default), mem, age, pid (ignored in tree, which keeps input order).
# $FZX_TOGGLES: "kernel" shows kernel threads (pid 2 and its children), hidden otherwise.

# ps::color <kernel 0|1>: ps's table -> aligned, colored rows (cool palette, after grc's conf.ps): pid bold
# purple, parent pid dim, your user blue, other users cyan, root red; %cpu and %mem by load (dim, green,
# white, red); rss as K/M/G; state by kind (running green, sleeping dim, disk wait red, zombie on red,
# stopped blue); the tty cyan; the command's name bold white after its dim directory, options blue, paths
# light grey, kernel threads cyan, the tree's branches dim. Kernel threads (pid 2 and its children) are
# dropped unless kernel is 1. The pid stays first and left-aligned ({1}); NO_COLOR leaves the escapes out.
ps::color() {
  awk -v kernel="$1" -v me="${USER:-$(id -un)}" -v nocolor="${NO_COLOR+x}" '
    function c(code, text) { return nocolor != "" || text ~ /^ *$/ ? text : "\033[" code "m" text "\033[0m" }
    function pad(text, w, right) { return right ? sprintf("%" w "s", text) : sprintf("%-" w "s", text) }
    function human(kb) {
      if (kb !~ /^[0-9]+$/) return kb
      if (kb < 1024) return kb "K"
      if (kb < 1048576) return sprintf("%.0fM", kb / 1024)
      return sprintf("%.1fG", kb / 1048576)
    }
    function load(v) { return v >= 50 ? "1;38;5;203" : v >= 10 ? "1;38;5;255" : v >= 1 ? "38;5;114" : "38;5;240" }
    function state(s,  k) {
      k = substr(s, 1, 1)
      return k == "R" ? "1;38;5;48" : k == "D" ? "1;38;5;203" : k == "Z" ? "1;38;5;255;48;5;124" : k == "T" || k == "t" ? "38;5;117" : k == "I" ? "38;5;240" : "38;5;244"
    }
    function command(a,  lead, n, i, w, words, first, dir, name, out) {
      # the forest drawing ("  \_ ") before the command
      match(a, /^[ |\\_]*/); lead = substr(a, 1, RLENGTH); a = substr(a, RLENGTH + 1)
      if (a ~ /^\[.*\]$/) return c("38;5;240", lead) c("38;5;81", a)
      n = split(a, words, " ")
      first = words[1]; name = first; dir = ""
      if (first ~ /\//) { name = first; sub(/.*\//, "", name); dir = substr(first, 1, length(first) - length(name)) }
      out = c("38;5;240", lead) c("38;5;244", dir) c("1;38;5;255", name)
      for (i = 2; i <= n; i++) {
        w = words[i]
        out = out " " (w ~ /^-/ ? c("38;5;110", w) : w ~ /\// ? c("38;5;252", w) : c("38;5;250", w))
      }
      return out
    }
    NR == 1 { at = index($0, "COMMAND"); head = $0; next }
    {
      split(substr($0, 1, at - 1), f, " ")
      if (!kernel && (f[1] == 2 || f[2] == 2)) next
      f[6] = human(f[6])
      n++
      for (i = 1; i <= 9; i++) { row[n, i] = f[i]; if (length(f[i]) > w[i]) w[i] = length(f[i]) }
      args[n] = substr($0, at)
    }
    END {
      split("PID PPID USER %CPU %MEM RSS ELAPSED STAT TT", h, " ")
      right[2] = right[4] = right[5] = right[6] = right[7] = 1
      line = ""
      for (i = 1; i <= 9; i++) { if (length(h[i]) > w[i]) w[i] = length(h[i]); line = line pad(h[i], w[i], right[i]) " " }
      print c("1;38;5;245", line "COMMAND")
      for (r = 1; r <= n; r++) {
        u = row[r, 3]
        line = c("1;38;5;141", pad(row[r, 1], w[1])) " " c("38;5;244", pad(row[r, 2], w[2], 1)) " "
        line = line c(u == "root" ? "1;38;5;203" : u == me ? "38;5;110" : "38;5;81", pad(u, w[3])) " "
        line = line c(load(row[r, 4]), pad(row[r, 4], w[4], 1)) " " c(load(row[r, 5]), pad(row[r, 5], w[5], 1)) " "
        line = line c("38;5;152", pad(row[r, 6], w[6], 1)) " " c("38;5;245", pad(row[r, 7], w[7], 1)) " "
        line = line c(state(row[r, 8]), pad(row[r, 8], w[8])) " " c(row[r, 9] == "?" ? "38;5;240" : "38;5;117", pad(row[r, 9], w[9])) " "
        print line command(args[r])
      }
    }'
}

# ps::source [--ppid PID]   only the direct children of PID
ps::source() {
  local mode="${FZX_MODE:-user}" scope sort ppid="" kernel=0
  case "${FZX_SORT:-cpu}" in
    cpu) sort=(--sort=-%cpu) ;;
    mem) sort=(--sort=-%mem) ;;
    age) sort=(--sort=etimes) ;;
    pid) sort=(--sort=pid) ;;
    *)
      printf 'ps: unknown sort: %s\n' "$FZX_SORT" >&2
      return 2
      ;;
  esac
  [[ " ${FZX_TOGGLES:-} " == *" kernel "* ]] && kernel=1
  while (($#)); do
    case "$1" in
      --ppid)
        [[ "${2:-}" =~ ^[0-9]+$ ]] || {
          printf 'ps: --ppid needs a pid, got: %s\n' "${2:-}" >&2
          return 2
        }
        ppid="$2"
        shift
        ;;
      *)
        printf 'ps: unknown argument: %s\n' "$1" >&2
        return 2
        ;;
    esac
    shift
  done

  case "$mode" in
    user) scope=(--user="${USER:-$(id -un)}") ;;
    all) scope=(-e) ;;
    tree) scope=(-e) sort=(--forest) ;;
    *)
      printf 'ps: unknown mode: %s\n' "$mode" >&2
      return 2
      ;;
  esac
  [[ -n "$ppid" ]] && scope=(--ppid "$ppid")

  # ps exits 1 both on errors and when nothing matches; only a match-less run still prints the header
  local out rc
  out="$(command ps "${scope[@]}" -o pid,ppid,user,%cpu,%mem,rss,etime,stat,tty,args "${sort[@]}")"
  rc=$?
  if ((rc != 0)) && [[ "$out" != *PID* ]]; then
    return "$rc"
  fi
  printf '%s\n' "$out" | ps::color "$kernel"
}

[[ "${BASH_SOURCE[0]}" == "$0" ]] && ps::source "$@"
