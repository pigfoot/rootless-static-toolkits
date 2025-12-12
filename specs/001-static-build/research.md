# Research: Static Container Tools Build System

**Date**: 2025-12-12
**Branch**: `001-static-build`

## Research Summary

This document consolidates research findings from the brainstorming session and validates key technical decisions.

---

## 1. Static Linking Strategy

### Decision: Zig + musl + mimalloc

### Rationale

| Approach | Pros | Cons |
|----------|------|------|
| Alpine + musl-gcc | Proven (podman-static uses it), well-documented | Requires Docker build, complex cross-compile |
| Zig cross-compiler | Single binary, built-in musl support, easy cross-compile | Experimental for Go CGO, may need patches |
| glibc static | Better compatibility | Not truly static (NSS, DNS issues) |

**Chosen**: Zig with musl target because:
1. Simplifies cross-compilation (no QEMU, no ARM runners needed)
2. Built-in musl support (`-target aarch64-linux-musl`)
3. Single binary installation in CI
4. Fallback to Alpine/Docker if issues arise

### Alternatives Considered

- **Nix**: Excellent reproducibility but steep learning curve
- **xx (Docker cross-compile)**: Still requires Docker build context
- **Native ARM runners**: Works but adds complexity and cost

---

## 2. Allocator Choice

### Decision: mimalloc (statically linked)

### Rationale

musl's built-in allocator is 7-10x slower than glibc malloc in multi-threaded workloads. While podman/buildah/skopeo are CLI tools (short-lived), using mimalloc:
1. Eliminates potential performance issues
2. Provides consistent memory behavior
3. Minimal overhead to integrate

### Integration Approach

```bash
# Compile mimalloc as static library with Zig
git clone https://github.com/microsoft/mimalloc
cd mimalloc
zig cc -target x86_64-linux-musl -c -O3 src/static.c -I include -o mimalloc.o
zig ar rcs libmimalloc.a mimalloc.o

# Link with Go CGO builds
export CGO_LDFLAGS="-L/path/to/mimalloc -lmimalloc"
```

### Alternatives Considered

- **jemalloc**: Good but larger, more complex build
- **Accept musl allocator**: Simpler but potential performance issues
- **tcmalloc**: Google's allocator, less portable

---

## 3. Cross-Compilation Strategy

### Decision: Cross-compile arm64 on amd64 runner

### Rationale

Zig's cross-compilation capabilities allow building arm64 binaries on standard amd64 runners:

```bash
# Build for arm64 from amd64
export CC="zig cc -target aarch64-linux-musl"
export CXX="zig c++ -target aarch64-linux-musl"
CGO_ENABLED=1 GOARCH=arm64 go build ...
```

Benefits:
1. No need for QEMU (slow emulation)
2. No need for ARM runners (cost, availability)
3. Faster builds (native speed, no emulation overhead)

### Fallback

If Zig cross-compile fails for certain dependencies:
1. First try: Patch the problematic dependency
2. Second try: Use `ubuntu-24.04-arm` native runner
3. Last resort: Docker build with QEMU

### Known Risks

Some build systems may:
- Run compiled binaries during build (impossible with cross-compile)
- Use architecture-specific assembly
- Have autoconf scripts that detect host incorrectly

---

## 4. Archive Format

### Decision: .tar.zst (Zstandard compression)

### Rationale

| Format | Compression Ratio | Decompression Speed | Compatibility |
|--------|-------------------|---------------------|---------------|
| .tar.gz | Baseline | Baseline | Universal |
| .tar.zst | ~20-30% better | 3-5x faster | Modern tar (2019+) |
| .tar.xz | Best | Slowest | Universal |

**Chosen**: .tar.zst because:
1. Better compression than gzip
2. Much faster decompression
3. Modern tar versions auto-detect (`tar -xf file.tar.zst`)
4. Users can extract directly to `/` to install

### Compatibility Note

Users on older systems without zstd support can:
```bash
zstd -d file.tar.zst && tar -xf file.tar
```

---

## 5. Version Detection Mechanism

### Decision: Check GitHub Releases via API

### Rationale

