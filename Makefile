# Makefile for Static Container Tools Build System
# Containerized builds using podman + ubuntu:rolling

SHELL := /bin/bash
.SHELLFLAGS := -o pipefail -c

# Default configuration
CONTAINER_IMAGE := docker.io/ubuntu:latest
ARCH := amd64
LIBC := static
VERSION ?= latest

# Directories
REPO_ROOT := $(shell pwd)
SCRIPTS_DIR := $(REPO_ROOT)/scripts
BUILD_DIR := $(REPO_ROOT)/build

# Volume mount options for SELinux compatibility
MOUNT_SCRIPTS := -v $(SCRIPTS_DIR):/workspace/scripts:ro,z
MOUNT_BUILD := -v $(BUILD_DIR):/workspace/build:rw,z

# Container runtime
PODMAN := podman

.PHONY: help
help: ## Show this help message
	@echo "Static Container Tools Build System"
	@echo ""
	@echo "Available targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-20s %s\n", $$1, $$2}'

.PHONY: pull-image
pull-image: ## Pull the build container image
	$(PODMAN) pull $(CONTAINER_IMAGE)

.PHONY: build-podman
build-podman: pull-image ## Build podman (full variant by default)
	@echo "Building podman for $(ARCH) ($(LIBC))..."
	$(PODMAN) run --rm \
		$(MOUNT_SCRIPTS) \
		$(MOUNT_BUILD) \
		-e VERSION=$(VERSION) \
		-e TOOL=podman \
		-e ARCH=$(ARCH) \
		-e VARIANT=full \
		-e LIBC=$(LIBC) \
		$(CONTAINER_IMAGE) \
		bash -c " \
			/workspace/scripts/container/setup-build-env.sh && \
			{ [ -f /etc/profile.d/go.sh ] && source /etc/profile.d/go.sh; } || true && \
			{ [ -f /etc/profile.d/llvm.sh ] && source /etc/profile.d/llvm.sh; } || true && \
			{ [ -f /etc/profile.d/cmake.sh ] && source /etc/profile.d/cmake.sh; } || true && \
			{ [ -f /etc/profile.d/uv.sh ] && source /etc/profile.d/uv.sh; } || true && \
			{ [ -f /root/.cargo/env ] && source /root/.cargo/env; } || true && \
			/workspace/scripts/build-tool.sh podman $(ARCH) full $(LIBC) && \
			/workspace/scripts/package.sh podman $(ARCH) $(LIBC) full $(VERSION) \
		"

.PHONY: build-podman-minimal
build-podman-minimal: pull-image ## Build podman (minimal variant)
	@echo "Building podman-minimal for $(ARCH) ($(LIBC))..."
	$(PODMAN) run --rm \
		$(MOUNT_SCRIPTS) \
		$(MOUNT_BUILD) \
		-e VERSION=$(VERSION) \
		-e TOOL=podman \
		-e ARCH=$(ARCH) \
		-e VARIANT=minimal \
		-e LIBC=$(LIBC) \
		$(CONTAINER_IMAGE) \
		bash -c " \
			/workspace/scripts/container/setup-build-env.sh && \
			{ [ -f /etc/profile.d/go.sh ] && source /etc/profile.d/go.sh; } || true && \
			{ [ -f /etc/profile.d/llvm.sh ] && source /etc/profile.d/llvm.sh; } || true && \
			{ [ -f /etc/profile.d/cmake.sh ] && source /etc/profile.d/cmake.sh; } || true && \
			{ [ -f /etc/profile.d/uv.sh ] && source /etc/profile.d/uv.sh; } || true && \
			{ [ -f /root/.cargo/env ] && source /root/.cargo/env; } || true && \
			/workspace/scripts/build-tool.sh podman $(ARCH) minimal $(LIBC) && \
			/workspace/scripts/package.sh podman $(ARCH) $(LIBC) minimal $(VERSION) \
		"

