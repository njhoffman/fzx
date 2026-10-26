#!/usr/bin/env bash
# docker menu entries

docker::manifest() {
  fzx::entry docker "Docker containers"
  fzx::entry docker:images "Docker images"
  fzx::entry docker:volumes "Docker volumes"
  fzx::entry docker:compose "Docker compose projects"
}

# only where the daemon answers (docker installed but not running would only show errors)
docker::applicable() {
  command -v docker > /dev/null || return 1
  [[ "$1" != docker:compose ]] || command docker compose version > /dev/null 2>&1 || return 1
  timeout 2 docker info --format '{{.ServerVersion}}' > /dev/null 2>&1
}

docker::summary() {
  case "$1" in
    docker) printf '%s running, %s stopped\n' "$(command docker ps -q | wc -l)" "$(command docker ps -aq --filter status=exited | wc -l)" ;;
    docker:images) printf '%s images, %s dangling\n' "$(command docker images -q | wc -l)" "$(command docker images -q --filter dangling=true | wc -l)" ;;
    docker:volumes) printf '%s volumes, %s unused\n' "$(command docker volume ls -q | wc -l)" "$(command docker volume ls -q --filter dangling=true | wc -l)" ;;
    docker:compose) printf '%s projects\n' "$(command docker compose ls -aq 2> /dev/null | wc -l)" ;;
  esac
}