```bash
# Check if release exists
gh release view "podman-v5.3.1" --repo owner/repo 2>/dev/null
if [ $? -ne 0 ]; then
  # Release doesn't exist, trigger build
fi
```

Benefits:
1. Release = actual published state
2. Failed builds don't create releases, so they'll retry
3. No separate version tracking file to maintain
4. Works with `gh` CLI in GitHub Actions

### Upstream Version Check

```bash
# Get latest stable release from upstream
LATEST=$(gh release list --repo containers/podman --limit 1 --exclude-drafts --exclude-pre-releases | head -1 | cut -f1)
```

---

## 6. Signing Strategy

### Decision: Sigstore/cosign keyless signing

### Rationale

| Method | Key Management | Verification | Complexity |
|--------|----------------|--------------|------------|
| GPG | Must manage keys | Manual download of public key | High |
| Sigstore/cosign | Keyless (OIDC) | Automatic via transparency log | Low |
| None | N/A | N/A | None |

**Chosen**: Sigstore/cosign because:
1. No key management needed
2. GitHub Actions has built-in OIDC support
3. Verification is straightforward: `cosign verify-blob`
4. Transparency log provides audit trail

### Implementation

```yaml
# In GitHub Actions
- uses: sigstore/cosign-installer@v3

- name: Sign artifacts
  run: |
    cosign sign-blob --yes \
      --oidc-issuer https://token.actions.githubusercontent.com \
      --output-signature $FILE.sig \
      $FILE
```

---

## 7. Podman Runtime Components

### Decision: Bundle all required components in podman-full

### Components List

| Component | Purpose | Required for Rootless |
|-----------|---------|----------------------|
| podman | Main binary | Yes |
| crun | OCI runtime | Yes |
| conmon | Container monitor | Yes |
| fuse-overlayfs | Rootless overlay FS | Yes |
| netavark | CNI networking | Yes |
| aardvark-dns | DNS for containers | Yes |
| pasta | Rootless networking | Yes (or slirp4netns) |
| catatonit | Minimal init | Recommended |

### Source Repositories

- podman: github.com/containers/podman
- buildah: github.com/containers/buildah
- skopeo: github.com/containers/skopeo
- crun: github.com/containers/crun
- conmon: github.com/containers/conmon
- fuse-overlayfs: github.com/containers/fuse-overlayfs
- netavark: github.com/containers/netavark
- aardvark-dns: github.com/containers/aardvark-dns
- pasta: https://passt.top/passt (or github mirror)
- catatonit: github.com/openSUSE/catatonit

### Version Strategy

**Decision: Use latest stable release for each component**

For each build:
1. Query upstream repository for latest non-prerelease version
2. Build all components with their respective latest versions
3. Bundle together in podman-full tarball

**Rationale:**
- Simpler implementation (no version mapping maintenance)
- Runtime components maintain backward compatibility
- Users get security fixes and improvements
- If incompatibility occurs, can add version pinning later

**Alternative considered:**
- Follow podman's recommended versions (complex, requires parsing release notes)

---

## 8. Directory Structure in Tarball

### Decision: Match podman-static structure

```
{tool}-v{version}/
├── bin/           # All executables
├── lib/           # Helper libraries (if any)
│   └── podman/
└── etc/           # Configuration files
    └── containers/
        ├── policy.json
        └── registries.conf
```

### Rationale

1. Familiar to podman-static users
2. Can extract directly to `/` or `/usr/local`
3. Config files in etc/ allow easy overwrite updates
4. Follows FHS-like structure

---

## Open Questions (Resolved)

| Question | Resolution |
|----------|------------|
| musl vs glibc? | musl for true static |
| ARM build method? | Cross-compile first, native runner fallback |
| Allocator? | mimalloc statically linked |
| Archive format? | .tar.zst |
| Signing? | Sigstore/cosign keyless |
| Notifications? | GitHub Actions built-in |

---

## Next Steps

1. Phase 1: Generate data-model.md and quickstart.md
2. Phase 2: Generate tasks.md with implementation steps
3. Implementation: Start with proof-of-concept for Zig + Go CGO build
