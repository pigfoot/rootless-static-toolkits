# Podman Rootless Networking Research

**Date:** 2025-12-19
**Podman Version:** v5.7.1 (static build with mimalloc)
**Test Environments:** Gentoo Linux (IPv6), GitHub Actions Ubuntu 24.04 (IPv4 only)

---

## Executive Summary

This document consolidates research on Podman rootless networking, comparing this project's builds with mgoltzsche/podman-static and Ubuntu's native packages.

**Key Findings:**
1. pasta IPv6 issues are now fixed in recent versions
2. mgoltzsche pasta build has SSL issues with some applications (bun)
3. pigfoot builds work correctly in both IPv4 and IPv6 environments
4. standalone variant requires system crun >= 1.25.1

---

## Comparison: pigfoot vs mgoltzsche vs Ubuntu

### Component Versions

| Component | Ubuntu 24.04 | mgoltzsche | pigfoot (full) |
|-----------|--------------|------------|----------------|
| podman | 4.9.3 | 5.7.1 | 5.7.1 |
| crun | 1.14.1 | (bundled) | 1.25.1 |
| pasta | git20240220 | 2025_12_10 | 5.7.1 |

### Test Results (GitHub Actions, 2025-12-18)

| Test Configuration | Network | curl | bun install |
|--------------------|---------|------|-------------|
| Ubuntu native | pasta | ✅ | ✅ |
| mgoltzsche | pasta | ✅ | **❌** |
| pigfoot standalone | pasta | ❌ (crun version) | ❌ |
| pigfoot default | pasta | ✅ | ✅ |
| pigfoot full | pasta | ✅ | ✅ |
| pigfoot glibc-default | pasta | ✅ | ✅ |
| pigfoot glibc-full | pasta | ✅ | ✅ |

**Result: 11/16 tests passed**

### Failure Analysis

**1. standalone failures (4 tests):**
```
error running container: from /usr/bin/crun creating container: unknown version specified
```
- pigfoot podman 5.7.1 requires crun >= 1.25.1
- Ubuntu 24.04's crun 1.14.1 is incompatible
- standalone only includes podman binary, relies on system crun

**2. mgoltzsche pasta failure (1 test):**
```
error: UNKNOWN_CERTIFICATE_VERIFICATION_ERROR downloading package manifest zod
```
- curl test passes, but bun install fails
- mgoltzsche pasta version `2025_12_10.d04c480` has SSL issues
- Other pasta versions (Ubuntu, pigfoot) work correctly

---

## pasta Version Comparison

| Source | Version | IPv6 | SSL/bun | Notes |
|--------|---------|------|---------|-------|
| Ubuntu 24.04 | git20240220 | ✅ | ✅ | Old but stable |
| Gentoo | 2025.06.11 | ✅ | ✅ | |
| pigfoot | 5.7.1 | ✅ | ✅ | |
| **mgoltzsche** | 2025_12_10.d04c480 | ✅ | **❌** | Has SSL bug |

---

## IPv6 Status Update

### Previously Reported Issues (Now Fixed)

