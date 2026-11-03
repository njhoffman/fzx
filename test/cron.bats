#!/usr/bin/env bats
# the cron module against fixture crontabs, a stub crontab and a stub systemd-analyze (fixed times); one
# test hands every expression the parser makes to the real systemd-analyze

load test_helper

CRON="$(readlink -f "$BATS_TEST_DIRNAME/../modules/cron")"
# 2026-01-01 00:00:00 UTC
NOW=1767225600

setup() {
  setup_fzx
  export NO_COLOR=1 FZX_ICONS=none TZ=UTC FZX_CRON_NOW="$NOW"
  STUBS="$BATS_TEST_TMPDIR/stubs"
  mkdir -p "$STUBS" "$BATS_TEST_TMPDIR/etc/cron.d" "$BATS_TEST_TMPDIR/spool" "$BATS_TEST_TMPDIR/etc/cron.daily"
  # crontab: -l prints the fixture (none: exit 1), - replaces it, -e is logged; -u USER: the spool's file
  cat > "$STUBS/crontab" << 'STUB'
#!/usr/bin/env bash
if [[ "$1" == -u ]]; then
  f="$BATS_TEST_TMPDIR/spool-cron/$2"
  case "$3" in
    -l) cat "$f" ;;
    -) cat > "$f" ;;
    *) echo "crontab -u $2 $3" >> "$BATS_TEST_TMPDIR/calls" ;;
  esac
  exit
fi
case "$1" in
  -l) [[ -f "$BATS_TEST_TMPDIR/crontab" ]] || { echo "no crontab for $USER" >&2; exit 1; }; cat "$BATS_TEST_TMPDIR/crontab" ;;
  -) cat > "$BATS_TEST_TMPDIR/crontab" ;;
  *) echo "crontab $*" >> "$BATS_TEST_TMPDIR/calls" ;;
esac
STUB
  # systemd-analyze: each expression's next run from calendar.tsv (EXPR<TAB>UTC time), else never; with
  # --iterations=N, N runs a day apart; an expression named "bad" fails the call as the real one does
  cat > "$STUBS/systemd-analyze" << 'STUB'
#!/usr/bin/env bash
shift
n="${1#--iterations=}"; shift
rc=0
for e; do
  [[ "$e" == bad ]] && { echo "Failed to parse calendar specification '$e'" >&2; rc=1; continue; }
  echo "Normalized form: $e"
  t="$(awk -F '\t' -v e="$e" '$1 == e { print $2 }' "$BATS_TEST_TMPDIR/calendar.tsv")"
  if [[ -z "$t" ]]; then echo "    Next elapse: never"; continue; fi
  for ((i = 0; i < n; i++)); do
    u="$(date -u -d "@$(($(date -u -d "$t UTC" +%s) + i * 86400))" '+%a %Y-%m-%d %H:%M:%S UTC')"
    ((i)) && echo "   Iteration #$((i + 1)): $u" || echo "    Next elapse: $u"
    echo "       (in UTC): $u"
  done
  echo
done
exit "$rc"
STUB
  cat > "$STUBS/sudoedit" << 'STUB'
#!/usr/bin/env bash
echo "sudoedit $* SUDO_EDITOR=$SUDO_EDITOR" >> "$BATS_TEST_TMPDIR/calls"
STUB
  # sudo: -n fails when $BATS_TEST_TMPDIR/nosudo exists; -u USER is logged; runs the command as is
  cat > "$STUBS/sudo" << 'STUB'
#!/usr/bin/env bash
while [[ "$1" == -* ]]; do
  case "$1" in
    -n) [[ -f "$BATS_TEST_TMPDIR/nosudo" ]] && { echo "sudo: a password is required" >&2; exit 1; } ;;
    -u) echo "sudo -u $2" >> "$BATS_TEST_TMPDIR/calls"; shift ;;
  esac
  shift
