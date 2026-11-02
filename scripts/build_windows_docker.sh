#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
IMAGE_NAME="nai-windows-builder"

if ! docker info >/dev/null 2>&1; then
    echo "Docker Desktop is not running. Start Docker Desktop and retry." >&2
    exit 1
fi

docker build \
    --platform linux/amd64 \
    --file "$PROJECT_ROOT/scripts/windows.Dockerfile" \
    --tag "$IMAGE_NAME" \
    "$PROJECT_ROOT"

docker run --rm \
    --platform linux/amd64 \
    --volume "$PROJECT_ROOT:/workspace" \
    --workdir /workspace \
    "$IMAGE_NAME"
