# Rootless Static Toolkits

Build truly static binaries for **podman**, **buildah**, and **skopeo** targeting `linux/amd64` and `linux/arm64`.

## Features

- **Truly Static Binaries**: Built with musl libc + mimalloc, runs on any Linux distribution
- **Cross-Architecture**: Supports amd64 and arm64 via Zig cross-compilation
- **Independent Releases**: Each tool released separately when upstream updates
- **Automated Pipeline**: Daily upstream version checks with GitHub Actions
- **Verified Downloads**: SHA256 checksums + Sigstore/cosign signatures

## Quick Start

### Download Pre-built Binaries

```bash
# Download latest podman-full for linux/amd64
wget https://github.com/YOUR_USERNAME/rootless-static-toolkits/releases/download/podman-vX.Y.Z/podman-full-linux-amd64.tar.zst

# Extract
tar -xf podman-full-linux-amd64.tar.zst

# Run
cd podman-vX.Y.Z/bin
./podman --version
```

### Verify Authenticity

```bash
# Verify SHA256 checksum
wget https://github.com/YOUR_USERNAME/rootless-static-toolkits/releases/download/podman-vX.Y.Z/checksums.txt
sha256sum -c checksums.txt --ignore-missing

# Verify cosign signature (requires cosign CLI)
wget https://github.com/YOUR_USERNAME/rootless-static-toolkits/releases/download/podman-vX.Y.Z/podman-full-linux-amd64.tar.zst.sig
cosign verify-blob \
  --signature podman-full-linux-amd64.tar.zst.sig \
  --certificate-identity-regexp 'https://github.com/YOUR_USERNAME/rootless-static-toolkits' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  podman-full-linux-amd64.tar.zst
```

## Available Tools

### podman

- **podman-full**: Includes all runtime components (crun, conmon, fuse-overlayfs, netavark, aardvark-dns, pasta, catatonit)
- **podman-minimal**: Binary only

### buildah

Single binary for building OCI images.

### skopeo

Single binary for image operations.

## Building from Source

### Prerequisites

- Zig 0.11+
- Go 1.21+
- cosign
- gh CLI (authenticated)

```bash
# Install dependencies
make install-deps

# Build specific tool
make build-podman

# Run tests
make test
```

### Manual Build

```bash
# Build podman for current architecture
./scripts/build-tool.sh podman

# Package tarball
./scripts/package.sh podman v5.3.1 full

# Sign with cosign
./scripts/sign-release.sh podman-full-linux-amd64.tar.zst
```

## Architecture

### Build Strategy

1. **Primary**: Zig cross-compiler with musl target
2. **Fallback**: Alpine Linux container with musl-based GCC
3. **Allocator**: mimalloc (statically linked, 7-10x faster than musl default)

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
