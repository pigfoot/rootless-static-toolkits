#!/bin/bash
# Setup build environment inside Ubuntu container
# This script installs all dependencies needed for building static binaries

set -euo pipefail

echo "=== Setting up build environment inside container ==="

# Update package list
echo "Updating package list..."
apt-get update

# Install core build tools
echo "Installing core build tools..."
DEBIAN_FRONTEND=noninteractive apt-get install -y \
    clang \
    llvm \
    musl-dev \
    musl-tools \
    make \
    cmake \
    ninja-build \
    autoconf \
    automake \
    libtool \
    pkg-config \
    git \
    curl \
    wget \
    ca-certificates

# Install language toolchains
echo "Installing Go toolchain..."
DEBIAN_FRONTEND=noninteractive apt-get install -y golang-go

echo "Installing Rust toolchain..."
DEBIAN_FRONTEND=noninteractive apt-get install -y \
    cargo \
    rustc \
    protobuf-compiler

# Install component-specific dependencies
echo "Installing component-specific dependencies..."
DEBIAN_FRONTEND=noninteractive apt-get install -y \
    libglib2.0-dev \
    libcap-dev \
    meson

# Set up Rust musl target for static linking
echo "Setting up Rust musl target..."
if command -v rustup >/dev/null 2>&1; then
    rustup target add x86_64-unknown-linux-musl || true
    rustup target add aarch64-unknown-linux-musl || true
else
    echo "Warning: rustup not available, using system Rust"
fi

# Clean up
echo "Cleaning up package cache..."
apt-get clean
rm -rf /var/lib/apt/lists/*

echo "=== Build environment setup complete ==="
echo "Installed tools:"
echo "  - Clang: $(clang --version | head -n1)"
echo "  - Go: $(go version)"
echo "  - Rust: $(rustc --version)"
echo "  - Cargo: $(cargo --version)"
