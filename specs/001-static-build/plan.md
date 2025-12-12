# Implementation Plan: Static Container Tools Build System

**Branch**: `001-static-build` | **Date**: 2025-12-12 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/001-static-build/spec.md`

## Summary

Build a fully automated release pipeline for static podman, buildah, and skopeo binaries targeting linux/amd64 and linux/arm64. Uses Zig as cross-compiler with musl libc and mimalloc for optimal static binaries. Each tool is tracked and released independently based on upstream versions, with daily automated checks and manual trigger support.

## Technical Context

**Language/Version**: Bash scripts, YAML (GitHub Actions), Dockerfile (optional fallback)
**Compiler**: Zig 0.11+ (as C/C++ cross-compiler for CGO dependencies)
**Libc**: musl (for truly static binaries)
**Allocator**: mimalloc (static linked, replaces musl's slow allocator)
**Primary Dependencies**: Go toolchain, Zig, cosign, gh CLI
**Storage**: N/A (version tracking via GitHub Releases)
**Testing**: Shell-based smoke tests (ldd verification, version checks, binary execution)
**Target Platform**: GitHub Actions runners (ubuntu-latest for cross-compile)
**Project Type**: Build infrastructure / CI-CD pipeline
**Performance Goals**: Build-to-release < 30 minutes per tool per architecture
**Constraints**: GitHub Actions runner limits, upstream release frequency
**Scale/Scope**: 3 tools × 2 architectures × 2 variants (podman) = ~10 artifacts per release cycle

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Evidence |
|-----------|--------|----------|
| I. Truly Static Binaries | ✅ PASS | Zig + musl target produces static binaries; verified with `ldd` |
| II. Independent Tool Releases | ✅ PASS | Separate workflows per tool; version tracking per tool |
| III. Reproducible Builds | ✅ PASS | Pinned Zig version; containerized fallback available |
| IV. Minimal Dependencies | ✅ PASS | Only required runtime components in podman-full; minimal has binary only |
| V. Automated Release Pipeline | ✅ PASS | Daily cron + workflow_dispatch; cosign signing; auto GitHub Release |

## Project Structure

### Documentation (this feature)

```text
specs/001-static-build/
├── plan.md              # This file
├── spec.md              # Feature specification
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── checklists/          # Validation checklists
└── tasks.md             # Phase 2 output (/speckit.tasks)
```

### Source Code (repository root)

```text
.github/
└── workflows/
    ├── check-releases.yml       # Daily cron: check upstream versions
    ├── build-podman.yml         # Build + release podman
    ├── build-buildah.yml        # Build + release buildah
    └── build-skopeo.yml         # Build + release skopeo

scripts/
├── check-version.sh             # Compare upstream vs local releases
├── build-tool.sh                # Common build logic (Zig + Go + mimalloc)
├── package.sh                   # Create tarball with bin/lib/etc structure
└── sign-release.sh              # Cosign signing

build/
├── mimalloc/                    # mimalloc source for static compilation
└── patches/                     # Any patches needed for dependencies

Dockerfile.podman               # Fallback: Alpine-based build (if Zig fails)
Dockerfile.buildah              # Fallback: Alpine-based build
Dockerfile.skopeo               # Fallback: Alpine-based build

Makefile                        # Local build/test commands
```

**Structure Decision**: Build infrastructure project with GitHub Actions workflows as primary, scripts for build logic, and Dockerfiles as fallback.

## Build Artifacts

### Release Naming

- Tag format: `{tool}-v{version}` (e.g., `podman-v5.3.1`)
- Release title: `{Tool} {version}` (e.g., `Podman 5.3.1`)

### Artifact Structure

For podman:
```
podman-full-linux-amd64.tar.zst
podman-full-linux-arm64.tar.zst
podman-minimal-linux-amd64.tar.zst
podman-minimal-linux-arm64.tar.zst
checksums.txt
cosign signatures (attached to release)
```

For buildah/skopeo:
```
buildah-linux-amd64.tar.zst
buildah-linux-arm64.tar.zst
checksums.txt
cosign signatures
```

### Tarball Contents (podman-full example)

```
podman-v5.3.1/
├── bin/
│   ├── podman
│   ├── crun
│   ├── conmon
│   ├── fuse-overlayfs
│   ├── netavark
│   ├── aardvark-dns
│   ├── pasta
│   └── catatonit
├── lib/
│   └── podman/
│       └── (helper libraries if any)
└── etc/
    └── containers/
        ├── policy.json
        └── registries.conf
```

## Complexity Tracking

| Experimental Choice | Why Needed | Fallback Plan |
|---------------------|------------|---------------|
| Zig cross-compiler | Simpler cross-compile, no QEMU/ARM runners | Dockerfile.* with Alpine/musl |
| mimalloc static link | musl allocator is slow | Accept musl allocator for CLI tools |
| Cross-compile arm64 | Avoid ARM runner cost/complexity | Use ubuntu-24.04-arm native runner |
