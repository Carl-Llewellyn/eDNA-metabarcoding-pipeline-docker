#!/usr/bin/env bash
# setup_edna.sh
# Build and run helper for edna_pipeline Docker image.
# - Uses a locally-provided micromamba tarball in the build context (default: micromamba-2.4.0-1.tar.bz2)
# - Ensures the image contains pipeline files at /opt/eDNA (not hidden by mount)
# - Default mount behavior will mount /home/deegc@ENT/Documents/01_eDNA into /opt/eDNA/01_eDNA
#   and /data/blastdb into /opt/eDNA/blastdb to avoid hiding the repo.
#
# Usage:
#   ./setup_edna.sh build [--tag TAG] [--micromamba-file FILE] [--megan-file FILE] [--no-cache]
#   ./setup_edna.sh run   [--tag TAG] [--micromamba-file FILE] [--mount HOST[:CONTAINER]] [--blastdb HOST[:CONTAINER]] [--megan-file FILE] [--no-cache]
#   ./setup_edna.sh build-and-run ...
#
# Examples:
#   ./setup_edna.sh build --micromamba-file micromamba-2.4.0-1.tar.bz2
#   ./setup_edna.sh run --mount "/home/deegc@ENT/Documents/01_eDNA" --megan-file MEGAN_Community_unix_6_25_10.sh  # mounts to /opt/eDNA/01_eDNA
#   ./setup_edna.sh run --blastdb "/data/blastdb" --mount "/host/path:/opt/eDNA/01_eDNA"

set -euo pipefail

TAG="edna_pipeline:latest"
MICROMAMBA_FILE="micromamba-2.4.0-1.tar.bz2"
MEGAN_INSTALLER_FILE="MEGAN_Community_unix_6_25_10.sh"
MOUNT=""
NO_CACHE=0
ACTION=""
BLASTDB_HOST="/data/blastdb"
BLASTDB_CONTAINER="/opt/eDNA/blastdb"
BLASTDB_MOUNT=""

print_usage() {
  cat <<EOF
Usage: $0 <build|run|build-and-run> [options]

Options:
  --tag TAG                Image tag (default: ${TAG})
  --micromamba-file FILE   Local micromamba tar.bz2 filename (default: ${MICROMAMBA_FILE})
  --megan-file FILE        MEGAN installer .sh filename in build context (default: MEGAN_Community_unix_6_25_10.sh)
  --mount HOST[:CONTAINER] Mount host path into container.
                            If only HOST is provided, it will be mounted into /opt/eDNA/01_eDNA.
                            If HOST:CONTAINER is provided, the provided container path will be used,
                            but mounting directly over /opt/eDNA is refused to avoid hiding repo.
  --blastdb HOST[:CONTAINER] Host BLAST DB path to mount (default: /data/blastdb -> /opt/eDNA/blastdb)
  --no-cache               Pass --no-cache to docker build (force fresh build)
EOF
  exit 1
}

if [ $# -lt 1 ]; then print_usage; fi
ACTION="$1"; shift || true

while [ $# -gt 0 ]; do
  case "$1" in
    --tag) TAG="$2"; shift 2;;
    --micromamba-file) MICROMAMBA_FILE="$2"; shift 2;;
    --megan-file) MEGAN_INSTALLER_FILE="$2"; shift 2;;
    --mount) MOUNT="$2"; shift 2;;
    --blastdb) BLASTDB_MOUNT="$2"; shift 2;;
    --no-cache) NO_CACHE=1; shift;;
    -h|--help) print_usage;;
    *) echo "Unknown arg: $1"; print_usage;;
  esac
done

# Basic docker checks
if ! command -v docker >/dev/null 2>&1; then
  echo "ERROR: docker not found in PATH"; exit 2
fi
if ! docker info >/dev/null 2>&1; then
  echo "ERROR: Docker daemon not running or inaccessible"; exit 3
fi

image_exists() { docker image inspect "$TAG" >/dev/null 2>&1; }