| Issue | Status | Notes |
|-------|--------|-------|
| [#22824](https://github.com/containers/podman/issues/22824) | ✅ CLOSED | pasta route error handling fixed |
| [#23003](https://github.com/containers/podman/issues/23003) | ✅ CLOSED | IPv6 outbound traffic fixed |
| [#24580](https://github.com/containers/podman/issues/24580) | NOT_PLANNED | User config issue |
| [#23403](https://github.com/containers/podman/issues/23403) | NOT_PLANNED | Requires routable IPv6 setup |

### Local Testing (Gentoo, IPv6 Environment)

- **16/16 tests passed**, including forced IPv6 (`curl -6`)
- Versions: podman 5.7.0, crun 1.21, pasta 2025.06.11
- Conclusion: Recent pasta versions have fixed IPv6 issues

---

## Variant Selection Guide

### Comparison

| Variant | Contents | Size | System Requirements |
|---------|----------|------|---------------------|
| **standalone** | podman only | ~44MB | crun >= 1.25.1, pasta |
| **default** ⭐ | podman + crun + conmon | ~49MB | pasta (usually available) |
| **full** | podman + crun + all tools | ~74MB | None |

### Recommendations by Scenario

| Scenario | Recommended | Reason |
|----------|-------------|--------|
| GitHub Actions (Ubuntu 24.04) | **default** | Ubuntu has pasta, only needs bundled crun |
| Clean system / Alpine / Minimal | **full** | No external dependencies |
| System has crun >= 1.25.1 | standalone | Smallest size |
| Avoid | mgoltzsche | pasta has SSL issues |

---

## Why Build Workflows Use `--network=host`

### Background

The initial investigation started with SSL timeout errors when downloading Go toolchain:
```
curl: (56) OpenSSL SSL_read: error:0A000126:SSL routines::unexpected eof while reading
```

This looked like an SSL issue but was actually pasta IPv6 routing problems.

### Solution: `--network=host`

```bash
podman run --network=host <image> <command>
```

**Benefits for build scenarios:**
- Bypasses pasta/slirp4netns entirely
- Full IPv4/IPv6 support
- Best performance (no network translation overhead)
- Container uses host network stack directly

**Trade-offs:**
- No network isolation (acceptable for ephemeral build containers)
- Container can listen on host ports (not an issue for build-and-discard pattern)

### Alternative: Force IPv4

```bash
# Force pasta to IPv4 only
podman run --network=pasta:-4 <image> <command>

# Or inside container
curl -4 https://...
```

---

## pasta vs slirp4netns

| Feature | pasta (default) | slirp4netns (legacy) |
|---------|-----------------|---------------------|
| Performance (low concurrency) | Faster (avoids NAT) | Slower |
| Performance (high concurrency >8) | May slow down | Better |
| IPv6 Support | Fixed in recent versions | Has 1-2s startup delay |
| Network Model | Copies host config | Independent NAT |
| Default Since | Podman 5.0+ | Podman 4.x |
| Status | Actively developed | Maintenance mode |

**References:**
- [Rootless network performance discussion](https://github.com/containers/podman/discussions/22559)
- [Oracle Linux pasta documentation](https://docs.oracle.com/en/learn/ol-podman-pasta-networking/)

---

## Docker Rootless Comparison

Docker rootless uses the same underlying technology (slirp4netns, RootlessKit) and has similar IPv6 issues:
- [Docker rootless IPv6 issues (#48257)](https://github.com/moby/moby/issues/48257)
- [slirp4netns IPv6 problems (#305)](https://github.com/rootless-containers/slirp4netns/issues/305)

**Conclusion:** Switching to Docker would not solve IPv6 issues.

---

## Quick Verification Commands

```bash
# Test IPv6 (may fail on older pasta)
podman run --rm ubuntu:latest curl -6 -fsSL https://go.dev/VERSION?m=text

# Test IPv4 (should always work)
podman run --rm ubuntu:latest curl -4 -fsSL https://go.dev/VERSION?m=text

# Test host network (should always work)
podman run --rm --network=host ubuntu:latest curl -fsSL https://go.dev/VERSION?m=text
```

---

## References

### Podman pasta Issues (Historical)
- [pasta IPv6 route failures (#22824)](https://github.com/containers/podman/issues/22824) - FIXED
- [Quadlet IPv6 problems (#24580)](https://github.com/containers/podman/issues/24580)
- [pasta IPv6 port mapping (#23403)](https://github.com/containers/podman/issues/23403)
- [pasta outbound traffic (#23003)](https://github.com/containers/podman/issues/23003) - FIXED

### Performance & Comparison
- [pasta vs slirp4netns performance](https://github.com/containers/podman/discussions/22559)
- [Podman rootless tutorial](https://github.com/containers/podman/blob/main/docs/tutorials/rootless_tutorial.md)

### Docker Rootless
- [Docker rootless IPv6 issues (#48257)](https://github.com/moby/moby/issues/48257)
- [slirp4netns IPv6 problems (#305)](https://github.com/rootless-containers/slirp4netns/issues/305)

---

**Document Version:** 1.0
**Based on:** Original research from 2025-12-16 to 2025-12-19
