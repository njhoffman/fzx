#!/usr/bin/env bash
# tasks source: "id<TAB>project:task<TAB>display" per task, or per repository in projects mode. Modes from
# $FZX_MODE: selected (default: the tasks of the repository here, read now, then the ones picked with
# ctrl-t), repos (every task of the chosen projects), all (every task found), projects (the repositories
# with tasks; chosen ones marked). Every repository is scanned into $FZX_CACHE_DIR/tasks/index, kept for
# FZX_TASKS_TTL; picks and chosen projects live in $FZX_STATE_DIR/tasks/{selected,projects}.
# A task row's id is DIR|KIND|NAME.

tasks::index_file() { printf '%s/tasks/index' "$FZX_CACHE_DIR"; }
tasks::state_dir() { printf '%s/tasks' "$FZX_STATE_DIR"; }

# tasks::here: the repository the shell is in (its top level, resolved); fails outside one
tasks::here() {
  local top
  top="$(command git rev-parse --show-toplevel 2> /dev/null)" || return 1
  realpath -e -- "$top"
}

# tasks::repos: repository paths (ghq's and any under FZX_TASKS_ROOTS), resolved and deduplicated
tasks::repos() {
  local root
  {
    command -v ghq > /dev/null && command ghq list -p 2> /dev/null
    for root in "${FZX_TASKS_ROOTS[@]}"; do
      [[ -d "$root" ]] || continue
      find -L "$root" -mindepth 2 -maxdepth "$((${FZX_TASKS_DEPTH:-3} + 1))" -name .git -prune -printf '%h\n' 2> /dev/null
    done
  } | xargs -r -d '\n' realpath -e -- 2> /dev/null | awk '!seen[$0]++'
}

# tasks::makefile <dir>: the makefile make would read there
tasks::makefile() {
  local f
  for f in GNUmakefile makefile Makefile; do
    [[ -f "$1/$f" ]] && { printf '%s\n' "$1/$f"; return 0; }
  done
  return 1
}

# tasks::justfile <dir>
tasks::justfile() {
  local f
  for f in justfile Justfile .justfile; do
    [[ -f "$1/$f" ]] && { printf '%s\n' "$1/$f"; return 0; }
  done
  return 1
}

# tasks::taskfile <dir>
tasks::taskfile() {
  local f
  for f in Taskfile.yml Taskfile.yaml taskfile.yml taskfile.yaml; do
    [[ -f "$1/$f" ]] && { printf '%s\n' "$1/$f"; return 0; }
  done
  return 1
}

# tasks::gotask: the go-task binary (go-task, or a task that is go-task: taskwarrior is also called task);
# fails when there is none
tasks::gotask() {
  if command -v go-task > /dev/null; then
    printf 'go-task\n'
  elif command -v task > /dev/null && command task --version 2> /dev/null | grep -q '^Task version'; then
    printf 'task\n'
  else
    return 1
  fi
}