ensure_micromamba_present() {
  if [ -f "$MICROMAMBA_FILE" ]; then
    echo "Using micromamba file: $MICROMAMBA_FILE"
    return 0
  fi
  echo "ERROR: micromamba file '${MICROMAMBA_FILE}' not found in current directory."
  echo "Place your micromamba tar.bz2 in this directory or pass --micromamba-file."
  exit 4
}

build_image() {
  ensure_micromamba_present
  if [ ! -f "$MEGAN_INSTALLER_FILE" ]; then
    echo "ERROR: MEGAN installer file '${MEGAN_INSTALLER_FILE}' not found in current directory."
    exit 7
  fi
  BUILD_ARGS=(--build-arg REPO_REF="5e509b4f46eb67e32a90bfb38ffbd1c61d2a050b" --build-arg MICROMAMBA_FILE="${MICROMAMBA_FILE}" --build-arg MEGAN_INSTALLER_FILE="${MEGAN_INSTALLER_FILE}")
  if [ $NO_CACHE -eq 1 ]; then NO_CACHE_ARG="--no-cache"; else NO_CACHE_ARG=""; fi
  echo "Building Docker image '${TAG}' (micromamba file: ${MICROMAMBA_FILE})..."
  docker build $NO_CACHE_ARG --progress=plain "${BUILD_ARGS[@]}" -t "${TAG}" .
}

# Validate mount target: default to /opt/eDNA/01_eDNA if only host path provided.
prepare_mount_args() {
  if [ -z "$MOUNT" ]; then
    MOUNT="/home/deegc@ENT/Documents/01_eDNA"
  fi

  # If mount string contains ":", treat as host:container. Otherwise treat as host and mount to /opt/eDNA/01_eDNA
  if [[ "$MOUNT" == *:* ]]; then
    HOST_PART="${MOUNT%%:*}"
    CONTAINER_PART="${MOUNT#*:}"
    if [ -z "$HOST_PART" ] || [ -z "$CONTAINER_PART" ]; then
      echo "ERROR: Invalid --mount argument. Use HOST or HOST:CONTAINER"; exit 5
    fi
  else
    HOST_PART="$MOUNT"
    CONTAINER_PART="/opt/eDNA/01_eDNA"
  fi

  # Prevent accidental mount over /opt/eDNA root which would hide repo files
  if [ "$CONTAINER_PART" = "/opt/eDNA" ] || [ "$CONTAINER_PART" = "/opt/eDNA/" ]; then
    echo "ERROR: Refusing to mount over /opt/eDNA (this would hide the repository in the image)."
    echo "Mount into /opt/eDNA/01_eDNA or a subfolder instead."
    exit 6
  fi

  # build Docker -v argument
  MOUNT_ARG=(-v "${HOST_PART}:${CONTAINER_PART}")
}

run_container() {
  if ! image_exists; then
    echo "Image '${TAG}' not found locally — building now..."
    build_image
  else
    echo "Image found locally: ${TAG}"
  fi

  prepare_mount_args
  if [ -n "$BLASTDB_MOUNT" ]; then
    if [[ "$BLASTDB_MOUNT" == *:* ]]; then
      BLASTDB_HOST="${BLASTDB_MOUNT%%:*}"
      BLASTDB_CONTAINER="${BLASTDB_MOUNT#*:}"
    else
      BLASTDB_HOST="$BLASTDB_MOUNT"
    fi
  fi
  if [ ! -d "$BLASTDB_HOST" ]; then
    echo "ERROR: Host BLAST DB directory '$BLASTDB_HOST' does not exist."
    exit 7
  fi

  echo "Running container from image ${TAG}"
  RUN_ARGS=(--rm -it)
  if [ ${#MOUNT_ARG[@]} -gt 0 ]; then
    RUN_ARGS+=("${MOUNT_ARG[@]}")
    echo "Mounting host -> container: ${MOUNT_ARG[*]}"
  fi
  RUN_ARGS+=(-v "${BLASTDB_HOST}:${BLASTDB_CONTAINER}")

  # Start interactive shell with working dir at /opt/eDNA
  docker run "${RUN_ARGS[@]}" -w /opt/eDNA "${TAG}"
}

case "$ACTION" in
  build) build_image;;
  run) run_container;;
  build-and-run) build_image && run_container;;
  *) print_usage;;
esac
