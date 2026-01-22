#!/usr/bin/env bash
# delete_and_rebuild_container.sh - remove the persistent container and rebuild the image.
# Usage:
#   ./delete_and_rebuild_container.sh [--megan-file FILE] [--micromamba-file FILE] [--tag TAG] [--no-cache]

set -euo pipefail

TAG="edna_pipeline:latest"
MICROMAMBA_FILE="micromamba-2.4.0-1.tar.bz2"
MEGAN_INSTALLER_FILE="MEGAN_Community_unix_6_25_10.sh"
NO_CACHE=0
CONTAINER_NAME="edna_session"

print_usage() {
  cat <<EOF
Usage: $0 [options]

Options:
  --tag TAG                Image tag (default: ${TAG})
  --micromamba-file FILE   Local micromamba tar.bz2 filename (default: ${MICROMAMBA_FILE})
  --megan-file FILE        MEGAN installer .sh filename in build context (default: MEGAN_Community_unix_6_25_10.sh)
  --no-cache               Pass --no-cache to docker build (force fresh build)
EOF
  exit 1
}

while [ $# -gt 0 ]; do
  case "$1" in
    --tag) TAG="$2"; shift 2;;
    --micromamba-file) MICROMAMBA_FILE="$2"; shift 2;;
    --megan-file) MEGAN_INSTALLER_FILE="$2"; shift 2;;
    --no-cache) NO_CACHE=1; shift;;
    -h|--help) print_usage;;
    *) echo "Unknown arg: $1"; print_usage;;
  esac
done

if ! command -v docker >/dev/null 2>&1; then
  echo "ERROR: docker not found in PATH"; exit 2
fi
if ! docker info >/dev/null 2>&1; then
  echo "ERROR: Docker daemon not running or inaccessible"; exit 3
fi

if [ ! -f "$MEGAN_INSTALLER_FILE" ]; then
  echo "ERROR: MEGAN installer file '${MEGAN_INSTALLER_FILE}' not found in current directory."
  exit 4
fi

if docker ps -a --filter "name=^/${CONTAINER_NAME}$" --format '{{.ID}}' | grep -q .; then
  echo "Removing container '${CONTAINER_NAME}'..."
  docker rm -f "${CONTAINER_NAME}"
else
  echo "Container '${CONTAINER_NAME}' not found; skipping removal."
fi

if docker image inspect "${TAG}" >/dev/null 2>&1; then
  echo "Removing image '${TAG}'..."
  docker rmi "${TAG}"
else
  echo "Image '${TAG}' not found; skipping removal."
fi

BUILD_ARGS=(build --tag "${TAG}" --micromamba-file "${MICROMAMBA_FILE}" --megan-file "${MEGAN_INSTALLER_FILE}")
if [ $NO_CACHE -eq 1 ]; then BUILD_ARGS+=(--no-cache); fi

echo "Rebuilding image..."
./setup_edna.sh "${BUILD_ARGS[@]}"
