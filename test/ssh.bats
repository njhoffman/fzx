#!/usr/bin/env bats
# the ssh module: hosts from a fixture ssh config, known_hosts and histdb, against stub ssh, ssh-keygen,
# tmux, rsync and ssh-copy-id (their calls logged)

load test_helper

SSHM="$(readlink -f "$BATS_TEST_DIRNAME/../modules/ssh")"

setup() {
  command -v sqlite3 > /dev/null || skip "sqlite3 not installed"
  setup_fzx
  export NO_COLOR=1 CALLS="$BATS_TEST_TMPDIR/calls" FZX_TTY="$BATS_TEST_TMPDIR/tty"
  local d="$BATS_TEST_TMPDIR/dot-ssh"
  mkdir -p "$d/conf.d" "$BATS_TEST_TMPDIR/bin"
  : > "$FZX_TTY"
  export FZX_SSH_CONFIG="$d/config" FZX_SSH_KNOWN_HOSTS="$d/known_hosts" FZX_SSH_HISTDB="$BATS_TEST_TMPDIR/histdb.db"
  printf 'Include conf.d/*\n\nHost desk desk-alias\n  HostName 10.0.0.5\n\nHost *.example.com !bad\n  User x\n' > "$FZX_SSH_CONFIG"
  printf 'Host nas\n  User admin\n' > "$d/conf.d/home"
  printf '|1|abc=|def= ssh-ed25519 AAAA\nbox.lan,10.0.0.9 ssh-ed25519 AAAA\n[git.lan]:2222 ssh-rsa AAAA\n10.0.0.7 ssh-rsa AAAA\n' > "$FZX_SSH_KNOWN_HOSTS"
  sqlite3 "$FZX_SSH_HISTDB" "
    create table commands (id integer primary key, argv text);
    create table history (id integer primary key, command_id int, start_time int);
    insert into commands values (1, 'ssh me@desk'), (2, 'ssh -p 2222 -i ~/.ssh/k git.lan'), (3, 'scp file.txt me@nas:/tmp/'),
      (4, 'rsync -a ./ box.lan:backup/'), (5, 'ssh -l root desk'), (6, 'mosh far'), (7, 'ssh desk ls' || char(10) || 'echo hi'),
      (8, 'ls -l'), (9, 'ssh \$HOST'), (10, 'ssh me@desk | tee log');
    insert into history (command_id, start_time) values (1, 1000), (1, 3000), (2, 2000), (3, 500), (4, 4000), (5, 100),
      (6, 50), (7, 20), (8, 9000), (9, 10), (10, 3500);"
  cat > "$BATS_TEST_TMPDIR/bin/ssh" << 'STUB'
#!/usr/bin/env bash
printf 'ssh %s\n' "$*" >> "$CALLS"
if [[ "$1" == -G ]]; then printf 'user me\nhostname 10.0.0.5\nport 22\nidentityfile ~/.ssh/id_ed25519\nidentityfile ~/.ssh/id_rsa\n'; fi
exit 0
STUB
  printf '#!/usr/bin/env bash\nprintf "ssh-keygen %%s\\n" "$*" >> "$CALLS"\n[[ "$2" == desk ]]\n' > "$BATS_TEST_TMPDIR/bin/ssh-keygen"
  local t
  for t in tmux rsync scp ssh-copy-id; do
    printf '#!/usr/bin/env bash\nprintf "%s %%s\\n" "$*" >> "$CALLS"\n' "$t" > "$BATS_TEST_TMPDIR/bin/$t"
  done
  chmod +x "$BATS_TEST_TMPDIR/bin/"*
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
  export FZX_SSH_NOW=10000
}

src() { "$SSHM/source.sh"; }

@test "hosts: config (Include too, no patterns), unhashed known_hosts, and histdb's commands, merged" {
  load_libs log
  source "$SSHM/source.sh" || :
  run ssh::hosts
  local got
  got="$(printf '%s\n' "$output" | cut -f1,3 | sort)"
  [ "$got" = "$(printf '%s\n' $'box.lan\tknown,history' $'desk\tconfig,history' $'desk-alias\tconfig' $'far\thistory' \
    $'git.lan\tknown,history' $'me@desk\thistory' $'me@nas\thistory' $'nas\tconfig' $'root@desk\thistory' | sort)" ]
}

@test "hosts: the last use is the newest, counts add up; a newline or a pipe ends the command" {
  load_libs log
  source "$SSHM/source.sh" || :
  run ssh::hosts
  [[ "$output" == *$'me@desk\tdesk\thistory\t3500\t3'* ]]
  [[ "$output" == *$'git.lan\tgit.lan\tknown,history\t2000\t1'* ]]
}

