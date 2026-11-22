#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
IMAGE_REF="${1:-}"
ARCHIVE_PLATFORM="${ARCHIVE_PLATFORM:-linux/amd64}"
PUBLISH_PLATFORMS="${PUBLISH_PLATFORMS:-linux/amd64,linux/arm64}"

if [[ ! "$IMAGE_REF" =~ ^ghcr\.io/[a-z0-9][a-z0-9-]*/[a-z0-9._-]+:[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}$ ]]; then
    echo "Usage: $0 ghcr.io/OWNER/REPOSITORY:tag" >&2
    exit 2
fi

if ! docker info >/dev/null 2>&1; then
    echo "Docker Engine is unavailable. Run this script on a host with Docker Engine." >&2
    exit 1
fi

IMAGE_PATH="${IMAGE_REF#ghcr.io/}"
IMAGE_NAME="${IMAGE_PATH##*/}"
IMAGE_TAG="${IMAGE_NAME##*:}"
IMAGE_BASENAME="${IMAGE_NAME/:/-}"
OCI_SOURCE_URL="${OCI_SOURCE_URL:-https://github.com/${IMAGE_PATH%/*}/${IMAGE_NAME%:*}}"
IMAGE_ARCHIVE="$PROJECT_DIR/${IMAGE_BASENAME}.tar.gz"
IMAGE_ARCHIVE_TMP="$IMAGE_ARCHIVE.tmp"
trap 'rm -f "$IMAGE_ARCHIVE_TMP"' EXIT

echo "Building an archive image for $ARCHIVE_PLATFORM..."
docker buildx build --platform "$ARCHIVE_PLATFORM" --pull \
    --build-arg "OCI_SOURCE_URL=$OCI_SOURCE_URL" \
    --tag "$IMAGE_REF" --load "$PROJECT_DIR"

echo "Saving a portable archive to $IMAGE_ARCHIVE..."
docker image save "$IMAGE_REF" | gzip -c > "$IMAGE_ARCHIVE_TMP"
mv "$IMAGE_ARCHIVE_TMP" "$IMAGE_ARCHIVE"
trap - EXIT

echo "Building and pushing $IMAGE_REF for $PUBLISH_PLATFORMS..."
docker buildx build --platform "$PUBLISH_PLATFORMS" --pull \
    --build-arg "OCI_SOURCE_URL=$OCI_SOURCE_URL" \
    --tag "$IMAGE_REF" --push "$PROJECT_DIR"

echo "Published $IMAGE_REF ($PUBLISH_PLATFORMS)"
