# Research: Dynamic glibc Build Variant

**Feature**: 002-glibc-build
**Date**: 2025-12-16
**Source**: Consolidated from `/home/pigfoot/podman-mimalloc-build-research.md` and additional analysis

## Executive Summary

This research validates the feasibility of adding a glibc-dynamic build variant alongside the existing musl-static builds. Key findings:

1. **Binary size parity**: Both variants produce ~43MB binaries
2. **NSS limitations don't affect Podman**: Go's Pure Go resolver bypasses NSS
3. **IPv6 issues are network-layer**: Unrelated to libc choice (pasta bug)
4. **Unified Clang toolchain**: Both variants can use Clang

## Research Areas

### 1. Glibc Build Configuration

**Decision**: Use Clang with glibc (no musl target flag)

**Rationale**:
- Unified toolchain simplifies maintenance
- Clang produces comparable or better optimized code
- compiler-rt replaces libgcc for pure Clang builds

**Configuration**:
```bash
# Glibc dynamic build with Clang
CC="clang"
CXX="clang++"
AR="llvm-ar"
RANLIB="llvm-ranlib"

CGO_ENABLED=1
CGO_CFLAGS="-I$MIMALLOC_DIR/include -w"
CGO_LDFLAGS=""

# Partial static linking: static mimalloc/pthread, dynamic glibc
EXTLDFLAGS="-rtlib=compiler-rt -L${MIMALLOC_LIB_DIR} -Wl,-Bstatic -Wl,--whole-archive -l:libmimalloc.a -Wl,--no-whole-archive -lpthread -Wl,-Bdynamic"
```