.PHONY: build-buildah
build-buildah: pull-image ## Build buildah
	@echo "Building buildah for $(ARCH) ($(LIBC))..."
	$(PODMAN) run --rm \
		$(MOUNT_SCRIPTS) \
		$(MOUNT_BUILD) \
		-e VERSION=$(VERSION) \
		-e TOOL=buildah \
		-e ARCH=$(ARCH) \
		-e LIBC=$(LIBC) \
		$(CONTAINER_IMAGE) \
		bash -c " \
			/workspace/scripts/container/setup-build-env.sh && \
			{ [ -f /etc/profile.d/go.sh ] && source /etc/profile.d/go.sh; } || true && \
			{ [ -f /etc/profile.d/llvm.sh ] && source /etc/profile.d/llvm.sh; } || true && \
			{ [ -f /etc/profile.d/cmake.sh ] && source /etc/profile.d/cmake.sh; } || true && \
			{ [ -f /etc/profile.d/uv.sh ] && source /etc/profile.d/uv.sh; } || true && \
			{ [ -f /root/.cargo/env ] && source /root/.cargo/env; } || true && \
			/workspace/scripts/build-tool.sh buildah $(ARCH) default $(LIBC) && \
			/workspace/scripts/package.sh buildah $(ARCH) $(LIBC) default $(VERSION) \
		"

.PHONY: build-skopeo
build-skopeo: pull-image ## Build skopeo
	@echo "Building skopeo for $(ARCH) ($(LIBC))..."
	$(PODMAN) run --rm \
		$(MOUNT_SCRIPTS) \
		$(MOUNT_BUILD) \
		-e VERSION=$(VERSION) \
		-e TOOL=skopeo \
		-e ARCH=$(ARCH) \
		-e LIBC=$(LIBC) \
		$(CONTAINER_IMAGE) \
		bash -c " \
			/workspace/scripts/container/setup-build-env.sh && \
			{ [ -f /etc/profile.d/go.sh ] && source /etc/profile.d/go.sh; } || true && \
			{ [ -f /etc/profile.d/llvm.sh ] && source /etc/profile.d/llvm.sh; } || true && \
			{ [ -f /etc/profile.d/cmake.sh ] && source /etc/profile.d/cmake.sh; } || true && \
			{ [ -f /etc/profile.d/uv.sh ] && source /etc/profile.d/uv.sh; } || true && \
			{ [ -f /root/.cargo/env ] && source /root/.cargo/env; } || true && \
			/workspace/scripts/build-tool.sh skopeo $(ARCH) default $(LIBC) && \
			/workspace/scripts/package.sh skopeo $(ARCH) $(LIBC) default $(VERSION) \
		"

.PHONY: build-all
build-all: build-podman build-buildah build-skopeo ## Build all tools (podman-full, buildah, skopeo)

.PHONY: test
test: ## Run static linking verification tests
	@echo "Running static linking tests..."
	@if [ -d "$(BUILD_DIR)/podman-$(ARCH)/install/bin" ]; then \
		$(SCRIPTS_DIR)/test-static.sh $(BUILD_DIR)/podman-$(ARCH)/install; \
	else \
		echo "No binaries found. Run 'make build-podman' first."; \
		exit 1; \
	fi

.PHONY: clean
clean: ## Clean build artifacts
	@echo "Cleaning build artifacts..."
	rm -rf $(BUILD_DIR)/*-*/
	rm -f $(BUILD_DIR)/*.tar.zst
	rm -f $(BUILD_DIR)/checksums.txt
	rm -f $(BUILD_DIR)/*.sig

.PHONY: clean-all
clean-all: clean ## Clean all build artifacts including mimalloc
	@echo "Cleaning all build artifacts including dependencies..."
	rm -rf $(BUILD_DIR)/mimalloc/build/

.PHONY: shell
shell: pull-image ## Start an interactive shell in the build container
	$(PODMAN) run --rm -it \
		$(MOUNT_SCRIPTS) \
		$(MOUNT_BUILD) \
		$(CONTAINER_IMAGE) \
		bash
