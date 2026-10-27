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
esac
exit 0
STUB
  chmod +x "$BATS_TEST_TMPDIR/bin/docker"
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
}

plain() { sed 's/\x1b\[[0-9;]*m//g'; }
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
  run bash -c "FZX_MODE=containers '$DOCKER/actions.sh' logs c1 c2 | sed 's/\x1b\[[0-9;]*m//g' | sort"
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
