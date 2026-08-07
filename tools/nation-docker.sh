#!/bin/bash
# NATION AGENT — Docker Tool
# Usage: nation-docker.sh <command> [args...]
#
# Commands:
#   ps       [--all]                  List containers (running, or all)
#   images                            List images
#   run      <image> [cmd...]         Run a container
#   exec     <container> <cmd...>     Exec command in running container
#   logs     <container> [--tail n]   Show container logs
#   stop     <container>              Stop a container
#   rm       <container> [--force]    Remove a container
#   rmi      <image> [--force]        Remove an image
#   build    [path] [tag]             Build image from Dockerfile
#   pull     <image>                  Pull an image
#   push     <image>                  Push an image
#   inspect  <container|image>        Inspect a container or image
#   stats    [container]              Show resource stats
#   networks                          List networks
#   volumes                           List volumes
#   compose  <up|down|ps|logs> [...]  Docker Compose wrapper
#   info                              Show Docker system info
#   prune                             Remove unused resources (with confirm)
#
set -euo pipefail

CMD="${1:-help}"
LOG="$HOME/.kiro/logs/nation-agent.log"
TS=$(date '+%Y-%m-%d %H:%M:%S')

log() { echo "[$TS] [DOCKER] $*" >> "$LOG"; }
die() { echo "ERROR: $*" >&2; exit 1; }

# Docker availability check
check_docker() {
    if ! command -v docker &>/dev/null; then
        die "Docker not installed. Install with: pkg install docker OR see https://docs.docker.com/engine/install/"
    fi
    if ! docker info &>/dev/null 2>&1; then
        die "Docker daemon not running or not accessible. Start with: dockerd & (or use Termux:Docker)"
    fi
}

case "$CMD" in

  ps)
    check_docker
    FLAG="${2:-}"
    log "ps $FLAG"
    if [ "$FLAG" = "--all" ] || [ "$FLAG" = "-a" ]; then
        docker ps -a --format "table {{.ID}}\t{{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}"
    else
        docker ps --format "table {{.ID}}\t{{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}"
    fi
    ;;

  images)
    check_docker
    log "images"
    docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.ID}}\t{{.Size}}\t{{.CreatedSince}}"
    ;;

  run)
    check_docker
    [ -n "${2:-}" ] || die "Image name required"
    IMAGE="$2"
    shift 2
    log "run $IMAGE $*"
    docker run --rm "$IMAGE" "$@"
    ;;

  exec)
    check_docker
    [ -n "${2:-}" ] || die "Container name/ID required"
    [ -n "${3:-}" ] || die "Command required"
    CONTAINER="$2"
    shift 2
    log "exec $CONTAINER $*"
    docker exec -it "$CONTAINER" "$@"
    ;;

  logs)
    check_docker
    [ -n "${2:-}" ] || die "Container name/ID required"
    CONTAINER="$2"
    TAIL_ARG="${3:-}"
    TAIL_N="100"
    if [ "$TAIL_ARG" = "--tail" ]; then
        TAIL_N="${4:-100}"
    fi
    log "logs $CONTAINER (tail=$TAIL_N)"
    docker logs --tail "$TAIL_N" --timestamps "$CONTAINER"
    ;;

  stop)
    check_docker
    [ -n "${2:-}" ] || die "Container name/ID required"
    log "stop $2"
    docker stop "$2"
    echo "Stopped: $2"
    ;;

  rm)
    check_docker
    [ -n "${2:-}" ] || die "Container name/ID required"
    FORCE="${3:-}"
    log "rm $2 $FORCE"
    if [ "$FORCE" = "--force" ] || [ "$FORCE" = "-f" ]; then
        docker rm -f "$2"
    else
        docker rm "$2"
    fi
    echo "Removed container: $2"
    ;;

  rmi)
    check_docker
    [ -n "${2:-}" ] || die "Image name/ID required"
    FORCE="${3:-}"
    log "rmi $2 $FORCE"
    if [ "$FORCE" = "--force" ] || [ "$FORCE" = "-f" ]; then
        docker rmi -f "$2"
    else
        docker rmi "$2"
    fi
    echo "Removed image: $2"
    ;;

  build)
    check_docker
    PATH_ARG="${2:-.}"
    TAG="${3:-}"
    log "build $PATH_ARG ${TAG:-}"
    if [ -n "$TAG" ]; then
        docker build -t "$TAG" "$PATH_ARG"
    else
        docker build "$PATH_ARG"
    fi
    ;;

  pull)
    check_docker
    [ -n "${2:-}" ] || die "Image name required"
    log "pull $2"
    docker pull "$2"
    ;;

  push)
    check_docker
    [ -n "${2:-}" ] || die "Image name required"
    log "push $2"
    docker push "$2"
    ;;

  inspect)
    check_docker
    [ -n "${2:-}" ] || die "Container or image name/ID required"
    log "inspect $2"
    docker inspect "$2" | python3 -c "import json,sys; print(json.dumps(json.load(sys.stdin), indent=2))"
    ;;

  stats)
    check_docker
    CONTAINER="${2:-}"
    log "stats $CONTAINER"
    if [ -n "$CONTAINER" ]; then
        docker stats --no-stream "$CONTAINER"
    else
        docker stats --no-stream
    fi
    ;;

  networks)
    check_docker
    log "networks"
    docker network ls
    ;;

  volumes)
    check_docker
    log "volumes"
    docker volume ls
    ;;

  compose)
    check_docker
    SUBCMD="${2:-ps}"
    shift 2 || shift $#
    log "compose $SUBCMD $*"
    if command -v docker-compose &>/dev/null; then
        docker-compose "$SUBCMD" "$@"
    elif docker compose version &>/dev/null 2>&1; then
        docker compose "$SUBCMD" "$@"
    else
        die "Docker Compose not available. Install with: pip3 install docker-compose"
    fi
    ;;

  info)
    check_docker
    log "info"
    docker info
    ;;

  prune)
    check_docker
    [[ "${2:-}" == "--confirm" ]] || die "This removes unused containers, images, networks. Pass --confirm to proceed."
    log "prune"
    docker system prune -f
    echo "Pruned unused Docker resources."
    ;;

  help|--help|-h)
    grep '^#' "$0" | grep -v '#!/' | sed 's/^# //' | sed 's/^#//'
    ;;

  *)
    die "Unknown command: $CMD. Run: nation-docker.sh help"
    ;;
esac