# tasks::scan <dir>: "dir<TAB>kind<TAB>name<TAB>description" per task the repository defines, in file order
tasks::scan() {
  local dir="${1%/}" f gotask
  {
    # make: explicit targets (not pattern rules, special .TARGETS or variable assignments); a "## text"
    # after the target, else a "## text" comment line right above it, is its description
    if f="$(tasks::makefile "$dir")"; then
      awk '
        /^##/ { doc = $0; sub(/^##+ */, "", doc); next }
        /^[A-Za-z0-9_][^:=#%$ \t]*( [^:=#%$ \t]+)*[ \t]*::?([^=]|$)/ {
          line = $0; d = ""
          if (match(line, /##+ */)) d = substr(line, RSTART + RLENGTH)
          if (d == "") d = doc
          split(line, parts, ":"); n = split(parts[1], names, " ")
          for (i = 1; i <= n; i++) if (!(names[i] in seen)) { seen[names[i]] = 1; print "make\t" names[i] "\t" d }
        }
        !/^##/ { doc = "" }' "$f"
    fi
    # just: public recipes with their doc comments
    if f="$(tasks::justfile "$dir")" && command -v just > /dev/null; then
      command just --justfile "$f" --working-directory "$dir" --dump --dump-format json 2> /dev/null |
        command jq -r '.recipes | to_entries | sort_by(.value.name) | .[].value | select(.private | not) | ["just", .name, (.doc // "")] | @tsv'
    fi
    # package.json scripts: the command is the description
    if [[ -f "$dir/package.json" ]]; then
      command jq -r '(.scripts // {}) | to_entries[] | ["npm", .key, (.value | tostring)] | @tsv' "$dir/package.json" 2> /dev/null
    fi
    if f="$(tasks::taskfile "$dir")" && gotask="$(tasks::gotask)"; then
      command "$gotask" --dir "$dir" --list-all --json 2> /dev/null | command jq -r '.tasks[] | ["task", .name, (.desc // "")] | @tsv'
    fi
    # cargo aliases and pdm, poe and hatch scripts, read with python's TOML parser
    if [[ -f "$dir/.cargo/config.toml" || -f "$dir/.cargo/config" || -f "$dir/pyproject.toml" ]] && command -v python3 > /dev/null; then
      python3 - "$dir" << 'PY' 2> /dev/null
import sys, tomllib, os
d = sys.argv[1]
def load(p):
    try:
        with open(p, "rb") as f:
            return tomllib.load(f)
    except Exception:
        return {}
def text(v):
    if isinstance(v, str):
        return v
    if isinstance(v, list):
        return " ".join(map(str, v))
    if isinstance(v, dict):
        return str(v.get("help") or v.get("cmd") or v.get("shell") or v.get("call") or " ".join(map(str, v.get("sequence", []))) or "")
    return ""
def out(kind, items):
    for k, v in items.items():
        if k.startswith("_"):
            continue
        print(kind, k, " ".join(text(v).split()), sep="\t")
for c in (".cargo/config.toml", ".cargo/config"):
    p = os.path.join(d, c)
    if os.path.isfile(p):
        out("cargo", load(p).get("alias", {}))
        break
p = os.path.join(d, "pyproject.toml")
if os.path.isfile(p):
    tool = load(p).get("tool", {})
    out("pdm", tool.get("pdm", {}).get("scripts", {}))
    out("poe", tool.get("poe", {}).get("tasks", {}))
    out("hatch", tool.get("hatch", {}).get("envs", {}).get("default", {}).get("scripts", {}))
PY
    fi
  } | awk -F'\t' -v dir="$dir" 'BEGIN { OFS = "\t" } $2 != "" { gsub(/[\r\n]/, " ", $3); print dir, $1, $2, $3 }'
}

# tasks::index: path of the index of every repository's tasks. The first time it is scanned while you wait;
# once older than FZX_TASKS_TTL, the old index is served and scanned again in the background (one scan at
# a time), so the next open has it.
tasks::index() {
  local file ttl mtime
  file="$(tasks::index_file)"
  fzx::parse_duration "${FZX_TASKS_TTL:-1h}" ttl || ttl=3600
  if [[ -f "$file" ]]; then
    mtime="$(stat -c %Y -- "$file")"
    # detached: it must not hold the source's stdout, which fzf reads until every writer closes it
    ((EPOCHSECONDS - mtime < ttl)) || (tasks::scan_all "$file" < /dev/null > /dev/null 2>&1 &)
  else
    tasks::scan_all "$file"
  fi
  printf '%s\n' "$file"
}

# tasks::scan_all <file>: scan every repository into the file, FZX_TASKS_JOBS at a time; skipped while
# another scan holds the lock
tasks::scan_all() {
  local file="$1" self
  mkdir -p -- "${file%/*}"
  exec {lock}> "$file.lock"
  flock -n "$lock" || return 0
  self="$(readlink -f "${BASH_SOURCE[0]}")"
  # each scan into its own file (scans sharing one stdout would interleave mid-line), then merged by
  # repository, each keeping its file order
  local parts="$file.$$.d"
  mkdir -p -- "$parts"
  tasks::repos | xargs -r -d '\n' -P "${FZX_TASKS_JOBS:-8}" -I{} "$self" --scan {} "$parts"
  find "$parts" -type f -exec cat -- {} + | sort -s -t $'\t' -k1,1 > "$file.$$" && mv -f -- "$file.$$" "$file"
  rm -rf -- "$parts"
  exec {lock}>&-
}

# tasks::rows <mode>: the rows of a task mode, "dir<TAB>kind<TAB>name<TAB>description<TAB>mark", mark
# "here" or "picked" (or empty)
tasks::rows() {
  local mode="$1" here="" index state
  state="$(tasks::state_dir)"
  here="$(tasks::here)" || here=""
  index="$(tasks::index)"
  {
    # the repository here, read now (the index may be an hour old); the index's rows of it are skipped
    [[ -n "$here" ]] && tasks::scan "$here" | sed 's/^/H\t/'
    awk -F'\t' -v here="$here" '$1 != here { print "I\t" $0 }' "$index"
  } | awk -F'\t' -v mode="$mode" -v here="$here" -v picked="$state/selected" -v chosen="$state/projects" '
      BEGIN {
        OFS = "\t"
        while ((getline line < picked) > 0) pick[line] = 1
        while ((getline line < chosen) > 0) proj[line] = 1
      }
      {
        key = $2 "\t" $3 "\t" $4
        mark = $2 == here ? "here" : (key in pick) ? "picked" : ""
        if (mode == "selected" && $1 != "H" && !(key in pick)) next
        if (mode == "repos" && !($2 in proj)) next
        print $2, $3, $4, $5, mark
      }'
}

# tasks::display: rows from tasks::rows -> "id<TAB>project:task<TAB>display"
tasks::display() {
  awk -F'\t' -v nocolor="${NO_COLOR+x}" -v proj="${FZX_COLORS[tasks_project]:-38;5;111}" -v name="${FZX_COLORS[tasks_name]:-1;38;5;255}" \
    -v markc="${FZX_COLORS[tasks_mark]:-38;5;114}" -v dim="${FZX_COLORS[dim]:-38;5;244}" '
    function c(code, text) { return nocolor != "" || text == "" ? text : "\033[" code "m" text "\033[0m" }
    {
      p = $1; sub(/.*\//, "", p)
      r++; id[r] = $1 "|" $2 "|" $3; label[r] = p ":" $3; kind[r] = $2; desc[r] = $4; mark[r] = $5; pl[r] = p
      if (length(label[r]) > w) w = length(label[r])
    }
    END {
      if (w > 48) w = 48
      for (i = 1; i <= r; i++) {
        m = mark[i] == "here" ? c(markc, "⌂") : mark[i] == "picked" ? c(markc, "●") : " "
        d = desc[i]; if (length(d) > 100) d = substr(d, 1, 99) "…"
        pad = w - length(label[i]); if (pad < 0) pad = 0
        printf "%s\t%s\t%s %s%s%s %s %s\n", id[i], label[i], m, c(proj, pl[i] ":"), c(name, substr(label[i], length(pl[i]) + 2)),
          sprintf("%" pad "s", ""), c(dim, sprintf("%-5s", kind[i])), c(dim, d)
      }
    }'
}

# tasks::projects: one row per repository with tasks: chosen mark, name, task counts by kind, path
tasks::projects() {
  local index chosen here
  index="$(tasks::index)"
  chosen="$(tasks::state_dir)/projects"
  here="$(tasks::here)" || here=""
  awk -F'\t' -v chosen="$chosen" -v here="$here" -v home="$HOME" -v nocolor="${NO_COLOR+x}" \
    -v proj="${FZX_COLORS[tasks_project]:-38;5;111}" -v markc="${FZX_COLORS[tasks_mark]:-38;5;114}" -v dim="${FZX_COLORS[dim]:-38;5;244}" '
    function c(code, text) { return nocolor != "" || text == "" ? text : "\033[" code "m" text "\033[0m" }
    BEGIN { while ((getline line < chosen) > 0) on[line] = 1 }
    !($1 in n) { order[++r] = $1 }
    { n[$1]++; k[$1, $2]++; if (!(($1, $2) in seen)) { seen[$1, $2] = 1; kinds[$1] = kinds[$1] " " $2 } }
    END {
      for (i = 1; i <= r; i++) {
        d = order[i]; p = d; sub(/.*\//, "", p)
        counts = ""; split(substr(kinds[d], 2), ks, " ")
        for (j = 1; j in ks; j++) counts = counts (counts == "" ? "" : ", ") k[d, ks[j]] " " ks[j]
        short = d; if (index(short, home "/") == 1) short = "~" substr(short, length(home) + 1)
        m = (d in on) ? c(markc, "●") : d == here ? c(markc, "⌂") : " "
        printf "%s\t%s\t%s %s %s %s\n", d, d, m, c(proj, sprintf("%-28s", p)), sprintf("%-28s", counts), c(dim, short)
      }
    }' "$index"
}

tasks::source() {
  local mode="${FZX_MODE:-selected}" out
  case "$mode" in
    selected | repos | all)
      out="$(tasks::rows "$mode" | tasks::display)"
      if [[ -n "$out" ]]; then
        printf '%s\n' "$out"
      elif [[ "$mode" == repos ]]; then
        printf -- '-\t-\tno projects chosen: choose them in the projects mode (enter or ctrl-t)\n'
      else
        printf -- '-\t-\tno tasks here and none picked: pick them with ctrl-t in the repos or all mode\n'
      fi
      ;;
    projects) tasks::projects ;;
    *)
      printf 'tasks: unknown mode: %s\n' "$mode" >&2
      return 2
      ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  [[ -n "${_FZX_CORE_LOADED:-}" ]] || source "$(dirname "${BASH_SOURCE[0]}")/../../lib/core.sh"
  if [[ "${1:-}" == --scan ]]; then
    # --scan DIR [OUTDIR]: into a file of its own in OUTDIR
    if [[ -n "${3:-}" ]]; then tasks::scan "$2" > "$(mktemp "$3/scan.XXXXXX")"; else tasks::scan "$2"; fi
  else
    tasks::source "$@"
  fi
fi
