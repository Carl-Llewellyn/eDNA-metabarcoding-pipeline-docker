#!/usr/bin/env bash
# run.sh - start a persistent edna container if missing, otherwise enter it.
# Usage:
#   ./run.sh [--data HOST[:CONTAINER]] [--blastdb HOST[:CONTAINER]] [HOST_DATA_DIR]
#
# Behavior:
# - If image edna_pipeline:latest is missing, instructs to build it.
# - If container 'edna_session' doesn't exist -> creates detached container (sleep infinity) with host data mounted to /opt/eDNA/01_eDNA
#   and /data/blastdb mounted to /opt/eDNA/blastdb.
# - If container exists but stopped -> starts it.
# - If container is running -> just exec a shell into it.
#
# Notes:
# - The container is created with --restart unless-stopped so it survives reboots.
# - To force recreate, remove the container first: docker rm -f edna_session

set -euo pipefail

CONTAINER_NAME="edna_session"
IMAGE_NAME="edna_pipeline:latest"
HOST_DATA="/home/deegc@ENT/Documents/01_eDNA"
CONTAINER_DATA="/opt/eDNA/01_eDNA"
HOST_BLASTDB="/data/blastdb"
CONTAINER_BLASTDB="/opt/eDNA/blastdb"
BLASTDB_ENV="/opt/eDNA/blastdb/ntdatabase:/opt/eDNA/blastdb/IYS_APC"
BLASTDB_MOUNT=""
WORKDIR="/opt/eDNA"

print_usage() {
  cat <<EOF
Usage: $0 [--data HOST[:CONTAINER]] [--blastdb HOST[:CONTAINER]] [--blastdb-env VALUE] [HOST_DATA_DIR]

Options:
  --data HOST[:CONTAINER]    Host data path to mount (default: ${HOST_DATA} -> ${CONTAINER_DATA})
  --blastdb HOST[:CONTAINER] Host BLAST DB path to mount (default: ${HOST_BLASTDB} -> ${CONTAINER_BLASTDB})
  --blastdb-env VALUE        BLASTDB env value (default: ${BLASTDB_ENV})
EOF
  exit 1
}

HOST_DATA_SET=0
while [ $# -gt 0 ]; do
  case "$1" in
    --data)
      HOST_DATA="$2"; HOST_DATA_SET=1; shift 2;;
    --blastdb)
      BLASTDB_MOUNT="$2"; shift 2;;
    --blastdb-env)
      BLASTDB_ENV="$2"; shift 2;;
    -h|--help)
      print_usage;;
    *)
      if [ $HOST_DATA_SET -eq 0 ]; then
        HOST_DATA="$1"; HOST_DATA_SET=1; shift
      else
        echo "Unknown arg: $1"; print_usage
      fi
      ;;
  esac
done

if [[ "$HOST_DATA" == *:* ]]; then
  CONTAINER_DATA="${HOST_DATA#*:}"
  HOST_DATA="${HOST_DATA%%:*}"
fi
if [ -n "$BLASTDB_MOUNT" ]; then
  if [[ "$BLASTDB_MOUNT" == *:* ]]; then
    HOST_BLASTDB="${BLASTDB_MOUNT%%:*}"
    CONTAINER_BLASTDB="${BLASTDB_MOUNT#*:}"
  else
    HOST_BLASTDB="$BLASTDB_MOUNT"
  fi
fi

# Ensure host data dir exists (create if necessary)
if [ ! -d "$HOST_DATA" ]; then
  echo "Host data directory '$HOST_DATA' does not exist — creating it."
  mkdir -p "$HOST_DATA"
fi
if [ ! -d "$HOST_BLASTDB" ]; then
  echo "ERROR: Host BLAST DB directory '$HOST_BLASTDB' does not exist."
  exit 2
fi

# Check image exists
if ! docker image inspect "$IMAGE_NAME" >/dev/null 2>&1; then
  echo "ERROR: Docker image '$IMAGE_NAME' not found."
  echo "Build it first (example): ./setup_edna.sh build --micromamba-file micromamba-2.4.0-1.tar.bz2"
  exit 1
fi

# Helper to check container state
container_exists() {
  docker ps -a --filter "name=^/${CONTAINER_NAME}$" --format '{{.ID}}' | grep -q .
}

container_is_running() {
  docker ps --filter "name=^/${CONTAINER_NAME}$" --filter "status=running" --format '{{.ID}}' | grep -q . || return 1
}

# Create the container if it doesn't exist
if ! container_exists; then
  echo "Creating and starting container '${CONTAINER_NAME}' (detached)..."
  docker run -d \
    --name "${CONTAINER_NAME}" \
    -v "${HOST_DATA}:${CONTAINER_DATA}" \
    -v "${HOST_BLASTDB}:${CONTAINER_BLASTDB}" \
    -e "BLASTDB=${BLASTDB_ENV}" \
    -w "${WORKDIR}" \
    --restart unless-stopped \
    "${IMAGE_NAME}" \
    sleep infinity
  echo "Container '${CONTAINER_NAME}' created."
else
  # If exists but not running, start it
  if ! container_is_running; then
    echo "Container '${CONTAINER_NAME}' exists but is stopped — starting..."
    docker start "${CONTAINER_NAME}"
    echo "Container started."
  else
    echo "Container '${CONTAINER_NAME}' is already running."
  fi
fi

# Exec into the running container when a TTY is available.
if [ -t 0 ]; then
  echo "Entering container '${CONTAINER_NAME}'. To detach, exit the shell (container keeps running)."
  docker exec -it "${CONTAINER_NAME}" bash
else
  echo "Container '${CONTAINER_NAME}' is running. No TTY available; skipping interactive exec."
fi
