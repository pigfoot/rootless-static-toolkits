# Data Model: Dynamic glibc Build Variant

**Feature**: 002-glibc-build
**Date**: 2025-12-16

## Overview

This feature introduces a new build configuration dimension (libc variant) to the existing build system. The data model describes the configuration entities and their relationships.

## Entities

### BuildVariant

Represents a libc linking strategy for the build.

| Attribute | Type | Values | Description |
|-----------|------|--------|-------------|
| id | string | `static`, `glibc` | Unique identifier |
| libc | string | `musl`, `glibc` | C library used |
| linking | string | `static`, `dynamic` | Linking strategy for libc |
| compiler | string | `clang` | Compiler (unified) |
| target_triple | string | `{arch}-linux-musl`, `{arch}-linux-gnu` | Compiler target |

**Instances**:

| id | libc | linking | compiler | target_triple (amd64) |
|----|------|---------|----------|----------------------|
| static | musl | static | clang | x86_64-linux-musl |
| glibc | glibc | dynamic | clang | x86_64-linux-gnu |

### BuildConfiguration

Represents a complete build specification.

| Attribute | Type | Description |
|-----------|------|-------------|
| tool | string | Tool name: `podman`, `buildah`, `skopeo` |
| arch | string | Architecture: `amd64`, `arm64` |
| variant | BuildVariant | Libc variant: `static`, `glibc` |
| package_variant | string | Package variant: `standalone`, `default`, `full` |
| version | string | Tool version (e.g., `v5.7.1`) |

**Uniqueness**: `(tool, arch, variant, package_variant)`

### BuildArtifact

Represents a produced binary or package.

| Attribute | Type | Description |
|-----------|------|-------------|
| config | BuildConfiguration | Source configuration |
| path | string | Output file path |
| size | integer | File size in bytes |
| checksum | string | SHA256 hash |
| dependencies | list[string] | Dynamic library dependencies (from ldd) |

**Naming Convention**:
```
# Directory structure during build
output/{variant}/{tool}

# Release asset naming
{tool}-{version}-linux-{arch}-{variant}.tar.zst

# Examples
podman-v5.7.1-linux-amd64-static.tar.zst
podman-v5.7.1-linux-amd64-glibc.tar.zst
```

### CompilerConfig

Represents compiler settings for a build variant.

| Attribute | Type | Description |
|-----------|------|-------------|
| variant | BuildVariant | Associated variant |
| cc | string | C compiler command |
| cxx | string | C++ compiler command |
| ar | string | Archive tool |
| ranlib | string | Ranlib tool |
| cgo_cflags | string | CGO C flags |
| cgo_ldflags | string | CGO linker flags |
| extldflags | string | External linker flags |

**Instances**:

| variant | cc | extldflags (key parts) |
|---------|----|-----------------------|
| static | `clang --target=x86_64-linux-musl` | `-static -Wl,--whole-archive -l:libmimalloc.a` |
| glibc | `clang` | `-rtlib=compiler-rt -Wl,-Bstatic -l:libmimalloc.a -Wl,-Bdynamic` |

### ReleaseAsset

Represents a file in a GitHub Release.

| Attribute | Type | Description |
|-----------|------|-------------|
| filename | string | Asset filename |
| content_type | string | MIME type |
| size | integer | File size |
| download_url | string | Download URL |

**Asset Types per Release**:
- `{tool}-{version}-linux-{arch}-static.tar.zst` - Musl static variant
- `{tool}-{version}-linux-{arch}-glibc.tar.zst` - Glibc dynamic variant
- `checksums.txt` - SHA256 checksums
- `*.bundle` - Cosign signature bundles

## Relationships

```
BuildConfiguration
    ├── 1:1 ──> BuildVariant
    └── 1:N ──> BuildArtifact

BuildVariant
    └── 1:1 ──> CompilerConfig

BuildArtifact
    └── 1:1 ──> ReleaseAsset (when released)
```

## State Transitions

### Build Process States

```
[Not Started]
    │
    ▼ (trigger: manual or scheduled)
[Building]
    │
    ├──> [Failed] (on error)
    │
    ▼ (on success)
[Built]
    │
    ▼ (package step)
[Packaged]
    │
    ▼ (sign step)
[Signed]
    │
    ▼ (release step)
[Released]
```

## Validation Rules

1. **BuildVariant.id** must be one of: `static`, `glibc`
2. **BuildConfiguration.arch** must be one of: `amd64`, `arm64`
3. **BuildConfiguration.tool** must be one of: `podman`, `buildah`, `skopeo`
4. **BuildArtifact.dependencies** for `static` variant must be empty (`not a dynamic executable`)
5. **BuildArtifact.dependencies** for `glibc` variant must contain only:
   - `linux-vdso.so.1`
   - `libc.so.6`
   - `/lib64/ld-linux-x86-64.so.2` (or arm64 equivalent)
6. **BuildArtifact.size** for both variants should be within 10% of each other

## Configuration Files

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `LIBC` | Build variant selector | `musl` |
| `ARCH` | Target architecture | `amd64` |
| `VARIANT` | Package variant | `default` |
| `VERSION` | Tool version | (auto-detected) |

### Script Parameters

```bash
# build-tool.sh
./scripts/build-tool.sh <tool> [arch] [package_variant] [libc_variant]

# Examples
./scripts/build-tool.sh podman amd64 default static
./scripts/build-tool.sh podman amd64 default glibc
./scripts/build-tool.sh podman arm64 full static
```
