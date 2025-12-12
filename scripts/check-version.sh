#!/usr/bin/env bash
# Check if upstream has new version compared to local releases
# Usage: ./scripts/check-version.sh <tool> [repo-owner]
# Example: ./scripts/check-version.sh podman
#          ./scripts/check-version.sh buildah myuser

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Parse arguments
TOOL="${1:-}"
REPO_OWNER="${2:-}"

if [[ -z "$TOOL" ]]; then
  echo "Error: Tool name required" >&2
  echo "Usage: $0 <podman|buildah|skopeo> [repo-owner]" >&2
  exit 1
fi

# Validate tool
case "$TOOL" in
  podman|buildah|skopeo)
    ;;
  *)
    echo "Error: Unsupported tool: $TOOL" >&2
    exit 1
    ;;
esac

# Determine upstream repository
UPSTREAM_REPO="containers/$TOOL"

# Determine local repository (from environment or argument)
if [[ -n "$REPO_OWNER" ]]; then
  LOCAL_REPO="$REPO_OWNER/rootless-static-toolkits"
elif [[ -n "${GITHUB_REPOSITORY:-}" ]]; then
  LOCAL_REPO="$GITHUB_REPOSITORY"
else
  # Try to get from git remote
  LOCAL_REPO=$(git -C "$PROJECT_ROOT" config --get remote.origin.url 2>/dev/null | sed -E 's#https://github.com/([^/]+/[^/]+)(\.git)?#\1#' || echo "")
  if [[ -z "$LOCAL_REPO" ]]; then
    echo "Error: Could not determine local repository" >&2
    echo "Please set GITHUB_REPOSITORY or pass repo-owner as argument" >&2
    exit 1
  fi
fi

echo "Checking versions for: $TOOL"
echo "Upstream: $UPSTREAM_REPO"
echo "Local: $LOCAL_REPO"
echo ""

# Check dependencies
if ! command -v gh &> /dev/null; then
  echo "Error: gh CLI not found" >&2
  exit 1
fi

# Get latest upstream version (excluding pre-releases)
echo "Fetching latest upstream version..."
UPSTREAM_VERSION=$(gh release list \
  --repo "$UPSTREAM_REPO" \
  --limit 50 \
  --exclude-drafts \
  --exclude-pre-releases \
  | grep -v -E '(alpha|beta|rc|RC)' \
  | head -1 \
  | awk '{print $1}')

if [[ -z "$UPSTREAM_VERSION" ]]; then
  echo "Error: Could not fetch upstream version" >&2
  exit 1
fi

echo "Latest upstream: $UPSTREAM_VERSION"

# Normalize version (ensure it starts with 'v')
if [[ ! "$UPSTREAM_VERSION" =~ ^v ]]; then
  UPSTREAM_VERSION="v$UPSTREAM_VERSION"
fi

# Check if this version already exists in local releases
LOCAL_TAG="${TOOL}-${UPSTREAM_VERSION}"
echo "Checking for local release: $LOCAL_TAG"

if gh release view "$LOCAL_TAG" --repo "$LOCAL_REPO" &>/dev/null; then
  echo "✓ Release $LOCAL_TAG already exists"
  echo "NEW_VERSION=false" >> "${GITHUB_OUTPUT:-/dev/null}"
  echo "VERSION=$UPSTREAM_VERSION" >> "${GITHUB_OUTPUT:-/dev/null}"
  exit 0
else
  echo "✗ Release $LOCAL_TAG does not exist"
  echo "NEW_VERSION=true" >> "${GITHUB_OUTPUT:-/dev/null}"
  echo "VERSION=$UPSTREAM_VERSION" >> "${GITHUB_OUTPUT:-/dev/null}"
  echo ""
  echo "New version detected: $UPSTREAM_VERSION"
  echo "Action required: Trigger build for $TOOL $UPSTREAM_VERSION"
  exit 0
fi
