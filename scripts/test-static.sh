#!/usr/bin/env bash
# Smoke test for static binaries
# Usage: ./scripts/test-static.sh <install-dir>
# Example: ./scripts/test-static.sh build/podman-amd64/install

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Parse arguments
INSTALL_DIR="${1:-}"

if [[ -z "$INSTALL_DIR" ]]; then
  echo "Error: Install directory required" >&2
  echo "Usage: $0 <install-dir>" >&2
  echo "Example: $0 build/podman-amd64/install" >&2
  exit 1
fi

if [[ ! -d "$INSTALL_DIR/bin" ]]; then
  echo "Error: Directory not found: $INSTALL_DIR/bin" >&2
  exit 1
fi

echo "========================================"
echo "Running Smoke Tests"
echo "========================================"
echo "Install directory: $INSTALL_DIR"
echo ""

# Test results
PASS_COUNT=0
FAIL_COUNT=0
TOTAL_COUNT=0

# Test function
test_binary() {
  local BINARY_PATH="$1"
  local BINARY_NAME=$(basename "$BINARY_PATH")

  ((TOTAL_COUNT++))

  echo "----------------------------------------"
  echo "Testing: $BINARY_NAME"
  echo "----------------------------------------"

  # Test 1: Binary exists and is executable
  if [[ ! -x "$BINARY_PATH" ]]; then
    echo "✗ FAIL: Binary not executable"
    ((FAIL_COUNT++))
    return 1
  fi
  echo "✓ Binary is executable"

  # Test 2: Binary is static (no dynamic dependencies)
  echo "Checking static linking..."
  LDD_OUTPUT=$(ldd "$BINARY_PATH" 2>&1 || true)

  if echo "$LDD_OUTPUT" | grep -q "not a dynamic executable"; then
    echo "✓ Binary is truly static (no dynamic dependencies)"
  elif echo "$LDD_OUTPUT" | grep -q "statically linked"; then
    echo "✓ Binary is statically linked"
  else
    echo "✗ FAIL: Binary has dynamic dependencies:"
    echo "$LDD_OUTPUT"
    ((FAIL_COUNT++))
    return 1
  fi

  # Test 3: Binary can execute --version
  echo "Testing --version..."
  if VERSION_OUTPUT=$("$BINARY_PATH" --version 2>&1); then
    echo "✓ --version succeeded:"
    echo "  $VERSION_OUTPUT" | head -3
  else
    echo "✗ FAIL: --version failed"
    ((FAIL_COUNT++))
    return 1
  fi

  # Test 4: File info
  echo "Binary info:"
  file "$BINARY_PATH"
  echo "Size: $(du -h "$BINARY_PATH" | cut -f1)"

  ((PASS_COUNT++))
  echo "✓ All tests passed for $BINARY_NAME"
  echo ""
}

# Find and test all binaries
echo "Scanning for binaries in $INSTALL_DIR/bin/..."
echo ""

BINARIES=()
while IFS= read -r -d '' binary; do
  BINARIES+=("$binary")
done < <(find "$INSTALL_DIR/bin" -type f -executable -print0)

if [[ ${#BINARIES[@]} -eq 0 ]]; then
  echo "Error: No binaries found in $INSTALL_DIR/bin/" >&2
  exit 1
fi

echo "Found ${#BINARIES[@]} binaries to test"
echo ""

# Test each binary
for binary in "${BINARIES[@]}"; do
  test_binary "$binary" || true
done

# Summary
echo "========================================"
echo "Test Summary"
echo "========================================"
echo "Total binaries: $TOTAL_COUNT"
echo "Passed: $PASS_COUNT"
echo "Failed: $FAIL_COUNT"
echo ""

if [[ $FAIL_COUNT -gt 0 ]]; then
  echo "✗ Some tests failed"
  exit 1
else
  echo "✓ All tests passed"
  exit 0
fi
