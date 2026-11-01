#!/usr/bin/env bats
# docker and systemd against the real thing (the other tests stub both). Opt-in: FZX_TEST_LIVE=1
# (`just test-live`); each part skips when its tool or daemon is missing. Everything made here is
# labelled or named fzx-live-* and removed in teardown:
#   docker   a container from a local image (never pulled: FZX_LIVE_IMAGE, else the first of ubuntu:24.04,
#            debian, alpine, busybox present), a volume and a network
#   systemd  a user unit in $XDG_RUNTIME_DIR/systemd/user (enable links it from
#            ~/.config/systemd/user/default.target.wants; teardown disables it). System units and sudo
#            stay stubbed (test/modules.bats).

load test_helper

DOCKER="$(readlink -f "$BATS_TEST_DIRNAME/../modules/docker")"
SYSTEMD="$(readlink -f "$BATS_TEST_DIRNAME/../modules/systemd")"

setup() {
  [[ "${FZX_TEST_LIVE:-0}" == 1 ]] || skip "live tests: FZX_TEST_LIVE=1"
  setup_fzx
  LIVE="fzx-live-$BATS_TEST_NUMBER-$$"
}

teardown() {
  [[ "${FZX_TEST_LIVE:-0}" == 1 ]] || return 0
  if [[ "$BATS_TEST_DESCRIPTION" == docker* ]]; then
    command docker rm -f "$LIVE" > /dev/null 2>&1
    command docker volume rm -f "$LIVE" > /dev/null 2>&1
    command docker network rm "$LIVE" > /dev/null 2>&1
  fi
  if [[ "$BATS_TEST_DESCRIPTION" == systemd* ]]; then
    systemctl --user disable "$LIVE.service" > /dev/null 2>&1
    systemctl --user stop "$LIVE.service" > /dev/null 2>&1
    rm -f "$XDG_RUNTIME_DIR/systemd/user/$LIVE.service"
    systemctl --user daemon-reload > /dev/null 2>&1
  fi
  return 0
}

plain() { sed 's/\x1b\[[0-9;]*m//g'; }

# a local image with sleep, or skip
live_image() {
  command -v docker > /dev/null || skip "no docker"
  command docker info > /dev/null 2>&1 || skip "docker daemon not reachable"
  local img
  for img in ${FZX_LIVE_IMAGE:-} ubuntu:24.04 debian:latest alpine:latest busybox:latest; do
    if command docker image inspect "$img" > /dev/null 2>&1; then
      IMAGE="$img"
      return 0
    fi
  done
  skip "no local image to run (set FZX_LIVE_IMAGE; nothing is pulled)"
}

# the container's state as docker reports it
state() { command docker inspect -f '{{.State.Status}}' "$1"; }

dsrc() { FZX_MODE="$1" FZX_TOGGLES="${2:-}" "$DOCKER/source.sh" | plain; }
dact() { FZX_MODE="$1" "$DOCKER/actions.sh" "${@:2}"; }

@test "docker containers: listed, the running toggle, stop, start, restart, kill and remove" {
  live_image
  local id
  id="$(command docker run -d --name "$LIVE" --label fzx-live=1 "$IMAGE" sleep 300)"
  id="${id:0:12}"
  run dsrc containers
  [ "$status" -eq 0 ]
  [[ "$output" == *"$id"$'\t'*"$LIVE"* ]]
  run dsrc containers running
  [[ "$output" == *"$LIVE"* ]]
  run dact containers stop "$id"
  [ "$status" -eq 0 ]
  [ "$(state "$id")" = exited ]
  run dsrc containers running
  [[ "$output" != *"$LIVE"* ]]
  run dact containers start "$id"
  [ "$status" -eq 0 ]
  [ "$(state "$id")" = running ]
  run dact containers restart "$id"
  [ "$status" -eq 0 ]
  [ "$(state "$id")" = running ]
  run dact containers kill "$id"
  [ "$status" -eq 0 ]
  [ "$(state "$id")" = exited ]
  run dact containers remove "$id"
  [ "$status" -eq 0 ]
  run command docker inspect "$id"
  [ "$status" -ne 0 ]
}

