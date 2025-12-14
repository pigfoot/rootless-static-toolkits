#!/bin/bash
# Wrapper script to launch podman container with volume mounts and environment variables
# This script runs on the host (GitHub Actions runner or local machine)

set -euo pipefail

# Configuration
CONTAINER_IMAGE="${CONTAINER_IMAGE:-docker.io/ubuntu:rolling}"
TOOL="${1:-podman}"
ARCH="${2:-amd64}"
VARIANT="${3:-full}"
VERSION="${VERSION:-latest}"

# Directories
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SCRIPTS_DIR="${REPO_ROOT}/scripts"
BUILD_DIR="${REPO_ROOT}/build"

echo "=== Containerized Build Wrapper ==="
echo "Tool: ${TOOL}"
echo "Architecture: ${ARCH}"
echo "Variant: ${VARIANT}"
echo "Version: ${VERSION}"
echo "Container Image: ${CONTAINER_IMAGE}"
echo ""

# Check if podman is available
if ! command -v podman >/dev/null 2>&1; then
    echo "ERROR: podman is not installed or not in PATH"
    echo "Please install podman: https://podman.io/getting-started/installation"
    exit 1
fi

# Pull container image
echo "Pulling container image: ${CONTAINER_IMAGE}"
podman pull "${CONTAINER_IMAGE}"

# Create build directory if it doesn't exist
mkdir -p "${BUILD_DIR}"

# Run build in container
echo ""
echo "=== Starting containerized build ==="
podman run --rm \
    -v "${SCRIPTS_DIR}:/workspace/scripts:ro,z" \
    -v "${BUILD_DIR}:/workspace/build:rw,z" \
    -e VERSION="${VERSION}" \
    -e TOOL="${TOOL}" \
    -e ARCH="${ARCH}" \
    -e VARIANT="${VARIANT}" \
    "${CONTAINER_IMAGE}" \
    bash -c "
        set -euo pipefail
        echo '=== Inside container ==='
        echo 'Running setup-build-env.sh...'
        /workspace/scripts/container/setup-build-env.sh

        echo ''
        echo '=== Building ${TOOL} ==='
        /workspace/scripts/build-tool.sh ${TOOL} ${ARCH} ${VARIANT}

        echo ''
        echo '=== Packaging ${TOOL} ==='
        /workspace/scripts/package.sh ${TOOL} ${ARCH} ${VARIANT}

        echo ''
        echo '=== Build complete ==='
    "

echo ""
echo "=== Containerized build complete ==="
echo "Artifacts available in: ${BUILD_DIR}/${TOOL}-${ARCH}/"
