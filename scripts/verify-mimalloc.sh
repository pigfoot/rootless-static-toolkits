#!/bin/bash
# Verify that mimalloc is actually being used in built binaries
# Usage: ./scripts/verify-mimalloc.sh <binary-path>

set -euo pipefail

BINARY="${1:-}"

if [[ -z "$BINARY" ]]; then
  echo "Usage: $0 <binary-path>"
  echo "Example: $0 build/podman-amd64/install/bin/podman"
  exit 1
fi

if [[ ! -f "$BINARY" ]]; then
  echo "Error: Binary not found: $BINARY"
  exit 1
fi

echo "========================================"
echo "Verifying mimalloc usage in: $BINARY"
echo "========================================"

# Method 1: Check for mimalloc symbols in the binary
echo ""
echo "Method 1: Checking for mimalloc symbols..."
if nm "$BINARY" 2>/dev/null | grep -q "mi_malloc\|mi_free\|mimalloc"; then
  echo "✓ Found mimalloc symbols in binary"
  nm "$BINARY" 2>/dev/null | grep "mi_malloc\|mi_free" | head -5
else
  echo "✗ No mimalloc symbols found"
  echo "Note: Symbols may be stripped (-s flag), this is expected"
fi

# Method 2: Check for mimalloc strings in binary
echo ""
echo "Method 2: Checking for mimalloc strings..."
if strings "$BINARY" | grep -qi "mimalloc"; then
  echo "✓ Found mimalloc references in binary"
  strings "$BINARY" | grep -i "mimalloc" | head -3
else
  echo "✗ No mimalloc strings found"
fi

# Method 3: Runtime test (if binary is executable)
echo ""
echo "Method 3: Runtime verification..."
echo "Running: MIMALLOC_VERBOSE=1 $BINARY --version"
echo ""

# Capture output
OUTPUT=$(MIMALLOC_VERBOSE=1 "$BINARY" --version 2>&1)

if echo "$OUTPUT" | grep -q "mimalloc: process init"; then
  echo ""
  echo "✓✓✓ SUCCESS: mimalloc is ACTIVE!"
  echo ""
  echo "mimalloc initialization output:"
  echo "$OUTPUT" | grep -i "mimalloc" | head -15
else
  echo ""
  echo "⚠ WARNING: No mimalloc initialization detected"
  echo ""
  echo "Possible causes:"
  echo "  1. Binary doesn't support --version flag"
  echo "  2. mimalloc was not linked with --whole-archive"
  echo "  3. musl's malloc is still being used"
  echo ""
  echo "Output:"
  echo "$OUTPUT"
fi

echo ""
echo "========================================"
echo "Verification complete"
echo "========================================"
