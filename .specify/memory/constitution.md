<!--
Sync Impact Report
==================
Version change: 1.3.0 → 1.4.0
Bump rationale: Add glibc libc variant (static + glibc hybrid linking) - MINOR

Modified sections:
  - Principle I (Truly Static Binaries): Renamed to "Maximally Static Binaries", added glibc variant
  - Build Artifacts: Added libc variant dimension (static/glibc) to artifact naming
  - Build Environment: Added glibc build support with unified Clang toolchain

Rationale:
  - glibc variant provides system integration for modern Linux (glibc 2.34+)
  - All dependencies except glibc remain statically linked (libstdc++, mimalloc, pthread)
  - musl-static remains default and recommended for maximum portability
  - Both variants use unified Clang toolchain

Templates requiring updates:
  - .specify/templates/plan-template.md: ✅ No changes needed (generic template)
  - .specify/templates/spec-template.md: ✅ No changes needed (generic template)
  - .specify/templates/tasks-template.md: ✅ No changes needed (generic template)

Previous changes:
==================
Version 1.2.1 → 1.3.0 (MINOR)
- Add third package variant (standalone/default/full)

Version 1.2.0 → 1.2.1 (PATCH)
- Adjusted daily check schedule from UTC 00:00 to UTC 02:00

Version 1.1.0 → 1.2.0 (MINOR)
- Migration from Zig to Clang due to compatibility issues
- Updated Principle III (Reproducible Builds): "documented minimum versions"
- Updated Build Environment: Clang with musl target
- Updated Minimum Requirements: Clang, Go 1.21+, protobuf-compiler
-->

# Rootless Static Toolkits Constitution

## Core Principles

### I. Maximally Static Binaries

All produced binaries MUST minimize runtime library dependencies through static linking.

Two libc variants are supported:
- **static** (default, recommended): Fully static with musl libc, zero runtime dependencies
- **glibc**: Hybrid static with only glibc dynamically linked (requires glibc 2.34+)

Static variant requirements:
- Build using musl libc to achieve true static linking
- Binaries MUST run on any Linux distribution without additional libraries
- Verify with `ldd` showing "not a dynamic executable"

Glibc variant requirements:
- Only glibc (libc.so.6, ld-linux) may be dynamically linked
- All other dependencies MUST be statically linked: libstdc++, mimalloc, pthread, compiler-rt
- Verify with `ldd` showing only glibc dependencies
- Requires glibc 2.34+ on target system (Ubuntu 22.04+, Debian 12+, RHEL 9+)

Both variants:
- Use unified Clang toolchain
- Statically link mimalloc via --whole-archive
- Produce binaries of similar size (~43MB)

**Rationale**: Static linking ensures portability and reduces dependency conflicts. The glibc variant provides an alternative for users who need system integration (NSS, LDAP) while maintaining static linking for all other dependencies.

### II. Independent Tool Releases

Each tool (podman, buildah, skopeo) MUST be tracked and released independently.

- Version tracking follows upstream releases (e.g., `podman-v5.3.1`, `buildah-v1.38.0`)
- A new upstream version of one tool does NOT trigger rebuilds of other tools
- Each tool has its own GitHub Release with tool-specific assets
- Release tags follow pattern: `{tool}-v{version}` (e.g., `podman-v5.3.1`)

**Rationale**: Independent releases reduce unnecessary builds and allow users to update tools selectively.

### III. Reproducible Builds

Build processes MUST be deterministic and reproducible.

- Use well-defined build dependencies with documented minimum versions
- Document exact build steps in scripts and Makefile
- Maintain Alpine-based Dockerfile as reproducibility fallback
- Same inputs MUST produce functionally equivalent outputs
- Build environment can be recreated from documentation

**Rationale**: Reproducibility enables verification, debugging, and trust in the build artifacts.

### IV. Minimal Dependencies

Include only components strictly necessary for functionality.

All tools provide three package variants:
- **standalone**: Binary only (for users with existing compatible system runtimes)
- **default**: Binary + minimum runtime components (crun, conmon) + configs (recommended for most users)
- **full**: Binary + all companion tools (complete rootless stack)

Specific variant contents:
- Podman default: podman + crun + conmon + configs (~49MB)
- Podman full: default + netavark + aardvark-dns + pasta + fuse-overlayfs + catatonit (~74MB)
- Buildah default: buildah + crun + conmon + configs (~55MB)
- Buildah full: default + fuse-overlayfs (~56MB)
- Skopeo: all variants identical (~30MB, no runtime components needed)

Principles:
- No optional features or plugins unless explicitly justified
- YAGNI: do not add components "just in case"
- Default variant recommended for most users (includes minimum required runtime)

