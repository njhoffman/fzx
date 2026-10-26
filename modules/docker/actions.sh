#!/usr/bin/env bash
# docker actions on the selected ids of the current mode; an action that does not apply to the mode says
# so and does nothing. Compose projects are addressed by name (docker compose -p).

# docker::not_here <action>: report an action that does not apply to the current mode
docker::not_here() {
  printf 'docker: %s does not apply to %s\n' "$1" "${FZX_MODE:-containers}" >&2
  return 2
}

# docker::wait: keep output on screen until a key (foreground actions return to fzf at once)
docker::wait() {
  [[ -t 1 ]] || return 0
  printf '\n\e[2m(press a key)\e[0m'
  read -rsn1 < /dev/tty || :
}

# docker::exec <container>: the first of FZX_DOCKER_SHELLS the container has
docker::exec() {
  local shell
  for shell in "${FZX_DOCKER_SHELLS[@]:-sh}"; do
    if command docker exec "$1" sh -c "command -v $shell" > /dev/null 2>&1; then
      command docker exec -it "$1" "$shell"
      return
    fi
  done
  # no sh in the image either: let docker say why
  command docker exec -it "$1" sh
}

# docker::action <action> <id...>
docker::action() {
  local action="${1:-}" mode="${FZX_MODE:-containers}" id rc=0
  shift
  (($#)) || [[ "$action" == prune ]] || return 0
  case "$action:$mode" in
    start:containers) command docker start "$@" ;;
    start:compose) for id in "$@"; do command docker compose -p "$id" up -d || rc=$?; done ;;
    stop:containers) command docker stop "$@" ;;
    stop:compose) for id in "$@"; do command docker compose -p "$id" down || rc=$?; done ;;
    restart:containers) command docker restart "$@" ;;
    restart:compose) for id in "$@"; do command docker compose -p "$id" restart || rc=$?; done ;;
    kill:containers) command docker kill "$@" ;;
    remove:containers) command docker rm -f "$@" ;;
    remove:images) command docker rmi -f "$@" ;;
    remove:volumes) command docker volume rm -f "$@" ;;
    remove:networks) command docker network rm "$@" ;;
    exec:containers) docker::exec "$1" ;;
    logs:containers)
      printf '\e[2mdocker logs -f %s (ctrl-c returns)\e[0m\n' "$1"
      # ctrl-c ends the follow, not fzx
      trap : INT
      command docker logs -f --tail "${FZX_DOCKER_LOG_LINES:-40}" "$1"
      trap - INT
      ;;
    logs:compose)
      printf '\e[2mdocker compose -p %s logs -f (ctrl-c returns)\e[0m\n' "$1"
      trap : INT
      command docker compose -p "$1" logs -f --tail "${FZX_DOCKER_LOG_LINES:-40}"
      trap - INT
      ;;
    inspect:containers | inspect:images | inspect:volumes | inspect:networks)
      local kind="${mode%s}"
      command docker "$kind" inspect "$@" | { if command -v jq > /dev/null; then jq -C .; else cat; fi; } |
        ${PAGER:-less -R}
      ;;
    run:images)
      printf '\e[2mdocker run -it --rm %s (exit returns)\e[0m\n' "$1"
      # shellcheck disable=SC2016  # $s is the container shell's
      command docker run -it --rm --entrypoint sh "$1" -c 'for s in zsh bash ash sh; do command -v $s > /dev/null && exec $s; done' ||
        docker::wait
      ;;
    pull:images)
      for id in "$@"; do
        # by reference: pulling an image id means nothing
        id="$(command docker image inspect --format '{{index .RepoTags 0}}' "$id" 2> /dev/null)" || continue
        [[ -n "$id" ]] && { command docker pull "$id" || rc=$?; }
      done
      docker::wait
      ;;
    pull:compose)
      for id in "$@"; do command docker compose -p "$id" pull || rc=$?; done
      docker::wait
      ;;
    prune:containers) command docker container prune -f ;;
    prune:images) command docker image prune -f ;;
    prune:volumes) command docker volume prune -f ;;
    prune:networks) command docker network prune -f ;;
    start:* | stop:* | restart:* | kill:* | remove:* | exec:* | logs:* | inspect:* | run:* | pull:* | prune:*)
      docker::not_here "$action"
      ;;
    *)
      printf 'docker: unknown action: %s\n' "$action" >&2
      return 2
      ;;
  esac || rc=$?
  return "$rc"
}

[[ "${BASH_SOURCE[0]}" == "$0" ]] && {
  source "$(dirname "${BASH_SOURCE[0]}")/../../lib/core.sh"
  fzx::require log config
  fzx::config_load "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" docker
  docker::action "$@"
}