**Alternatives Considered**:
- GCC for glibc builds: Rejected (requires maintaining two compilers)
- Static glibc: Not feasible (glibc doesn't support static NSS)

### 2. Binary Size Comparison

**Decision**: Both variants acceptable (~43MB)

**Research Data** (from actual builds):

| Variant | Size (bytes) | Size (MB) | Difference |
|---------|-------------|-----------|------------|
| Musl static | 44,719,048 | 43M | baseline |
| Glibc dynamic | 44,614,536 | 43M | -104KB |

**Rationale**:
- Go code dominates binary size
- libc choice has minimal impact (~100KB)
- mimalloc adds ~200KB to both

**Alternatives Considered**:
- UPX compression: Rejected (startup time penalty)
- LTO: Already enabled via Clang

### 3. Glibc Version Requirements

**Decision**: Require glibc 2.34+ for glibc variant

**Research Data** (from objdump analysis):
```
GLIBC_2.34: pthread_create, pthread_join, __libc_start_main, shm_open
GLIBC_2.38: __isoc23_strtol (optional, fallback exists)
```

**Compatibility Matrix**:

| Distribution | glibc Version | Compatible |
|--------------|---------------|------------|
| Ubuntu 22.04 | 2.35 | ✅ |
| Ubuntu 24.04 | 2.39 | ✅ |
| Debian 12 | 2.36 | ✅ |
| RHEL 9 | 2.34 | ✅ |
| Ubuntu 20.04 | 2.31 | ❌ |
| Debian 11 | 2.31 | ❌ |
| Alpine | N/A (musl) | ❌ |

**Rationale**: glibc 2.34 is the minimum that includes unified pthread

### 4. NSS (Name Service Switch) Impact

**Decision**: NSS limitations don't affect Podman functionality

**Research Findings**:

Go's `net` package uses Pure Go resolver by default:
- Reads `/etc/hosts` and `/etc/resolv.conf` directly
- Does NOT call libc's `getaddrinfo`
- Does NOT require `/etc/nsswitch.conf`
- Does NOT need NSS plugins

**Test Results**:

| Feature | Musl Static | Glibc Dynamic |
|---------|-------------|---------------|
| DNS resolution | ✅ Works | ✅ Works |
| Image pull | ✅ Works | ✅ Works |
| Container run | ✅ Works | ✅ Works |
| User mapping | ✅ Works | ✅ Works |

**Edge Cases** (glibc advantage):
- LDAP user authentication: glibc only
- mDNS (.local domains): glibc only
- systemd-resolved integration: glibc only

**Rationale**: These edge cases are rare for container tool usage

### 5. IPv6 Network Issues

**Decision**: Use `--network=host` for builds (unrelated to libc choice)

**Root Cause**: pasta/slirp4netns IPv6 routing bug in Podman 5.0+

**Evidence**:
```bash
# Both variants fail identically
$ podman run --rm ubuntu curl -6 https://go.dev  # timeout
$ podman run --rm ubuntu curl -4 https://go.dev  # works

# Host network bypasses pasta
$ podman run --rm --network=host ubuntu curl https://go.dev  # works
```

**Related Issues**:
- [containers/podman#22824](https://github.com/containers/podman/issues/22824)
- [containers/podman#24580](https://github.com/containers/podman/issues/24580)

### 6. Build Tool Installation

**Decision**: Use `uv` for Python tools, direct download for cmake

**Rationale**:
- `uv` is fast and provides latest stable versions
- Avoids stale distro packages
- cmake direct download from Kitware is well-supported

**Implementation**:
```bash
# Install uv
curl -LsSf https://astral.sh/uv/install.sh | sh

# Install Python-based tools
uvx meson --version  # or uv tool install meson ninja
uvx ninja --version

# Install cmake (direct download)
CMAKE_VERSION=$(curl -s https://api.github.com/repos/Kitware/CMake/releases/latest | jq -r .tag_name)
curl -LO "https://github.com/Kitware/CMake/releases/download/${CMAKE_VERSION}/cmake-${CMAKE_VERSION#v}-linux-x86_64.tar.gz"
```

**Alternatives Considered**:
- pip install: Slower, needs Python venv management
- apt packages: Stale versions

### 7. Package Minimization

**Decision**: Remove redundant packages from setup-build-env.sh

**Packages to Remove**:
- `cmake` (install via direct download)
- `meson` (install via uv)
- `ninja-build` (install via uv)
- `gcc`, `g++`, `build-essential` (using Clang)

**Packages to Keep**:
- `musl-dev`, `musl-tools` (musl builds)
- `libc6-dev` (glibc headers)
- `autoconf`, `automake`, `libtool` (autotools for dependencies)
- `pkg-config` (dependency discovery)
- `libglib2.0-dev`, `libcap-dev` (container tool dependencies)
- `git`, `curl`, `ca-certificates`, `zstd` (build essentials)
- `protobuf-compiler` (Rust components)
- `gperf` (libcap build)

**Impact**: Faster container setup, smaller attack surface

## Linking Strategy Comparison

| Component | Musl Static | Glibc Dynamic |
|-----------|-------------|---------------|
| C library | musl (static) | glibc (dynamic) |
| C++ stdlib | libstdc++ (static) | libstdc++ (static) |
| pthread | static | static |
| mimalloc | static (--whole-archive) | static (--whole-archive) |
| Go runtime | static | static |
| Compiler runtime | N/A | compiler-rt (static) |

## User Guidance Decision Tree

```
┌─ Maximum portability needed?
│  └─ YES → Static variant (musl)
│
├─ Target only modern distros (Ubuntu 22.04+)?
│  └─ YES → Either variant works
│
├─ Enterprise environment with LDAP/NIS?
│  └─ YES → Glibc variant
│
├─ Deploying to containers/minimal images?
│  └─ YES → Static variant (musl)
│
└─ Default recommendation
   └─ Static variant (maximum compatibility)
```

## Static Linking Strategies (Detailed Reference)

For comprehensive static linking strategies, build system specific solutions, and troubleshooting guides, see:

**[static-linking-strategies.md](./static-linking-strategies.md)**

This companion document covers:
- Strategy comparison: musl vs glibc-dynamic
- Compiler choice: GCC vs Clang
- C/C++ projects: Full static and glibc dynamic configurations
- Go projects: CGO linking strategies
- Rust projects: musl vs gnu targets, libgcc_s.so.1 handling
- **Autotools + libtool linking issues**: Complete case study on debugging crun libcap linking
- Build system specific solutions (Makefile, autotools, CMake, Meson)
- Verification checklist and common issues
- Real-world debugging examples with systematic approaches

**Key highlights from the document:**

### Plain Makefile Linking (conmon example)
```makefile
# Linking order matters
$(CC) $(LDFLAGS) $(CFLAGS) -o $@ $^ $(LIBS)
      ↑                           ↑   ↑
      LDFLAGS (before objs)      objs  LIBS (after objs)
```

**Problem**: Libraries in LDFLAGS come before object files → linker discards them
**Solution**: Move libraries to LIBS variable (after object files)

### Autotools + libtool Linking (crun example)
**Problem**: libtool rewrites `-l` flags and filters `-Wl,-Bstatic` flags
**Root cause**: libtool's design - controls static/dynamic via `--static` flag, not `-Wl,-Bstatic`
**Solution**: Use direct `.a` file paths (libtool cannot rewrite file paths)

```bash
# Before (BROKEN) - libtool filters -Wl,-Bstatic
make FOUND_LIBS="-Wl,-Bstatic -lcap -lseccomp -Wl,-Bdynamic -lm"

# After (FIXED) - libtool cannot modify file paths
LIBCAP_A="/usr/lib/x86_64-linux-gnu/libcap.a"
LIBSECCOMP_A="/workspace/libseccomp-install/lib/libseccomp.a"
make FOUND_LIBS="$LIBCAP_A $LIBSECCOMP_A -lm"
```

### Why This Works
| Method | What libtool does | Result |
|--------|------------------|--------|
| `-lcap` | Searches for libcap.so → finds .so → dynamic link | ❌ Dynamic |
| `-Wl,-Bstatic -lcap` | **Filters out -Wl,-Bstatic**, then `-lcap` → finds .so | ❌ Still dynamic |
| `/usr/lib/.../libcap.a` | **Cannot rewrite file paths** → uses .a directly | ✅ Static |

### Rust libgcc_s.so.1 Handling
For Rust binaries with glibc target:
- ✅ **libgcc_s.so.1 is acceptable** - system library providing unwinding support
- ❌ **Cannot be eliminated** with `-static-libgcc` or `build-std` (tested, doesn't work)
- Alternative: Use musl target for fully static Rust binaries

See the full document for complete implementation patterns, diagnostic commands, and real-world case studies.

---

## References

- [Go DNS resolution](https://github.com/golang/go/issues/33019)
- [musl vs glibc differences](https://wiki.musl-libc.org/functional-differences-from-glibc.html)
- [pasta IPv6 issues](https://github.com/containers/podman/issues/22824)
- [mimalloc integration](https://github.com/microsoft/mimalloc)
- [GNU Libtool: Linking libraries](https://www.gnu.org/software/libtool/manual/html_node/Linking-libraries.html)
- [Libtool static library issues](https://lists.gnu.org/archive/html/libtool/2009-09/msg00030.html)
- [Bug#11064: libtool makes static linking impossible](https://bug-libtool.gnu.narkive.com/OKGVfnB3/bug-11064-critical-libtool-makes-static-linking-impossible)
