#!/usr/bin/env bats
# the docker module with a stubbed docker command (calls are logged; nothing touches a real daemon)

load test_helper

DOCKER="$(readlink -f "$BATS_TEST_DIRNAME/../modules/docker")"

setup() {
  setup_fzx
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  CALLS="$BATS_TEST_TMPDIR/calls"
  cat > "$BATS_TEST_TMPDIR/bin/docker" << STUB
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$CALLS"
case "\$*" in
  'ps -a --format'*|'ps --format'*)
    printf 'c1\texited\told-job\tbusybox\tExited (0) 2 days ago\t\n'
    [[ "\$*" == 'ps -a'* ]] || exit 0
    printf 'c2\trunning\tweb\tnginx:1\tUp 3 hours\t0.0.0.0:80->80/tcp\n' ;;
  'images -q --filter dangling=true') echo i2 ;;
  'images --format'*) printf 'i1\tnginx\t1\t2 weeks ago\t180MB\ni2\t<none>\t<none>\t3 months ago\t12MB\n' ;;
  'volume ls -q --filter dangling=true') echo spare ;;
  'volume ls --format'*) printf 'data\tlocal\t/var/lib/docker/volumes/data/_data\nspare\tlocal\t/var/lib/docker/volumes/spare/_data\n' ;;
  'network ls --format'*) printf 'n1\tbridge\tbridge\tlocal\n' ;;
  'compose version') echo 'Docker Compose version v2' ;;
  'compose ls -a --format json') echo '[{"Name":"site","Status":"running(2)","ConfigFiles":"/srv/site/compose.yml"}]' ;;
  'exec c2 sh -c command -v zsh') exit 1 ;;
  'exec c2 sh -c command -v bash') exit 0 ;;
  # c3: an image without a shell
  'exec c3 sh -c :') exit 126 ;;
  'inspect --format {{.Name}} c2') echo /web ;;
  'inspect --format {{.Name}} c3') echo /distroless ;;
esac
exit 0
STUB
  chmod +x "$BATS_TEST_TMPDIR/bin/docker"
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
}

plain() { sed 's/\x1b\[[0-9;:]*m//g'; }
src() { FZX_MODE="$1" "$DOCKER/source.sh" | plain; }
act() { FZX_MODE="$1" "$DOCKER/actions.sh" "${@:2}"; }

@test "containers: running first, every state, the running toggle asks docker for running ones only" {
  run src containers
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == c2$'\t'*web*nginx:1*'Up 3 hours'*'0.0.0.0:80->80/tcp' ]]
  [[ "${lines[1]}" == c1$'\t'*old-job* ]]
  FZX_TOGGLES=running run src containers
  [ "${#lines[@]}" -eq 1 ]
  grep -qxF 'ps --format {{.ID}}\t{{.State}}\t{{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}' "$CALLS"
}

@test "images: references, dangling ones dim; volumes: unused ones dim" {
  run bash -c "FZX_MODE=images '$DOCKER/source.sh'"
  [[ "${lines[0]}" == i1$'\t'*'nginx:1'* && "${lines[0]}" != i1$'\t'$'\e[38;5;244m'* ]]
  [[ "${lines[1]}" == i2$'\t'$'\e[38;5;244m<none>'* ]]
  run src volumes
  [[ "${lines[0]}" == data$'\t'*'in use'* && "${lines[1]}" == spare$'\t'*unused* ]]
}

@test "networks and compose projects" {
  run src networks
  [[ "$output" == n1$'\t'*bridge*local* ]]
  run src compose
  [ "$status" -eq 0 ]
  [[ "$output" == site$'\t'*'running(2)'*'/srv/site/compose.yml' ]]
}

@test "actions map to the mode's docker command" {
  act containers start c1 c2
  act compose stop site
  act images remove i1 i2
  act volumes remove spare
  act containers prune
  grep -qx 'start c1 c2' "$CALLS"
  grep -qx 'compose -p site down' "$CALLS"
  grep -qx 'rmi -f i1 i2' "$CALLS"
  grep -qx 'volume rm -f spare' "$CALLS"
  grep -qx 'container prune -f' "$CALLS"
}

@test "an action outside its modes does nothing and says so" {
  run act images exec i1
  [ "$status" -eq 2 ]
  [[ "$output" == *'exec does not apply to images'* ]]
  [ ! -f "$CALLS" ] || ! grep -q '^exec' "$CALLS"
}

# run a docker:: function with the module's actions loaded
docker_fn() { FZX_REPO="$FZX_REPO" bash -c 'source "$FZX_REPO/lib/core.sh"; source "$1/actions.sh"; shift; "$@"' _ "$DOCKER" "$@"; }

@test "cmd: through the container's sh when it has one, as words without; a header per container" {
  run docker_fn docker::cmd_run 'ls / | head -1' c2 c3
  [ "$status" -eq 0 ]
  grep -qxF 'exec c2 sh -c ls / | head -1' "$CALLS"
  grep -qxF 'exec c3 ls / | head -1' "$CALLS"
  [[ "$(printf '%s\n' "$output" | plain)" == *'── web: ls / | head -1'*'── distroless: ls / | head -1'* ]]
}

