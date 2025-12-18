# Quickstart: Building Static and Glibc Variants

**Feature**: 002-glibc-build
**Date**: 2025-12-16

## Prerequisites

- Linux host (amd64 or arm64)
- Podman or Docker installed
- Internet connection for downloading dependencies

## Quick Build Commands

### Build Static Variant (musl, recommended)

```bash
# Build podman static variant
make build-podman ARCH=amd64 LIBC=static

# Or using the script directly
./scripts/build-tool.sh podman amd64 default static
```

### Build Glibc Variant

```bash
# Build podman glibc variant
make build-podman ARCH=amd64 LIBC=glibc

# Or using the script directly
./scripts/build-tool.sh podman amd64 default glibc
```

### Build Both Variants

```bash
# Build both variants for podman
make build-podman-all ARCH=amd64
```

## Build Output

After building, artifacts are located in:

```
build/
├── podman-amd64/
│   └── install/
│       └── bin/
│           └── podman          # Static variant
└── podman-amd64-glibc/
    └── install/
        └── bin/
            └── podman          # Glibc variant
```

## Verification

### Verify Static Variant

```bash
# Should show "not a dynamic executable"
ldd build/podman-amd64/install/bin/podman

# Expected output:
# not a dynamic executable
```

### Verify Glibc Variant

```bash
# Should show only glibc dependencies
ldd build/podman-amd64-glibc/install/bin/podman

# Expected output:
# linux-vdso.so.1 (0x...)
# libc.so.6 => /lib/x86_64-linux-gnu/libc.so.6 (0x...)
# /lib64/ld-linux-x86-64.so.2 (0x...)
```

### Verify mimalloc Integration

```bash
# Check for mimalloc symbols
nm build/podman-amd64/install/bin/podman | grep mi_malloc
nm build/podman-amd64-glibc/install/bin/podman | grep mi_malloc

# Both should show mimalloc symbols
```

## Container-based Build

For consistent builds using the Ubuntu container:

```bash
# Pull the build container
podman pull docker.io/ubuntu:latest

# Run build inside container
podman run --rm \
    --network=host \
    -v $(pwd):/workspace:Z \
    -w /workspace \
    docker.io/ubuntu:latest \
    bash -c "
        ./scripts/container/setup-build-env.sh
        ./scripts/build-tool.sh podman amd64 default static
        ./scripts/build-tool.sh podman amd64 default glibc
    "
```

## Packaging

After building, create release packages:

```bash
# Package static variant
./scripts/package.sh podman amd64 static

# Package glibc variant
./scripts/package.sh podman amd64 glibc

# Output:
# podman-v5.7.1-linux-amd64-static.tar.zst
# podman-v5.7.1-linux-amd64-glibc.tar.zst
```

## Choosing a Variant

| Use Case | Recommended Variant |
|----------|---------------------|
| Maximum portability | static |
| CI/CD runners | static |
| Container deployments | static |
| Modern distros (Ubuntu 22.04+) | either |
| Enterprise (LDAP/NIS) | glibc |
| Default recommendation | static |

## Troubleshooting

### Build fails with network errors

Use `--network=host` when running in containers:

```bash
podman run --rm --network=host ...
```

### Missing musl-tools

Install musl development packages:

```bash
# Ubuntu/Debian
apt-get install musl-dev musl-tools

# The container setup script handles this automatically
```

### Glibc variant fails on older systems

The glibc variant requires glibc 2.34+. Check your system:

```bash
ldd --version
# Must show 2.34 or higher
```

If your system has older glibc, use the static variant instead.
