#!/usr/bin/env bash
# Smoke test for static and glibc binaries
# Usage: ./scripts/test-static.sh <install-dir> [libc]
# Example: ./scripts/test-static.sh build/podman-amd64/install static
#          ./scripts/test-static.sh build/podman-amd64-glibc/install glibc

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Parse arguments
INSTALL_DIR="${1:-}"
LIBC="${2:-static}"

if [[ -z "$INSTALL_DIR" ]]; then
  echo "Error: Install directory required" >&2
  echo "Usage: $0 <install-dir> [libc]" >&2
  echo "Example: $0 build/podman-amd64/install static" >&2
  echo "         $0 build/podman-amd64-glibc/install glibc" >&2
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
echo "Libc variant: $LIBC"
echo ""

# Test results
PASS_COUNT=0
FAIL_COUNT=0
TOTAL_COUNT=0

# Test function
test_binary() {
  local BINARY_PATH="$1"
  local BINARY_NAME=$(basename "$BINARY_PATH")

  TOTAL_COUNT=$((TOTAL_COUNT + 1))

  echo "----------------------------------------"
  echo "Testing: $BINARY_NAME"
  echo "----------------------------------------"

  # Test 1: Binary exists and is executable
  if [[ ! -x "$BINARY_PATH" ]]; then
    echo "✗ FAIL: Binary not executable"
    FAIL_COUNT=$((FAIL_COUNT + 1))
    return 1
  fi
  echo "✓ Binary is executable"

  # Test 2: Verify linking based on libc variant
  echo "Checking linking (expecting $LIBC)..."
  LDD_OUTPUT=$(ldd "$BINARY_PATH" 2>&1 || true)

  if [[ "$LIBC" == "static" ]]; then
    # Static build should have no dynamic dependencies
    if echo "$LDD_OUTPUT" | grep -q "not a dynamic executable"; then
      echo "✓ Binary is truly static (no dynamic dependencies)"
    elif echo "$LDD_OUTPUT" | grep -q "statically linked"; then
      echo "✓ Binary is statically linked"
    else
      echo "✗ FAIL: Binary has unexpected dynamic dependencies:"
      echo "$LDD_OUTPUT"
      FAIL_COUNT=$((FAIL_COUNT + 1))
      return 1
    fi
  else
    # Glibc build should only have glibc dependencies
    if echo "$LDD_OUTPUT" | grep -qE "libc\.so|ld-linux"; then
      echo "✓ Binary links to glibc dynamically"

      # Verify no other libraries (except linux-vdso.so.1 which is kernel-provided)
      NON_GLIBC_DEPS=$(echo "$LDD_OUTPUT" | grep -v "linux-vdso" | grep -v "libc\.so" | grep -v "ld-linux" | grep "=>" || true)
      if [[ -z "$NON_GLIBC_DEPS" ]]; then
        echo "✓ Only glibc is dynamically linked (as expected)"
      else
        echo "✗ FAIL: Unexpected dynamic dependencies found:"
        echo "$NON_GLIBC_DEPS"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        return 1
      fi
    else
      echo "✗ FAIL: Expected glibc dependencies not found"
      echo "$LDD_OUTPUT"
      FAIL_COUNT=$((FAIL_COUNT + 1))
      return 1
    fi
  fi

  # Test 3: Binary can execute --version (skip if cross-compiled)
  echo "Testing --version..."

  # Detect if binary is cross-compiled
  BINARY_ARCH=$(file "$BINARY_PATH" | grep -oE 'x86-64|aarch64|ARM aarch64' | head -1)
  HOST_ARCH=$(uname -m)

  # Normalize architecture names
  if [[ "$HOST_ARCH" == "x86_64" ]]; then
    HOST_ARCH="x86-64"
  elif [[ "$HOST_ARCH" == "aarch64" ]]; then
    HOST_ARCH="aarch64"
  fi

  if [[ "$BINARY_ARCH" != "$HOST_ARCH" ]] && [[ -n "$BINARY_ARCH" ]]; then
    echo "⊘ SKIP: Binary is cross-compiled ($BINARY_ARCH), cannot execute on $HOST_ARCH host"
  elif VERSION_OUTPUT=$("$BINARY_PATH" --version 2>&1); then
    echo "✓ --version succeeded:"
    echo "  $VERSION_OUTPUT" | head -3
  else
    echo "✗ FAIL: --version failed"
    FAIL_COUNT=$((FAIL_COUNT + 1))
    return 1
  fi

  # Test 4: File info
  echo "Binary info:"
  file "$BINARY_PATH"
  echo "Size: $(du -h "$BINARY_PATH" | cut -f1)"

  PASS_COUNT=$((PASS_COUNT + 1))
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
