#!/usr/bin/env bash
# Sign release artifacts with checksums and cosign signatures
# Usage: ./scripts/sign-release.sh <release-dir>
# Example: ./scripts/sign-release.sh ./release-artifacts
#
# This script:
# 1. Generates SHA256 checksums for all *.tar.zst files → checksums.txt
# 2. Signs each tarball with cosign (keyless OIDC) → *.tar.zst.bundle
# 3. Signs checksums.txt itself → checksums.txt.bundle

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Parse arguments
RELEASE_DIR="${1:-}"

if [[ -z "$RELEASE_DIR" ]]; then
  echo "Error: Release directory required" >&2
  echo "Usage: $0 <release-dir>" >&2
  echo "Example: $0 ./release-artifacts" >&2
  exit 1
fi

if [[ ! -d "$RELEASE_DIR" ]]; then
  echo "Error: Release directory not found: $RELEASE_DIR" >&2
  exit 1
fi

# Convert to absolute path
RELEASE_DIR="$(cd "$RELEASE_DIR" && pwd)"

echo "========================================"
echo "Signing Release Artifacts"
echo "Release Directory: $RELEASE_DIR"
echo "========================================"

# Step 1: Generate SHA256 checksums
echo ""
echo "Step 1: Generating SHA256 checksums..."
CHECKSUMS_FILE="$RELEASE_DIR/checksums.txt"

# Remove existing checksums file
rm -f "$CHECKSUMS_FILE"

# Find all tar.zst files and generate checksums
cd "$RELEASE_DIR"
TARBALL_COUNT=0
while IFS= read -r -d '' tarball; do
  BASENAME=$(basename "$tarball")
  echo "  Checksumming: $BASENAME"
  SHA256=$(sha256sum "$tarball" | awk '{print $1}')
  echo "$SHA256  $BASENAME" >> "$CHECKSUMS_FILE"
  TARBALL_COUNT=$((TARBALL_COUNT + 1))
done < <(find . -maxdepth 1 -name "*.tar.zst" -type f -print0 | sort -z)

if [[ $TARBALL_COUNT -eq 0 ]]; then
  echo "Error: No *.tar.zst files found in $RELEASE_DIR" >&2
  exit 1
fi

echo ""
echo "✓ Generated checksums for $TARBALL_COUNT file(s):"
cat "$CHECKSUMS_FILE"

# Step 2: Sign with cosign (keyless signing using GitHub OIDC)
echo ""
echo "Step 2: Signing artifacts with cosign..."

# Check if cosign is available
if ! command -v cosign &> /dev/null; then
  echo "⚠ Warning: cosign not found, skipping signature generation" >&2
  echo "  Install cosign: https://docs.sigstore.dev/cosign/installation/" >&2
  echo ""
  echo "✓ Checksums-only release prepared (cosign signatures skipped)"
  exit 0
fi

# Check cosign version
COSIGN_VERSION=$(cosign version 2>&1 | grep -oP 'v\K[0-9.]+' | head -1 || echo "unknown")
echo "Cosign version: $COSIGN_VERSION"

# Check if running in GitHub Actions with OIDC token
if [[ -z "${ACTIONS_ID_TOKEN_REQUEST_TOKEN:-}" ]]; then
  echo "⚠ Warning: Not running in GitHub Actions with OIDC, skipping cosign signing" >&2
  echo "  Cosign keyless signing requires GitHub Actions OIDC token" >&2
  echo "  See: https://docs.sigstore.dev/cosign/github_actions/" >&2
  echo ""
  echo "✓ Checksums-only release prepared (cosign signatures skipped)"
  exit 0
fi

echo "Running in GitHub Actions (OIDC mode)"
echo "  Repository: ${GITHUB_REPOSITORY:-unknown}"
echo "  Workflow: ${GITHUB_WORKFLOW:-unknown}"
echo "  Run ID: ${GITHUB_RUN_ID:-unknown}"
echo ""

# Sign each tarball with cosign
SUCCESS_COUNT=0
FAIL_COUNT=0

while IFS= read -r -d '' tarball; do
  BASENAME=$(basename "$tarball")
  BUNDLE_FILE="${BASENAME}.bundle"

  echo "  Signing: $BASENAME"

  # Use cosign sign-blob with --bundle for keyless signing
  # --bundle creates a file containing signature + certificate + transparency log entry
  # --yes skips confirmation prompts in automated environments
  if cosign sign-blob \
    --bundle="$BUNDLE_FILE" \
    --yes \
    "$tarball" > /dev/null 2>&1; then

    echo "    ✓ Bundle: $BUNDLE_FILE"
    SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
  else
    echo "    ✗ Failed to sign $BASENAME" >&2
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
done < <(find . -maxdepth 1 -name "*.tar.zst" -type f -print0 | sort -z)

if [[ $FAIL_COUNT -gt 0 ]]; then
  echo ""
  echo "⚠ Warning: Some files failed to sign" >&2
fi

echo ""
echo "✓ Signed $SUCCESS_COUNT tarball(s), $FAIL_COUNT failed"

# Step 3: Sign the checksums file itself
echo ""
echo "Step 3: Signing checksums file..."
CHECKSUMS_BUNDLE="$CHECKSUMS_FILE.bundle"

if cosign sign-blob \
  --bundle="$CHECKSUMS_BUNDLE" \
  --yes \
  "$CHECKSUMS_FILE" > /dev/null 2>&1; then

  echo "  ✓ Checksums bundle: $(basename "$CHECKSUMS_BUNDLE")"
else
  echo "  ✗ Failed to sign checksums file" >&2
  FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# Summary
echo ""
echo "========================================"
echo "Release Signing Complete"
echo "========================================"
echo ""
echo "Files created:"
echo "  - checksums.txt (SHA256 hashes for $TARBALL_COUNT tarball(s))"

if [[ -f "$CHECKSUMS_BUNDLE" ]]; then
  echo "  - checksums.txt.bundle (cosign signature + certificate)"
fi

while IFS= read -r -d '' bundle; do
  echo "  - $(basename "$bundle")"
done < <(find . -maxdepth 1 -name "*.tar.zst.bundle" -type f -print0 | sort -z)

echo ""
echo "Verification commands:"
echo ""
echo "# Verify checksums:"
echo "  sha256sum -c checksums.txt --ignore-missing"
echo ""
echo "# Verify cosign signature (example - replace with actual filename):"
echo "  cosign verify-blob \\"
echo "    --bundle=podman-v5.7.1-linux-amd64-static.tar.zst.bundle \\"
echo "    --certificate-identity-regexp='https://github.com/.*' \\"
echo "    --certificate-oidc-issuer='https://token.actions.githubusercontent.com' \\"
echo "    podman-v5.7.1-linux-amd64-static.tar.zst"
echo ""

if [[ $FAIL_COUNT -gt 0 ]]; then
  exit 1
fi