@test "cmd history: newest last, once each, capped at FZX_DOCKER_CMD_HISTORY" {
  docker_fn docker::cmd_remember 'ls /'
  docker_fn docker::cmd_remember 'uname -a'
  docker_fn docker::cmd_remember 'ls /'
  [ "$(cat "$FZX_STATE_DIR/docker/cmd_history")" = $'uname -a\nls /' ]
  FZX_DOCKER_CMD_HISTORY=1 docker_fn docker::cmd_remember 'id'
  [ "$(cat "$FZX_STATE_DIR/docker/cmd_history")" = id ]
}

@test "cmd applies to containers only; df in any mode, into the pager" {
  run act images cmd i1
  [[ "$output" == *'cmd does not apply to images'* ]]
  PAGER=cat run act volumes df
  [ "$status" -eq 0 ]
  grep -qx 'system df' "$CALLS" && grep -qx 'system df -v' "$CALLS"
}

@test "exec: the first shell the container has" {
  run act containers exec c2
  grep -qx 'exec -it c2 bash' "$CALLS"
}

@test "under fzx: mode, toggle and action keys are bound" {
  stub_fzf
  run "$FZX" -m docker
  [ "$status" -eq 0 ]
  [[ "$(fzf_bind alt-a)" == *'_cb toggle running'* ]]
  [[ "$(fzf_bind alt-s)" == *'_cb action start'* ]]
  [[ "$(fzf_bind alt-x)" == *'confirm'*'remove'* || "$(fzf_bind alt-x)" == *'_cb action remove'* ]]
}

@test "logs of several containers: merged, each line prefixed with its container's name" {
  # inspect gives the name, logs prints two lines and ends
  cat > "$BATS_TEST_TMPDIR/bin/docker" << STUB
#!/usr/bin/env bash
case "\$1" in
  inspect) echo "/name-\${@: -1}" ;;
  logs) printf 'line one of %s\nline two of %s\n' "\${@: -1}" "\${@: -1}" ;;
esac
STUB
  run bash -c "FZX_MODE=containers '$DOCKER/actions.sh' logs c1 c2 | sed 's/\x1b\[[0-9;:]*m//g' | sort"
  [ "$status" -eq 0 ]
  [[ "$output" == *'[name-c1] line one of c1'* && "$output" == *'[name-c2] line two of c2'* ]]
}

@test "sorts: containers by state or name, images by created, size or name; the sorted column underlined" {
  FZX_SORT=name run src containers
  [[ "${lines[0]}" == c1$'\t'*old-job* && "${lines[1]}" == c2$'\t'*web* ]]
  run bash -c "FZX_SORT=name FZX_MODE=containers '$DOCKER/source.sh'"
  [[ "${lines[1]}" == *$'\e[4mweb\e[0m'* ]]
  run bash -c "FZX_SORT=size FZX_MODE=images '$DOCKER/source.sh'"
  [[ "${lines[0]}" == i1$'\t'* && "${lines[0]}" == *$'\e[4m180MB\e[0m'* ]]
  FZX_SORT=name run src images
  # untagged images last
  [[ "${lines[0]}" == i1$'\t'* && "${lines[1]}" == i2$'\t'* ]]
  run bash -c "FZX_SORT=created FZX_MODE=images '$DOCKER/source.sh'"
  [[ "${lines[0]}" == i1$'\t'* && "${lines[0]}" == *$'4m2 weeks ago\e[0m'* ]]
}

@test "header row (FZX_SORTED_SHOW=header): the columns named over the rows, the sorted one marked, the rows plain" {
  run env FZX_SORTED_SHOW=header FZX_SORT_HEADER=1 FZX_SORT=name FZX_MODE=containers FZX_SORTED_ARROWS='^ v' "$DOCKER/source.sh"
  [ "${#lines[@]}" -eq 3 ]
  [[ "${lines[0]}" == $'\t'*$'mNAME^\e[0m'* && "${lines[1]}" != *$'\e[4m'* ]]
  local head row
  head="$(plain <<< "${lines[0]}")" row="$(plain <<< "${lines[1]}")"
  [[ "$head" == $'\t  NAME^'*IMAGE*STATUS*PORTS ]]
  # IMAGE starts where the image does
  local pre="${head%%IMAGE*}" rpre="${row#*$'\t'}"
  pre="${pre#*$'\t'}" rpre="${rpre%%busybox*}"
  [ "${#pre}" -eq "${#rpre}" ]
  run env FZX_SORTED_SHOW=both FZX_SORT_HEADER=1 FZX_SORT=size FZX_SORT_DESC=1 FZX_MODE=images FZX_SORTED_ARROWS='^ v' "$DOCKER/source.sh"
  [[ "$(plain <<< "${lines[0]}")" == $'\tREPOSITORY:TAG'*"IMAGE ID"*CREATED*SIZEv ]]
  [[ "${lines[1]}" == *$'\e[4m180MB\e[0m'* ]]
  # no header row without FZX_SORT_HEADER
  run env FZX_SORTED_SHOW=header FZX_SORT=size FZX_MODE=images "$DOCKER/source.sh"
  [[ "${lines[0]}" == i1$'\t'* ]]
}

@test "menu: the daemon is asked once for all the module's entries; compose needs the compose plugin" {
  load_libs log config menu
  fzx::menu_entries docker "$DOCKER"
  local t
  for t in "${FZX_ENTRY_TARGETS[@]}"; do docker::applicable "$t"; done
  [ "$(grep -c '^info' "$CALLS")" -eq 1 ]
  # a stopped daemon hides every entry
  _DOCKER_UP=1
  run docker::applicable docker
  [ "$status" -eq 1 ]
}
