# Rootless Static Toolkits

[![Build Podman](https://github.com/pigfoot/static-rootless-container-tools/actions/workflows/build-podman.yml/badge.svg)](https://github.com/pigfoot/static-rootless-container-tools/actions/workflows/build-podman.yml)
[![Build Buildah](https://github.com/pigfoot/static-rootless-container-tools/actions/workflows/build-buildah.yml/badge.svg)](https://github.com/pigfoot/static-rootless-container-tools/actions/workflows/build-buildah.yml)
[![Build Skopeo](https://github.com/pigfoot/static-rootless-container-tools/actions/workflows/build-skopeo.yml/badge.svg)](https://github.com/pigfoot/static-rootless-container-tools/actions/workflows/build-skopeo.yml)
[![Check New Releases](https://github.com/pigfoot/static-rootless-container-tools/actions/workflows/check-releases.yml/badge.svg)](https://github.com/pigfoot/static-rootless-container-tools/actions/workflows/check-releases.yml)

Build static and glibc binaries for **podman**, **buildah**, and **skopeo** targeting `linux/amd64` and `linux/arm64`.

## Features

- **Two Build Variants**: Static (musl, fully static) and glibc (hybrid static, only glibc dynamic)
- **Unified Clang Toolchain**: Both variants built with Clang + mimalloc in containerized Ubuntu:latest
- **Cross-Architecture**: Supports amd64 and arm64
- **Independent Releases**: Each tool released separately when upstream updates
- **Automated Pipeline**: Daily upstream version checks (2 AM UTC) with GitHub Actions
- **Verified Downloads**: SHA256 checksums + Sigstore/cosign keyless OIDC signatures

## Quick Start

### Download Latest Version (Auto-detect)

```bash
# Set repository and architecture
REPO="pigfoot/static-rootless-container-tools"
ARCH=$([[ $(uname -m) == "aarch64" ]] && echo "arm64" || echo "amd64")

# Download latest podman (default variant, static libc - recommended)
TOOL="podman"
TAG=$(curl -s "https://api.github.com/repos/${REPO}/releases" | \
  sed -n 's/.*"tag_name": "\('"${TOOL}"'-v[^"]*\)".*/\1/p' | head -1)
VERSION=${TAG#${TOOL}-}  # Extract version (e.g., v5.7.1)
curl -fsSL "https://github.com/${REPO}/releases/download/${TAG}/${TOOL}-${VERSION}-linux-${ARCH}-static.tar.zst" | \
  zstd -d | tar xvf -

# Or download podman-full for complete rootless stack
curl -fsSL "https://github.com/${REPO}/releases/download/${TAG}/${TOOL}-${VERSION}-linux-${ARCH}-static-full.tar.zst" | \
  zstd -d | tar xvf -

# Download latest buildah (default variant, static libc - recommended)
TOOL="buildah"
TAG=$(curl -s "https://api.github.com/repos/${REPO}/releases" | \
  sed -n 's/.*"tag_name": "\('"${TOOL}"'-v[^"]*\)".*/\1/p' | head -1)
VERSION=${TAG#${TOOL}-}
curl -fsSL "https://github.com/${REPO}/releases/download/${TAG}/${TOOL}-${VERSION}-linux-${ARCH}-static.tar.zst" | \
  zstd -d | tar xvf -

# Download latest skopeo (default variant, static libc - recommended)
TOOL="skopeo"
TAG=$(curl -s "https://api.github.com/repos/${REPO}/releases" | \
  sed -n 's/.*"tag_name": "\('"${TOOL}"'-v[^"]*\)".*/\1/p' | head -1)
VERSION=${TAG#${TOOL}-}
curl -fsSL "https://github.com/${REPO}/releases/download/${TAG}/${TOOL}-${VERSION}-linux-${ARCH}-static.tar.zst" | \
  zstd -d | tar xvf -
```

### Download Specific Version

Check [Releases](https://github.com/pigfoot/static-rootless-container-tools/releases) for all available versions.

```bash
# Example: Download podman default variant v5.7.1 for linux/amd64 (static, recommended)
curl -fsSL -O https://github.com/pigfoot/static-rootless-container-tools/releases/download/podman-v5.7.1/podman-v5.7.1-linux-amd64-static.tar.zst

# Extract
zstd -d podman-v5.7.1-linux-amd64-static.tar.zst && tar -xf podman-v5.7.1-linux-amd64-static.tar
cd podman-v5.7.1

# Install system-wide
sudo cp -r usr/* /usr/
sudo cp -r etc/* /etc/

# Or use from current directory
export PATH=$PWD/usr/local/bin:$PATH
podman --version
```

### Verify Authenticity

All releases include SHA256 checksums and cosign signatures (keyless OIDC).

```bash
# Download checksums file
curl -fsSL -O https://github.com/pigfoot/static-rootless-container-tools/releases/download/podman-v5.7.1/checksums.txt

# Verify SHA256 checksum
sha256sum -c checksums.txt --ignore-missing

# Verify cosign signature (requires cosign CLI)
curl -fsSL -O https://github.com/pigfoot/static-rootless-container-tools/releases/download/podman-v5.7.1/podman-v5.7.1-linux-amd64-static.tar.zst.bundle
cosign verify-blob \
  --bundle=podman-v5.7.1-linux-amd64-static.tar.zst.bundle \
  --certificate-identity-regexp='https://github.com/.*' \
  --certificate-oidc-issuer='https://token.actions.githubusercontent.com' \
  podman-v5.7.1-linux-amd64-static.tar.zst
```

## Build Variants

All binaries are available in two libc linking strategies:

| Variant | Libc | Linking | Portability | Binary Size | Use Case |
|---------|------|---------|-------------|-------------|----------|
| **static** (default) | musl | Fully static | Maximum - runs on any Linux | ~43MB | **RECOMMENDED** - CI/CD, containers, maximum compatibility |
| **glibc** | glibc | Only glibc dynamic, rest static | Modern Linux (glibc 2.34+) | ~43MB | System integration, enterprise (LDAP/NIS) |

### Static vs Glibc: What's Linked?

| Component | Static (musl) | Glibc (dynamic) |
|-----------|---------------|-----------------|
| C library (libc) | musl (static) | glibc (dynamic) |
| C++ stdlib (libstdc++) | Static | Static |
| pthread | Static | Static |
| Memory allocator (mimalloc) | Static (--whole-archive) | Static (--whole-archive) |
| Compiler runtime | N/A | Static (libgcc/compiler-rt) |
| Go runtime | Static | Static |

**Static variant**: Zero runtime dependencies, works everywhere
**Glibc variant**: Only links glibc dynamically (libc.so.6, ld-linux), all other dependencies static

### Choosing a Build Variant

Use this decision tree to select the right variant:

```
┌─ Maximum portability needed?
│  └─ YES → static (musl)
│
├─ Deploying to containers/CI/CD?
│  └─ YES → static (musl)
│
├─ Enterprise environment with LDAP/NIS?
│  └─ YES → glibc
│
├─ Target only modern distros (Ubuntu 22.04+, Debian 12+, RHEL 9+)?
│  └─ YES → Either variant works
│
└─ Default recommendation
   └─ static (maximum compatibility)
```

### OS Compatibility Matrix

| Distribution | glibc Version | Static Variant | Glibc Variant |
|--------------|---------------|----------------|---------------|
| Ubuntu 20.04 | 2.31 | ✅ Works | ❌ Too old |
| Ubuntu 22.04+ | 2.35+ | ✅ Works | ✅ Works |
| Ubuntu 24.04 | 2.39 | ✅ Works | ✅ Works |
| Debian 11 | 2.31 | ✅ Works | ❌ Too old |
| Debian 12+ | 2.36+ | ✅ Works | ✅ Works |
| RHEL 8 | 2.28 | ✅ Works | ❌ Too old |
| RHEL 9+ | 2.34+ | ✅ Works | ✅ Works |
| Alpine Linux | musl | ✅ Works | ❌ No glibc |
| Any Linux | Any | ✅ Works | Requires glibc 2.34+ |

**Glibc variant requirement**: Target system must have glibc 2.34 or newer

### Download Examples

```bash
REPO="pigfoot/static-rootless-container-tools"
ARCH=$([[ $(uname -m) == "aarch64" ]] && echo "arm64" || echo "amd64")

# Static variant (default - recommended)
curl -fsSL "https://github.com/${REPO}/releases/download/podman-v5.7.1/podman-v5.7.1-linux-${ARCH}-static.tar.zst" | \
  zstd -d | tar xvf -

# Glibc variant (for modern Linux systems)
curl -fsSL "https://github.com/${REPO}/releases/download/podman-v5.7.1/podman-v5.7.1-linux-${ARCH}-glibc.tar.zst" | \
  zstd -d | tar xvf -
```

## Package Variants

All tools provide three package variants to suit different use cases:

### Podman Variants

| Variant | Size | Components | Use Case |
|---------|------|------------|----------|
| **podman-{ver}-linux-{arch}-{libc}.tar.zst** ⭐ | ~49MB | podman + crun + conmon + configs | **RECOMMENDED** - Core container functionality, works everywhere |
| **podman-{ver}-linux-{arch}-{libc}-standalone.tar.zst** ⚠️ | ~44MB | podman only | NOT RECOMMENDED - requires system runc ≥1.1.11 + latest conmon |
| **podman-{ver}-linux-{arch}-{libc}-full.tar.zst** | ~74MB | Default + all networking tools | Complete rootless stack with custom networks |

**Default variant includes**: podman (44MB), crun (2.6MB), conmon (2.3MB), configs

**Full variant adds**: netavark (14MB), aardvark-dns (3.5MB), pasta + pasta.avx2 (3MB), fuse-overlayfs (1.4MB), catatonit (953KB)

### Buildah Variants

| Variant | Size | Components | Use Case |
|---------|------|------------|----------|
| **buildah-{ver}-linux-{arch}-{libc}.tar.zst** ⭐ | ~55MB | buildah + crun + conmon + configs | **RECOMMENDED** - Build images with `buildah run` support |
| **buildah-{ver}-linux-{arch}-{libc}-standalone.tar.zst** ⚠️ | ~50MB | buildah only | NOT RECOMMENDED - requires system runc/crun + conmon |
| **buildah-{ver}-linux-{arch}-{libc}-full.tar.zst** | ~56MB | Default + fuse-overlayfs | Rootless image building with overlay mounts |

**Default variant includes**: buildah (~50MB), crun (2.6MB), conmon (2.3MB), configs

**Full variant adds**: fuse-overlayfs (1.4MB) for rootless overlay mounts

### Skopeo Variants

| Variant | Size | Components | Use Case |
|---------|------|------------|----------|
| **skopeo-{ver}-linux-{arch}-{libc}.tar.zst** ⭐ | ~30MB | skopeo + configs | **RECOMMENDED** - Image operations with registry configs |
| **skopeo-{ver}-linux-{arch}-{libc}-standalone.tar.zst** | ~30MB | skopeo only | Binary only |
| **skopeo-{ver}-linux-{arch}-{libc}-full.tar.zst** | ~30MB | Same as default | Alias (skopeo needs no runtime components) |

**Note**: All skopeo variants are essentially the same since skopeo doesn't run containers.

### ⚠️ Compatibility Warnings

- **standalone variants** require compatible system packages:
  - crun ≥ 1.25.1 (Ubuntu 24.04 has 1.14.1 - **too old**)
  - Latest conmon version
  - pasta (for rootless networking)
- **default and full variants** include all required runtimes - work on **any** Linux distribution

### Comparison with Other Static Podman Projects

| Feature | pigfoot | mgoltzsche/podman-static |
|---------|---------|--------------------------|
| Podman version | 5.7.1 | 5.7.1 |
| crun version | 1.25.1 | bundled |
| pasta version | 5.7.1 | 2025_12_10 |
| SSL/TLS (bun install) | ✅ Works | ❌ Certificate errors |
| Libc variants | static + glibc | static only |

**Note:** mgoltzsche's pasta build has known SSL issues affecting some applications. See [Networking Research](docs/podman-rootless-networking-research.md) for detailed test results.

### Variant Selection by Scenario

| Scenario | Recommended Variant | Reason |
|----------|---------------------|--------|
| GitHub Actions (Ubuntu 24.04) | **default** | Ubuntu has pasta, only needs bundled crun |
| Clean system / Alpine / Minimal | **full** | No external dependencies |
| System has crun ≥ 1.25.1 | standalone | Smallest size |

## Building from Source

### Prerequisites

- podman or docker (for containerized builds)
- cosign (optional, for signing)
- gh CLI (optional, for automated releases)

All builds run inside Ubuntu:latest containers with:
- Clang + musl-dev + musl-tools
- Go 1.21+
- Rust (for netavark/aardvark-dns)
- protobuf-compiler

### Local Build

```bash
# Build podman (default variant, static libc, amd64) - runs inside ubuntu:latest container
./scripts/container/run-build.sh podman amd64 default static

# Build with different options
./scripts/container/run-build.sh podman arm64 full static
./scripts/container/run-build.sh buildah amd64 default glibc
./scripts/container/run-build.sh skopeo amd64 standalone static

# Or use Makefile shortcuts
make build-podman                    # default variant, static, amd64
make build-podman ARCH=arm64         # cross-compile for arm64
make build-podman VARIANT=full       # full variant with all components
make build-podman LIBC=glibc         # glibc variant
```

### Trigger GitHub Actions Build

```bash
# Trigger workflow with specific options
gh workflow run build-podman.yml \
  -f version=v5.3.1 \
  -f architecture=amd64 \
  -f variant=default    # or standalone, or full

# Build all variants for both architectures
gh workflow run build-podman.yml \
  -f version=v5.3.1 \
  -f architecture=both \
  -f variant=all
```

### Local Signing

```bash
# Sign all tarballs in release directory
./scripts/sign-release.sh ./release/
```

## Architecture

### Build Strategy

1. **Containerized**: Ubuntu:latest with Clang + musl-dev for reproducible builds
2. **Cross-Compilation**: Clang with `--target=<arch>-linux-musl` for amd64/arm64
3. **Allocator**: mimalloc (statically linked, 7-10x faster than musl default)
4. **Dependencies**: All dependencies built from source (libseccomp, libfuse, etc.)

### Release Pipeline

```
Daily Cron (check-releases.yml)
  ├─> Check upstream podman release
  ├─> Check upstream buildah release
  └─> Check upstream skopeo release
       └─> Trigger build-<tool>.yml if new version found
            ├─> Build for amd64
            ├─> Build for arm64
            ├─> Generate checksums
            ├─> Sign with cosign
            └─> Create GitHub Release
```

### Directory Structure

```
.github/workflows/     # CI/CD workflows
scripts/               # Build and utility scripts
build/                 # Build dependencies
  ├── mimalloc/        # Cloned mimalloc source
  ├── patches/         # Patches for dependencies
  └── etc/             # Default config files
```

## Contributing

See [CONTRIBUTING.md](./CONTRIBUTING.md) for development workflow.

## License

This build infrastructure is provided as-is. The built tools (podman, buildah, skopeo) retain their original licenses:

- podman: Apache-2.0
- buildah: Apache-2.0
- skopeo: Apache-2.0

## References

- Inspired by [mgoltzsche/podman-static](https://github.com/mgoltzsche/podman-static)
- [Project Constitution](.specify/memory/constitution.md)
- [Feature Specification](specs/001-static-build/spec.md)
