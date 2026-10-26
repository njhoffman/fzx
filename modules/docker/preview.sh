#!/usr/bin/env bash
# docker preview per mode: a container's state, image, ports, mounts and networks, then its latest logs;
# an image's details, the containers using it and its layers; a volume's details and its containers; a
# network's containers; a compose project's services. Image config fields go through index and lists
# through range: docker 28's image inspect values are maps and []interface {}, where a missing key is an
# error and join fails

# docker::preview <id>
docker::preview() {
  local id="${1:-}" B=$'\e[1m' D=$'\e[2m' R=$'\e[0m'
  [[ -n "$id" ]] || return 0
  case "${FZX_MODE:-containers}" in
    containers)
      command docker inspect --format "${B}{{.Name}}${R}  {{.State.Status}}{{if .State.Health}} ({{.State.Health.Status}}){{end}}
${D}image${R}     {{.Config.Image}}
${D}started${R}   {{.State.StartedAt}}{{if not .State.Running}}   ${D}exit${R} {{.State.ExitCode}}{{end}}
${D}command${R}   {{range .Config.Cmd}}{{.}} {{end}}
${D}restart${R}   {{.HostConfig.RestartPolicy.Name}}
${D}ports${R}     {{range \$p, \$b := .NetworkSettings.Ports}}{{\$p}}{{if \$b}}->{{(index \$b 0).HostPort}}{{end}} {{end}}
${D}networks${R}  {{range \$n, \$v := .NetworkSettings.Networks}}{{\$n}} {{\$v.IPAddress}}  {{end}}
${D}mounts${R}    {{range .Mounts}}
  {{.Source}} -> {{.Destination}}{{end}}" "$id" 2>&1
      printf '\n%slogs%s\n' "$B" "$R"
      command docker logs --tail "${FZX_DOCKER_LOG_LINES:-40}" "$id" 2>&1
      ;;
    images)
      command docker image inspect --format "${B}{{range .RepoTags}}{{.}} {{end}}${R}
${D}id${R}          {{.Id}}
${D}created${R}     {{.Created}}
${D}size${R}        {{.Size}} bytes
${D}entrypoint${R}  {{range index .Config \"Entrypoint\"}}{{.}} {{end}}
${D}cmd${R}         {{range index .Config \"Cmd\"}}{{.}} {{end}}
${D}ports${R}       {{range \$p, \$v := index .Config \"ExposedPorts\"}}{{\$p}} {{end}}
${D}workdir${R}     {{index .Config \"WorkingDir\"}}" "$id" 2>&1
      printf '\n%scontainers%s\n' "$B" "$R"
      command docker ps -a --filter "ancestor=$id" --format '  {{.Names}}  {{.Status}}' 2>&1
      printf '\n%slayers%s\n' "$B" "$R"
      command docker image history --no-trunc --format '  {{.Size}}\t{{.CreatedBy}}' "$id" 2>&1 | cut -c1-"${FZF_PREVIEW_COLUMNS:-200}"
      ;;
    volumes)
      command docker volume inspect --format "${B}{{.Name}}${R}
${D}driver${R}      {{.Driver}}
${D}mountpoint${R}  {{.Mountpoint}}
${D}created${R}     {{.CreatedAt}}
${D}labels${R}      {{range \$k, \$v := .Labels}}{{\$k}}={{\$v}} {{end}}" "$id" 2>&1
      printf '\n%scontainers%s\n' "$B" "$R"
      command docker ps -a --filter "volume=$id" --format '  {{.Names}}  {{.Status}}' 2>&1
      ;;
    networks)
      command docker network inspect --format "${B}{{.Name}}${R}  {{.Driver}} {{.Scope}}
${D}subnet${R}  {{range .IPAM.Config}}{{.Subnet}} {{end}}
${D}containers${R}{{range \$id, \$c := .Containers}}
  {{\$c.Name}}  {{\$c.IPv4Address}}{{end}}" "$id" 2>&1
      ;;
    compose)
      command docker compose -p "$id" ps -a --format 'table {{.Service}}\t{{.State}}\t{{.Status}}\t{{.Ports}}' 2>&1
      ;;
  esac
}

[[ "${BASH_SOURCE[0]}" == "$0" ]] && {
  source "$(dirname "${BASH_SOURCE[0]}")/../../lib/core.sh"
  fzx::require log config
  fzx::config_load "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" docker
  docker::preview "$@"
}