@test "docker preview: a container and its image" {
  live_image
  local id
  id="$(command docker run -d --name "$LIVE" --label fzx-live=1 "$IMAGE" sleep 300)"
  run env FZX_MODE=containers "$DOCKER/preview.sh" "${id:0:12}"
  [ "$status" -eq 0 ]
  [[ "$(plain <<< "$output")" == *"$LIVE"* ]]
  run dsrc images
  [[ "$output" == *"${IMAGE%%:*}"* ]]
}

@test "docker volumes and networks: listed, then removed by the remove action" {
  live_image
  command docker volume create --label fzx-live=1 "$LIVE" > /dev/null
  command docker network create --label fzx-live=1 "$LIVE" > /dev/null
  run dsrc volumes
  [[ "$output" == *"$LIVE"* ]]
  run dsrc networks
  [[ "$output" == *"$LIVE"* ]]
  local net
  net="$(dsrc networks | awk -F'\t' -v n="$LIVE" 'index($2, n) { print $1; exit }')"
  [ -n "$net" ]
  run dact volumes remove "$LIVE"
  [ "$status" -eq 0 ]
  run dact networks remove "$net"
  [ "$status" -eq 0 ]
  run dsrc volumes
  [[ "$output" != *"$LIVE"* ]]
  run dsrc networks
  [[ "$output" != *"$LIVE"* ]]
}

# a throwaway user unit, loaded, or skip
live_unit() {
  command -v systemctl > /dev/null || skip "no systemctl"
  systemctl --user is-system-running > /dev/null 2>&1 ||
    [[ "$(systemctl --user is-system-running 2> /dev/null)" == degraded ]] || skip "no user manager"
  mkdir -p "$XDG_RUNTIME_DIR/systemd/user"
  printf '[Unit]\nDescription=fzx live test\n[Service]\nExecStart=/bin/sleep 300\n[Install]\nWantedBy=default.target\n' \
    > "$XDG_RUNTIME_DIR/systemd/user/$LIVE.service"
  systemctl --user daemon-reload
}

ssrc() { FZX_MODE="$1" "$SYSTEMD/source.sh" | plain; }
sact() { "$SYSTEMD/actions.sh" "$@"; }

# a unit that is installed but not loaded is not listed (list-units only; TODO.md "systemd lists loaded
# units only"), so this one is started before it is looked for
@test "systemd user unit: start, listed running, restart, stop, enable, disable" {
  live_unit
  local id="user:$LIVE.service"
  run sact start "$id"
  [ "$status" -eq 0 ]
  [ "$(systemctl --user is-active "$LIVE.service")" = active ]
  run ssrc user
  [ "$status" -eq 0 ]
  [[ "$(grep -F "$id"$'\t'"$LIVE.service" <<< "$output")" == *running* ]]
  run sact restart "$id"
  [ "$status" -eq 0 ]
  [ "$(systemctl --user is-active "$LIVE.service")" = active ]
  run sact stop "$id"
  [ "$status" -eq 0 ]
  [ "$(systemctl --user is-active "$LIVE.service")" = inactive ]
  run sact enable "$id"
  [ "$status" -eq 0 ]
  [ "$(systemctl --user is-enabled "$LIVE.service")" = enabled ]
  run sact disable "$id"
  [ "$status" -eq 0 ]
  [ "$(systemctl --user is-enabled "$LIVE.service")" = disabled ]
}

@test "systemd preview: the unit's status; a failed unit shows in the failed mode" {
  live_unit
  local id="user:$LIVE.service"
  run "$SYSTEMD/preview.sh" "$id"
  [ "$status" -eq 0 ]
  [[ "$(plain <<< "$output")" == *"fzx live test"* ]]
  printf '[Unit]\nDescription=fzx live test\n[Service]\nExecStart=/bin/false\n' \
    > "$XDG_RUNTIME_DIR/systemd/user/$LIVE.service"
  systemctl --user daemon-reload
  sact start "$id" || true
  sleep 0.5
  run ssrc failed
  [[ "$output" == *"$id"* ]]
  systemctl --user reset-failed "$LIVE.service"
}