done
[[ "$1" == true ]] || echo "sudo $*" >> "$BATS_TEST_TMPDIR/calls"
exec "$@"
STUB
  printf '#!/usr/bin/env bash\necho "anacron $*" >> "%s/calls"\n' "$BATS_TEST_TMPDIR" > "$STUBS/anacron"
  chmod +x "$STUBS"/*
  export PATH="$STUBS:$PATH"
  cat > "$BATS_TEST_TMPDIR/crontab" << 'TAB'
# m h  dom mon dow   command
MAILTO=me@example.com
*/15 * * * * echo quarter
0 9 * * mon-fri echo weekdays
0 0 1,15 * 5 echo either
@reboot echo boot
#30 2 * * * echo off
61 * * * * echo broken
5 4 * jan,jul 7 cat %first\%%second
TAB
  printf 'SHELL=/bin/sh\n17 * * * * root cd / && run-parts /etc/cron.hourly\n' > "$BATS_TEST_TMPDIR/etc/crontab"
  printf '@weekly  backup  /usr/bin/backup --all\n' > "$BATS_TEST_TMPDIR/etc/cron.d/backup"
  printf '0 0 * * * root never-read\n' > "$BATS_TEST_TMPDIR/etc/cron.d/backup.dpkg-old"
  printf '1\t5\tcron.daily\trun-parts --report %s/etc/cron.daily\n@monthly\t15\tcron.monthly\trun-parts /etc/cron.monthly\n' \
    "$BATS_TEST_TMPDIR" > "$BATS_TEST_TMPDIR/etc/anacrontab"
  # cron.daily last ran 2025-12-31 08:00 UTC: next on 2026-01-01 00:00, due now
  touch -d '2025-12-31 08:00 UTC' "$BATS_TEST_TMPDIR/spool/cron.daily"
  printf '#!/bin/sh\nlogrotate /etc/logrotate.conf\n' > "$BATS_TEST_TMPDIR/etc/cron.daily/logrotate"
  chmod +x "$BATS_TEST_TMPDIR/etc/cron.daily/logrotate"
  printf '#!/bin/sh\n' > "$BATS_TEST_TMPDIR/etc/cron.daily/logrotate.dpkg-new"
  printf '#!/bin/sh\n' > "$BATS_TEST_TMPDIR/etc/cron.daily/manual"
  export FZX_CRON_SYSTEM_FILES="$BATS_TEST_TMPDIR/etc/crontab $BATS_TEST_TMPDIR/etc/cron.d"
  export FZX_CRON_ANACRONTAB="$BATS_TEST_TMPDIR/etc/anacrontab" FZX_CRON_ANACRON_SPOOL="$BATS_TEST_TMPDIR/spool"
  export FZX_CRON_SCRIPT_DIRS="$BATS_TEST_TMPDIR/etc/cron.daily $BATS_TEST_TMPDIR/etc/cron.none"
  # every user's crontab: only yours, which is read through crontab -l instead
  mkdir -p "$BATS_TEST_TMPDIR/spool-cron"
  printf '0 0 * * * never-listed\n' > "$BATS_TEST_TMPDIR/spool-cron/${USER:-$(id -un)}"
  export FZX_CRON_SPOOL_DIR="$BATS_TEST_TMPDIR/spool-cron" FZX_CRON_HONORS_TZ=0
  printf '%s\t%s\n' \
    '*-*-* *:0,15,30,45:00' '2026-01-01 00:15:00' \
    'Mon,Tue,Wed,Thu,Fri *-*-* 9:0:00' '2026-01-01 09:00:00' \
    '*-*-1,15 0:0:00' '2026-01-15 00:00:00' \
    'Fri *-*-* 0:0:00' '2026-01-02 00:00:00' \
    '*-*-* *:17:00' '2026-01-01 00:17:00' \
    'Sun *-*-* 0:0:00' '2026-01-04 00:00:00' \
    > "$BATS_TEST_TMPDIR/calendar.tsv"
}

src() { FZX_MODE="$1" "$CRON/source.sh"; }
# (the scripts end in their run guard, false when sourced)
parse() { source "$CRON/source.sh" || :; cron::_parse "$@"; }