**Rationale**: Minimal dependencies reduce attack surface, binary size, and maintenance burden. Three variants provide flexibility while keeping defaults lean.

### V. Automated Release Pipeline

Version detection and releases MUST be fully automated.

- Daily scheduled check (UTC 02:00) for new upstream versions via GitHub API
- Manual trigger support via workflow_dispatch for on-demand builds
- Automatic GitHub Release creation with:
  - Tarballs for linux/amd64 and linux/arm64
  - SHA256 checksums
  - Sigstore/cosign signatures (keyless signing)
- No manual intervention required for standard releases

**Rationale**: Automation ensures timely releases, eliminates human error, and reduces maintenance overhead.

## Build Requirements

### Target Platforms

| Architecture | OS | Status |
|--------------|------|--------|
| amd64 | Linux | Required |
| arm64 | Linux | Required |

### Build Artifacts

For each tool release, artifacts are organized by two dimensions:
- **Libc variant**: `static` (musl, default) or `glibc`
- **Package variant**: `standalone`, `default`, or `full`

| Artifact | Description |
|----------|-------------|
| `{tool}-{version}-linux-{arch}-static.tar.zst` | Static/musl default variant (recommended) |
| `{tool}-{version}-linux-{arch}-glibc.tar.zst` | Glibc default variant |
| `{tool}-{version}-linux-{arch}-static-standalone.tar.zst` | Static standalone (binary only) |
| `{tool}-{version}-linux-{arch}-static-full.tar.zst` | Static full (complete rootless stack) |
| `{tool}-{version}-linux-{arch}-glibc-standalone.tar.zst` | Glibc standalone (binary only) |
| `{tool}-{version}-linux-{arch}-glibc-full.tar.zst` | Glibc full (complete rootless stack) |
| `checksums.txt` | SHA256 checksums for all tarballs |
| `*.bundle` | Cosign signature bundles (keyless OIDC) |

**Naming Convention**:
- Format: `{tool}-{version}-linux-{arch}-{libc}[-{package}].tar.zst`
- Default package variant omits package suffix for simplicity
- Static libc is recommended for maximum portability

**Per-tool Differences**:
- Podman full: Adds netavark, aardvark-dns, pasta, fuse-overlayfs, catatonit
- Buildah full: Adds fuse-overlayfs only
- Skopeo: All package variants identical (no runtime components needed)

### Build Environment

- **Container Base**: Ubuntu latest (provides both musl-tools and glibc)
- **Compiler**: Clang (unified toolchain for both libc variants)
  - Static variant: `clang --target={arch}-linux-musl`
  - Glibc variant: `clang` (default target)
- **Allocator**: mimalloc (statically linked via --whole-archive for both variants)
- **Build Tools**: `uv` for Python tools (meson, ninja), direct download for cmake
- **Cross-compilation**: Clang cross-compile on amd64 runner; native arm64 runner as fallback
- **Minimum Requirements**: Clang, Go 1.21+, Rust stable, protobuf-compiler, musl-tools

## Release Pipeline

### Version Detection

```
Schedule: Daily at UTC 02:00
Method: curl + GitHub API (no authentication required for public repos)
  - Endpoint: https://api.github.com/repos/{org}/{repo}/releases
  - Fallback: https://api.github.com/repos/{org}/{repo}/tags
  - Filter: Semver regex ^v?[0-9]+\.[0-9]+(\.[0-9]+)?$ (excludes pre-releases)
Upstream repos:
  - github.com/containers/podman
  - github.com/containers/buildah
  - github.com/containers/skopeo
```

### Trigger Conditions

- **Automatic**: New release tag detected in upstream repo
- **Manual**: workflow_dispatch with tool name and version parameters

### Release Process

1. Detect new version (scheduled or manual trigger)
2. Build binaries for all target architectures
3. Generate checksums
4. Sign with sigstore/cosign
5. Create GitHub Release with tag `{tool}-v{version}`
6. Upload all artifacts

## Governance

### Amendment Process

1. Propose changes via pull request modifying this constitution
2. Document rationale for changes
3. Update dependent templates if principles change
4. Increment version according to semver:
   - MAJOR: Principle removal or fundamental change
   - MINOR: New principle or significant expansion
   - PATCH: Clarification or typo fix

### Compliance

- All PRs MUST verify alignment with these principles
- Build failures due to principle violations MUST be fixed, not worked around
- Exceptions require documented justification in the PR

### Reference Documents

- Upstream reference: https://github.com/mgoltzsche/podman-static
- Container tools: https://github.com/containers

**Version**: 1.4.0 | **Ratified**: 2025-12-12 | **Last Amended**: 2025-12-16
