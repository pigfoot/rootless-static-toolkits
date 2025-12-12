# Makefile for rootless-static-toolkits
# Build static container tools: podman, buildah, skopeo

.PHONY: help build test clean install-deps

# Tools
TOOLS := podman buildah skopeo
ARCHES := amd64 arm64

# Default target
help:
	@echo "Available targets:"
	@echo "  build           - Build all tools for all architectures"
	@echo "  build-<tool>    - Build specific tool (podman, buildah, skopeo)"
	@echo "  test            - Run smoke tests on built binaries"
	@echo "  clean           - Remove build artifacts"
	@echo "  install-deps    - Install build dependencies (Zig, Go, cosign)"
	@echo ""
	@echo "Examples:"
	@echo "  make build-podman"
	@echo "  make test"

# Build all tools
build:
	@for tool in $(TOOLS); do \
		$(MAKE) build-$$tool; \
	done

# Build specific tool
build-podman:
	@echo "Building podman..."
	@./scripts/build-tool.sh podman

build-buildah:
	@echo "Building buildah..."
	@./scripts/build-tool.sh buildah

build-skopeo:
	@echo "Building skopeo..."
	@./scripts/build-tool.sh skopeo

# Run smoke tests
test:
	@echo "Running smoke tests..."
	@./scripts/test-static.sh

# Clean build artifacts
clean:
	@echo "Cleaning build artifacts..."
	@rm -rf build/mimalloc/build
	@rm -rf build/*-*/
	@rm -f *.tar.zst
	@rm -f *.sig
	@rm -f checksums.txt

# Install build dependencies
install-deps:
	@echo "Installing build dependencies..."
	@echo "Note: This requires sudo for system package installation"
	@command -v zig >/dev/null 2>&1 || { echo "Installing Zig..."; curl -L https://ziglang.org/download/0.11.0/zig-linux-x86_64-0.11.0.tar.xz | tar -xJ -C /tmp && sudo mv /tmp/zig-linux-x86_64-0.11.0 /usr/local/zig && sudo ln -sf /usr/local/zig/zig /usr/local/bin/zig; }
	@command -v go >/dev/null 2>&1 || { echo "Installing Go..."; curl -L https://go.dev/dl/go1.21.5.linux-amd64.tar.gz | sudo tar -xz -C /usr/local; }
	@command -v cosign >/dev/null 2>&1 || { echo "Installing cosign..."; curl -L https://github.com/sigstore/cosign/releases/latest/download/cosign-linux-amd64 -o /tmp/cosign && sudo install /tmp/cosign /usr/local/bin/cosign; }
	@command -v cmake >/dev/null 2>&1 || { echo "Please install cmake: sudo apt install cmake / brew install cmake"; }
	@command -v ninja >/dev/null 2>&1 || { echo "Please install ninja: sudo apt install ninja-build / brew install ninja"; }
	@command -v gh >/dev/null 2>&1 || { echo "Please install gh CLI manually: https://cli.github.com/"; }
	@echo "Dependencies installed. Please ensure cmake, ninja, and 'gh' CLI are available."