@test "source: last used first, never used last; sort name by host" {
  run src
  [ "$(printf '%s\n' "$output" | cut -f1 | head -4 | paste -sd' ')" = "box.lan me@desk git.lan me@nas" ]
  [[ "$(printf '%s\n' "$output" | tail -1)" == *"    -  "* ]]
  [[ "$output" == *"me@desk"*"1h"*"3x  history"* ]]
  FZX_SORT=name run src
  [ "$(printf '%s\n' "$output" | cut -f2 | head -3 | paste -sd' ')" = "box.lan desk desk" ]
}

@test "source: with a header row, the columns named first, the sorted one marked" {
  FZX_SORT_HEADER=1 run src
  [[ "${lines[0]}" == $'\t\tHOST '*" LAST"*" USES  FROM" ]]
  [[ "${lines[1]}" == box.lan* ]]
}

@test "connect: a tmux window a host (after the origin pane's from the popup); outside tmux, here" {
  TMUX=x "$SSHM/actions.sh" connect me@desk box.lan
  grep -qx 'tmux new-window -n desk ssh me@desk' "$CALLS"
  grep -qx 'tmux new-window -n box ssh box.lan' "$CALLS"
  TMUX=x FZX_ORIGIN_PANE=%4 "$SSHM/actions.sh" connect nas
  grep -qx 'tmux new-window -a -t %4 -n nas ssh nas' "$CALLS"
  : > "$CALLS"
  TMUX="" "$SSHM/actions.sh" connect desk nas
  [ "$(cat "$CALLS")" = "ssh desk" ]
  "$SSHM/actions.sh" here box.lan
  grep -qx 'ssh box.lan' "$CALLS"
}

@test "send and fetch copy with rsync -a and its progress, else scp -r" {
  load_libs log
  source "$SSHM/actions.sh" || :
  ssh::_copy ./notes desk:srv
  grep -qx 'rsync -a --info=progress2 -- ./notes desk:srv' "$CALLS"
  FZX_SSH_RSYNC="" ssh::_copy desk:log .
  grep -qx 'scp -r -- desk:log .' "$CALLS"
}

@test "copy-id and edit" {
  "$SSHM/actions.sh" copy-id desk
  grep -qx 'ssh-copy-id desk' "$CALLS"
  printf '#!/usr/bin/env bash\nprintf "editor %%s\\n" "$*" >> "$CALLS"\n' > "$BATS_TEST_TMPDIR/bin/fake-editor"
  chmod +x "$BATS_TEST_TMPDIR/bin/fake-editor"
  VISUAL=fake-editor "$SSHM/actions.sh" edit me@desk-alias
  grep -qx "editor +3 -- $FZX_SSH_CONFIG" "$CALLS"
  VISUAL=fake-editor "$SSHM/actions.sh" edit far
  grep -qx "editor +7 -- $FZX_SSH_CONFIG" "$CALLS"
}

@test "preview: ssh -G's settings once each, known_hosts, the commands that named the host" {
  run "$SSHM/preview.sh" me@desk desk
  [ "${lines[0]}" = "me@desk" ]
  [[ "$output" == *"hostname       10.0.0.5"* && "$output" == *"identityfile   ~/.ssh/id_ed25519"* ]]
  [[ "$output" != *id_rsa* ]]
  [[ "$output" == *"known          in known_hosts"* ]]
  [[ "$output" == *"ssh me@desk | tee log"* && "$output" == *"ssh desk ls echo hi"* && "$output" != *"git.lan"* ]]
  run "$SSHM/preview.sh" far far
  [[ "$output" == *"not in known_hosts"* ]]
}

@test "under fzx: enter connects (become), alt-enter here, alt-s and alt-F ask" {
  stub_fzf
  run "$FZX" -m ssh
  [ "$(fzf_bind enter)" = "enter:become($FZX _cb action connect {+1})" ]
  [ "$(fzf_bind alt-enter)" = "alt-enter:become($FZX _cb action here {+1})" ]
  [[ "$(fzf_bind alt-s)" == *"execute("*"_cb action send {+1})"* ]]
  FZX_PRINT=1 run "$FZX" -m ssh
  run fzf_bind enter
  [ "$status" -ne 0 ]
}

@test "menu: applicable with ssh and a host; the summary counts them and names the last used" {
  load_libs log
  source "$SSHM/manifest.sh" || :
  ssh::applicable ssh
  [ "$(ssh::summary ssh)" = "9 hosts, last: box.lan" ]
  FZX_SSH_CONFIG=/nonexistent FZX_SSH_KNOWN_HOSTS=/nonexistent FZX_SSH_HISTDB=/nonexistent run ssh::applicable ssh
  [ "$status" -ne 0 ]
}

@test "components: every row has its five fields" {
  local bad
  bad="$(grep -v '^#' "$SSHM/components.tsv" | awk -F'  +|\t' 'NF != 5')"
  [ -z "$bad" ] || { printf 'rows without five fields:\n%s\n' "$bad"; return 1; }
}