@test "parse: schedules into OnCalendar expressions; names, steps, ranges, 7 as Sunday, @ shortcuts" {
  run parse user - < "$BATS_TEST_TMPDIR/crontab"
  [ "$status" -eq 0 ]
  [ "$(cut -f1,6,7,8 <<< "$output" | tr '\t' '|')" = "user:-:3|*-*-* *:0,15,30,45:00||
user:-:4|Mon,Tue,Wed,Thu,Fri *-*-* 9:0:00||
user:-:5|*-*-1,15 0:0:00|Fri *-*-* 0:0:00|
user:-:6|||reboot
user:-:7|*-*-* 2:30:00||disabled
user:-:8|||invalid
user:-:9|Sun *-1,7-* 4:5:00||" ]
  # the user field of system crontabs; anacron's period, delay and job
  run parse system /etc/cron.d/backup < "$BATS_TEST_TMPDIR/etc/cron.d/backup"
  [ "$(cut -f3,4,5,6 <<< "$output" | tr '\t' '|')" = "backup|@weekly|/usr/bin/backup --all|Sun *-*-* 0:0:00" ]
  run parse anacron /etc/anacrontab < "$BATS_TEST_TMPDIR/etc/anacrontab"
  [ "$(cut -f1,4,8 <<< "${lines[0]}" | tr '\t' '|')" = "anacron:/etc/anacrontab:1|1|anacron:1:5:cron.daily" ]
  [ "$(cut -f4,8 <<< "${lines[1]}" | tr '\t' '|')" = "@monthly|anacron:@monthly:15:cron.monthly" ]
}

@test "parse: the real systemd-analyze takes every expression (skipped without it)" {
  command -v /usr/bin/systemd-analyze > /dev/null || skip "no systemd-analyze"
  printf '%s\n' '*/7 1-5,22 */2 2-11/3 sat,sun echo a' '0 12 29 2 * echo b' '30 6 * * 1-7 echo c' |
    parse user - | cut -f6,7 | tr '\t' '\n' | grep . > "$BATS_TEST_TMPDIR/exprs"
  mapfile -t exprs < "$BATS_TEST_TMPDIR/exprs"
  [ "${#exprs[@]}" -eq 3 ]
  run /usr/bin/systemd-analyze calendar "${exprs[@]}"
  [ "$status" -eq 0 ]
}

@test "all: next run first, relative; disabled, at boot and invalid last; dom or dow takes the earlier" {
  run src all
  [ "$status" -eq 0 ]
  # due anacron jobs (yesterday's run; one never run) come first
  [ "$(cut -f2 <<< "$output" | head -7)" = "run-parts --report $BATS_TEST_TMPDIR/etc/cron.daily
run-parts /etc/cron.monthly
echo quarter
cd / && run-parts /etc/cron.hourly
echo weekdays
echo either
/usr/bin/backup --all" ]
  [[ "${lines[2]}" == $'user:-:3\techo quarter\tin 15m        */15 * * * *        '"$USER"* ]]
  [[ "${lines[2]}" == *"  crontab:3" ]]
  [[ "${lines[3]}" == *$'\tin 17m        17 * * * *          root      cd / && run-parts /etc/cron.hourly  '"$BATS_TEST_TMPDIR/etc/crontab:2" ]]
  [[ "${lines[0]}" == *$'\tdue           every 1d            root  '* ]]
  # the 1st and 15th, or a Friday: Friday the 2nd
  [[ "${lines[5]}" == *$'\tin 1d 0h      0 0 1,15 * 5'* ]]
  [[ "$output" == *$'\tnever         5 4 * jan,jul 7     '* ]]
  [[ "$output" == *$'\tat boot       @reboot'* && "$output" == *$'\tdisabled      30 2 * * *'* && "$output" == *$'\tinvalid       61 * * * *'* ]]
  # a cron.d name with a dot is skipped, as cron skips it
  [[ "$output" != *never-read* ]]
}

@test "a header row (FZX_SORTED_SHOW=header) over the entries, next marked; by file nothing" {
  export FZX_SORTED_SHOW=header FZX_SORT_HEADER=1 FZX_SORTED_ARROWS='^ v'
  run "$CRON/source.sh"
  [ "${lines[0]}" = $'\t\tNEXT^         SCHEDULE            USER      COMMAND' ]
  header_aligned 2 "${lines[0]}" SCHEDULE "${lines[1]}" "$(cut -f3 <<< "${lines[1]}" | awk -F'  +' '{ print $2 }')"
  header_aligned 2 "${lines[0]}" COMMAND "${lines[1]}" "$(cut -f3 <<< "${lines[1]}" | awk -F'  +' '{ print $4 }')"
  FZX_SORT=file run "$CRON/source.sh"
  [ "${lines[0]}" = $'\t\tNEXT          SCHEDULE            USER      COMMAND' ]
}

@test "user, system and the file sort; no crontab; an expression systemd-analyze rejects only loses its own time" {
  run src user
  [ "${#lines[@]}" -eq 7 ]
  [[ "$output" != *backup* ]]
  run src system
  [ "${#lines[@]}" -eq 4 ]
  [[ "$output" != *quarter* ]]
  FZX_SORT=file run src all
  # your crontab ("-") first, then the files by path, each in line order
  [ "$(cut -f1 <<< "$output" | sed -n '1p;7,9p' | tr '\n' ' ')" = "user:-:3 user:-:9 anacron:$BATS_TEST_TMPDIR/etc/anacrontab:1 anacron:$BATS_TEST_TMPDIR/etc/anacrontab:2 " ]
  rm "$BATS_TEST_TMPDIR/crontab"
  run src user
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  FZX_MODE=bogus run "$CRON/source.sh"
  [ "$status" -eq 2 ]
}

@test "the fallback: a failing systemd-analyze call is asked one expression at a time" {
  source "$CRON/source.sh" || :
  printf 'id1\tuser\tme\ts\tc\t*-*-* *:17:00\t\t\nid2\tuser\tme\ts\tc\tbad\t\t\n' > "$BATS_TEST_TMPDIR/recs"
  run cron::_next "$BATS_TEST_TMPDIR/recs"
  [ "$(cut -f1,9 <<< "$output")" = "id1	1767226620
id2	" ]
}

@test "scripts: each with its directory's next run (anacron's job first); skipped names and modes marked" {
  run src scripts
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 3 ]
  [[ "${lines[0]}" == "script:$BATS_TEST_TMPDIR/etc/cron.daily/logrotate:0"$'\t'"$BATS_TEST_TMPDIR/etc/cron.daily/logrotate"$'\tdue           daily               logrotate  '* ]]
  [[ "${lines[1]}" == *"logrotate.dpkg-new  (skipped: run-parts ignores the name)" ]]
  [[ "${lines[2]}" == *"manual  (not executable: skipped)" ]]
}

@test "preview: an entry's command, schedule, user, file and next runs; anacron; a script; disabled; gone" {
  run "$CRON/preview.sh" user:-:3
  [ "${lines[0]}" = "echo quarter" ]
  [[ "$output" == *"schedule  */15 * * * *"* && "$output" == *"file      your crontab (crontab -e):3"* ]]
  [[ "$output" == *$'next runs\n  Thu 2026-01-01 00:15\n  Fri 2026-01-02 00:15'* ]]
  run "$CRON/preview.sh" user:-:5
  [[ "$output" == *"cron runs on either"* ]]
  run "$CRON/preview.sh" "anacron:$BATS_TEST_TMPDIR/etc/anacrontab:1"
  [[ "$output" == *"period    every day"* && "$output" == *"delay     5 minutes"* && "$output" == *"last run  Wed 2025-12-31 08:00"* ]]
  run "$CRON/preview.sh" user:-:7
  [[ "$output" == *"disabled: commented out"* ]]
  run "$CRON/preview.sh" "script:$BATS_TEST_TMPDIR/etc/cron.daily/logrotate.dpkg-new:0"
  [[ "$output" == *"skipped: run-parts ignores names"* && "$output" == *"skipped: not executable"* ]]
  run "$CRON/preview.sh" user:-:99
  [ "$output" = "the entry is no longer at -:99" ]
}

@test "preview: the next runs come out sorted and merged across both expressions" {
  run "$CRON/preview.sh" user:-:5
  [[ "$output" == *$'next runs\n  Fri 2026-01-02 00:00\n  Sat 2026-01-03 00:00\n  Sun 2026-01-04 00:00\n  Mon 2026-01-05 00:00\n  Tue 2026-01-06 00:00'* ]]
}

@test "actions: disable comments your entry out and back in; a line that is not an entry is left" {
  "$CRON/actions.sh" disable user:-:3
  [ "$(sed -n 3p "$BATS_TEST_TMPDIR/crontab")" = "#*/15 * * * * echo quarter" ]
  "$CRON/actions.sh" disable user:-:3 user:-:7
  [ "$(sed -n 3p "$BATS_TEST_TMPDIR/crontab")" = "*/15 * * * * echo quarter" ]
  [ "$(sed -n 7p "$BATS_TEST_TMPDIR/crontab")" = "30 2 * * * echo off" ]
  run "$CRON/actions.sh" disable user:-:1
  [ "$status" -eq 1 ]
  [ "$(sed -n 1p "$BATS_TEST_TMPDIR/crontab")" = "# m h  dom mon dow   command" ]
}

@test "actions: disable system entries, anacron jobs and scripts through a cached sudo; without one a hint" {
  local tab="$BATS_TEST_TMPDIR/etc/crontab" ana="$BATS_TEST_TMPDIR/etc/anacrontab" sc="$BATS_TEST_TMPDIR/etc/cron.daily/logrotate"
  "$CRON/actions.sh" disable "system:$tab:2" "anacron:$ana:2" "script:$sc:0"
  [ "$(sed -n 2p "$tab")" = "#17 * * * * root cd / && run-parts /etc/cron.hourly" ]
  [[ "$(sed -n 2p "$ana")" == "#@monthly"* ]]
  [ ! -x "$sc" ]
  grep -q "^sudo sed -i 2s/^/#/ $tab" "$BATS_TEST_TMPDIR/calls"
  # listed as disabled now, and back
  run src system
  [[ "$output" == *"disabled      17 * * * *"* && "$output" == *"disabled      @monthly"* ]]
  "$CRON/actions.sh" disable "system:$tab:2" "anacron:$ana:2" "script:$sc:0"
  [ "$(sed -n 2p "$tab")" = "17 * * * * root cd / && run-parts /etc/cron.hourly" ]
  [[ "$(sed -n 2p "$ana")" == "@monthly"* ]]
  [ -x "$sc" ]
  touch "$BATS_TEST_TMPDIR/nosudo"
  run "$CRON/actions.sh" disable "system:$tab:2"
  [ "$status" -eq 1 ] && [[ "$output" == *"run sudo -v first"* ]]
  [ "$(sed -n 2p "$tab")" = "17 * * * * root cd / && run-parts /etc/cron.hourly" ]
}

@test "parse: commented-out system entries count when their user exists; the crontab example line does not" {
  printf '# *  *  *  *  * user-name command to be executed\n#0 3 * * * root echo off\n# a note\n' |
    parse system /etc/crontab > "$BATS_TEST_TMPDIR/out"
  [ "$(cut -f1,3,8 "$BATS_TEST_TMPDIR/out" | tr '\t' '|')" = "system:/etc/crontab:2|root|disabled" ]
  printf '#7\t10\tcron.weekly\trun-parts /etc/cron.weekly\n# See anacron(8) for details.\n' | parse anacron /etc/anacrontab > "$BATS_TEST_TMPDIR/out"
  [ "$(cut -f8 "$BATS_TEST_TMPDIR/out")" = "anacron-off:7:10:cron.weekly" ]
}

@test "parse: CRON_TZ moves the entries after it into its zone where cron honors it" {
  printf '0 1 * * * echo before\nCRON_TZ="Europe/Berlin"\n0 9 * * * echo after\n' > "$BATS_TEST_TMPDIR/crontab"
  FZX_CRON_HONORS_TZ=1 run parse user - < "$BATS_TEST_TMPDIR/crontab"
  [ "$(cut -f6 <<< "$output" | tr '\n' '|')" = "*-*-* 1:0:00|*-*-* 9:0:00 Europe/Berlin|" ]
  FZX_CRON_HONORS_TZ=0 run parse user - < "$BATS_TEST_TMPDIR/crontab"
  [ "$(cut -f6 <<< "$output" | tr '\n' '|')" = "*-*-* 1:0:00|*-*-* 9:0:00|" ]
  # the preview says which
  FZX_CRON_HONORS_TZ=1 run "$CRON/preview.sh" user:-:3
  [[ "$output" == *"zone      Europe/Berlin (CRON_TZ)"* ]]
  FZX_CRON_HONORS_TZ=0 run "$CRON/preview.sh" user:-:3
  [[ "$output" == *"CRON_TZ=Europe/Berlin is ignored"* ]]
  FZX_CRON_HONORS_TZ=0 run "$CRON/preview.sh" user:-:1
  [[ "$output" != *zone* ]]
}

@test "other users' crontabs: listed with a cached sudo (not yours twice), disabled and edited through crontab -u" {
  printf 'MAILTO=a\n30 4 * * * alice-job\n' > "$BATS_TEST_TMPDIR/spool-cron/alice"
  run src system
  [[ "$output" == *"alice     alice-job  alice's crontab:2"* ]]
  [[ "$output" != *never-listed* ]]
  run src user
  [[ "$output" != *alice* ]]
  "$CRON/actions.sh" disable "spool:$BATS_TEST_TMPDIR/spool-cron/alice:2"
  [ "$(sed -n 2p "$BATS_TEST_TMPDIR/spool-cron/alice")" = "#30 4 * * * alice-job" ]
  "$CRON/actions.sh" edit "spool:$BATS_TEST_TMPDIR/spool-cron/alice:2"
  grep -qx "crontab -u alice -e" "$BATS_TEST_TMPDIR/calls"
  run "$CRON/preview.sh" "spool:$BATS_TEST_TMPDIR/spool-cron/alice:2"
  [[ "$output" == *"user      alice"* && "$output" == *"alice's crontab ($BATS_TEST_TMPDIR/spool-cron/alice):2"* ]]
  touch "$BATS_TEST_TMPDIR/nosudo"
  run src system
  [[ "$output" != *alice* ]]
}

@test "actions: run as cron would: in your home with only cron's environment and the crontab's variables" {
  run "$CRON/actions.sh" run user:-:9
  [ "$status" -eq 0 ]
  [[ "$output" == *'$ cat '* && "$output" == *$'first%\nsecond'* ]]
  printf 'MAILTO=me\nPATH = "/opt/x:/usr/bin:/bin"\n* * * * * pwd; env | sort\n' > "$BATS_TEST_TMPDIR/crontab"
  run "$CRON/actions.sh" run user:-:3
  local home
  home="$(getent passwd "$(id -un)" | cut -d: -f6)"
  [[ "$output" == *$'\n'"$home"$'\n'* ]]
  [[ "$output" == *"HOME=$home"*"LOGNAME=$(id -un)"*"MAILTO=me"*"PATH=/opt/x:/usr/bin:/bin"*"SHELL=/bin/sh"* ]]
  [[ "$output" != *BATS_TEST_TMPDIR* ]]
  ! grep -q '^sudo' "$BATS_TEST_TMPDIR/calls" 2> /dev/null
  source "$CRON/source.sh" || :
  source "$CRON/actions.sh" || :
  { IFS= read -r -d '' c; IFS= read -r -d '' i; } < <(cron::_command 'cat%a\%b%c'; printf '\0')
  [ "$c" = cat ] && [ "$i" = $'a%b\nc' ]
}

@test "actions: run system entries as their user through sudo, anacron jobs with anacron, scripts as root" {
  printf 'SHELL=/bin/sh\nPATH=/sbin:/bin\n0 1 * * * nobody echo hi from cron\n' > "$BATS_TEST_TMPDIR/etc/cron.d/hello"
  printf '#!/bin/sh\necho "script $PATH"\n' > "$BATS_TEST_TMPDIR/etc/cron.daily/hello"
  chmod +x "$BATS_TEST_TMPDIR/etc/cron.daily/hello"
  run "$CRON/actions.sh" run "system:$BATS_TEST_TMPDIR/etc/cron.d/hello:3" "anacron:$BATS_TEST_TMPDIR/etc/anacrontab:1" \
    "script:$BATS_TEST_TMPDIR/etc/cron.daily/hello:0"
  [ "$status" -eq 0 ]
  # nobody's home does not exist: from /
  [[ "$output" == *"hi from cron"* && "$output" == *"(as nobody in /,"* && "$output" == *"PATH=/sbin:/bin"* ]]
  # a script gets /etc/crontab's environment (the first system file)
  [[ "$output" == *"script /usr/bin:/bin"* ]]
  [ "$(grep -c '^sudo -u nobody' "$BATS_TEST_TMPDIR/calls")" -eq 1 ] && [ "$(grep -c '^sudo -u root' "$BATS_TEST_TMPDIR/calls")" -eq 2 ]
  grep -qx "anacron -d -f -n -t $BATS_TEST_TMPDIR/etc/anacrontab cron.daily" "$BATS_TEST_TMPDIR/calls"
  run "$CRON/actions.sh" run "system:$BATS_TEST_TMPDIR/etc/cron.d/hello:1"
  [ "$status" -eq 1 ] && [[ "$output" == *"no longer an entry"* ]]
}

@test "actions: edit your crontab with crontab -e, system files with sudoedit at the line" {
  "$CRON/actions.sh" edit user:-:3
  EDITOR=nvim "$CRON/actions.sh" edit "system:$BATS_TEST_TMPDIR/etc/crontab:2"
  EDITOR=nvim "$CRON/actions.sh" edit "script:$BATS_TEST_TMPDIR/etc/cron.daily/logrotate:0"
  [ "$(cat "$BATS_TEST_TMPDIR/calls")" = "crontab -e
sudoedit -- $BATS_TEST_TMPDIR/etc/crontab SUDO_EDITOR=nvim +2
sudoedit -- $BATS_TEST_TMPDIR/etc/cron.daily/logrotate SUDO_EDITOR=nvim +1" ]
}

@test "under fzx: commands accepted and copied, the action keys" {
  stub_fzf
  run "$FZX" -m cron
  [ "$status" -eq 0 ]
  read_fzf_args
  [[ " ${FZF_ARGS[*]} " == *" --accept-nth=2 "* && " ${FZF_ARGS[*]} " == *" --with-nth=3 "* ]]
  [[ "$(fzf_bind ctrl-y)" == *"copy {+2}"* ]]
  [[ "$(fzf_bind alt-d)" == "alt-d:transform($FZX _cb notify disable {+1})+"*"reload("* ]]
  [[ "$(fzf_bind alt-enter)" == "alt-enter:execute($FZX _cb action run {+1})"* ]]
  [[ "$(fzf_bind ctrl-e)" == "ctrl-e:execute($FZX _cb action edit {+1})+"*"reload("* ]]
}

@test "menu: entries where crontab is installed; your crontab's entries counted" {
  source "$CRON/manifest.sh"
  cron::applicable cron
  [ "$(cron::summary cron:user)" = "6 entries" ]
  rm "$BATS_TEST_TMPDIR/crontab"
  [ "$(cron::summary cron:user)" = "no crontab" ]
}
