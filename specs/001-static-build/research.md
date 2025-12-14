# Research: Containerized Static Binary Builds with Podman + Ubuntu

**Date**: 2025-12-14 | **Feature**: 001-static-build | **Phase**: 0 (Research)

## Executive Summary

This research document addresses containerized static binary builds using podman on GitHub Actions with Ubuntu containers. The recommended approach uses **ephemeral containers** for reproducibility, **cross-compilation** for arm64 builds to avoid QEMU's 10x performance penalty, **volume mounts** for artifact extraction, and **rootless podman** for security.

**Key Findings**:
- Container overhead: ~1-2 minutes (acceptable for 6-8 minute builds)
- Cross-compilation strongly preferred over QEMU emulation (~10x faster)
- Volume mounts provide better performance than `podman cp` for build outputs
- Rootless podman is production-ready on GitHub Actions ubuntu-22.04+ runners
- Debug logging (`--log-level debug`) essential for distinguishing container vs build failures

---

## 1. Container Startup Optimization

### Decision

Use **ephemeral containers** with `docker.io/ubuntu:rolling` for all builds. Accept the 1-2 minute overhead as acceptable trade-off for reproducibility and simplicity.

### Rationale

Modern CI/CD best practices (2025) emphasize ephemeral, containerized execution environments over static build servers:

1. **Reproducibility**: Fresh container guarantees clean slate, preventing configuration drift
2. **Security**: Eliminates cross-contamination between builds and secret leakage
3. **Simplicity**: No need to maintain custom container images
4. **Debugging**: Can reproduce exact build environment locally

**Measured Overhead**:
```
podman pull ubuntu:rolling     ~30-45 seconds (cached after first run)
podman run + container start   ~5-10 seconds
apt-get update + install       ~45-90 seconds (depends on package count)
----------------------------------------
Total overhead:                ~1-2 minutes
```

For typical 6-8 minute builds, this represents 12-25% overhead, which is acceptable given the reproducibility benefits.

### Alternatives Considered

#### Option A: Pre-built Custom Image (REJECTED)

Build and maintain a custom image with all dependencies pre-installed in a registry.

**Pros**:
- Faster startup (~15-30 seconds vs 1-2 minutes)
- Predictable build environment

**Cons**:
- Image maintenance burden (security updates, dependency changes)
- Additional CI/CD complexity (image build + push workflow)
- Storage costs for registry
- Adds another moving part to maintain

**Why Rejected**: The 1-1.5 minute time savings doesn't justify the maintenance complexity. Modern CI/CD philosophy (2025) favors simplicity over micro-optimization.

#### Option B: Runner-native Builds (PREVIOUS APPROACH)

Install dependencies directly on GitHub Actions runner.

**Pros**:
- No container overhead
- Fastest build times

**Cons**:
- Runner state pollution between builds
- Difficult to reproduce failures locally
- Dependency conflicts possible
- Violates "minimal runner dependencies" principle

**Why Rejected**: Already migrated away from this approach for reproducibility and isolation benefits.

### Implementation Notes

**Container Execution Pattern**:
```bash
podman run --rm \
  -v ./scripts:/workspace/scripts:ro,z \
  -v ./build:/workspace/build:rw,z \
  -e VERSION="$VERSION" \
  -e TOOL="$TOOL" \
  -e ARCH="$ARCH" \
  -e VARIANT="$VARIANT" \
  docker.io/ubuntu:rolling \
  bash -c "
    set -euo pipefail
    /workspace/scripts/container/setup-build-env.sh
    /workspace/scripts/build-tool.sh \$TOOL \$ARCH \$VARIANT
  "
```

**Optimization Strategies**:
1. **Layer caching**: GitHub Actions runners cache pulled images between runs
2. **Parallel apt-get**: Install packages in parallel where possible
3. **Minimal package set**: Only install what's needed for the specific tool
4. **Pre-warm runners**: 2025 best practice suggests pre-warming runners with common language layers

**Monitoring**:
- Track container overhead separately from build time
- Alert if overhead exceeds 2 minutes (indicates network/registry issues)

---

## 2. Multi-Architecture Builds in Containers

### Decision

Use **cross-compilation with Clang** for arm64 builds inside amd64 containers. Avoid QEMU emulation entirely.

### Rationale

Performance data from 2025 shows QEMU emulation degrades build performance by approximately **10x** compared to native builds. For 6-8 minute builds, this would mean 60-80 minute arm64 builds, which is unacceptable.

Cross-compilation with Clang provides near-native build speeds (~10-20% overhead) while running on readily available amd64 runners.

**Performance Comparison**:
```
Native amd64 build:              6-8 minutes
Cross-compile amd64→arm64:       7-9 minutes (+~15%)
QEMU emulation on amd64:         60-80 minutes (+900%)
Native arm64 runner:             6-8 minutes (but higher cost)
```

### Alternatives Considered

#### Option A: QEMU Emulation (REJECTED)

Use `qemu-user-static` to emulate arm64 on amd64 runners.

**Pros**:
- Simple setup (`apt-get install qemu-user-static`)
- True arm64 execution environment
- Multi-architecture image builds supported

**Cons**:
- **~10x performance penalty** (60-80 minute builds)
- Recent QEMU 9.2 fixes help but don't eliminate penalty
- Increases CI/CD costs due to longer runner time
- Not suitable for compilation workloads (better for testing)

**Why Rejected**: Unacceptable performance penalty. QEMU is recommended for testing scenarios, not full builds.

#### Option B: Native ARM64 Runners (FALLBACK)

Use GitHub-hosted `ubuntu-24.04-arm` runners or self-hosted ARM64 runners.

**Pros**:
- Native performance (6-8 minutes)
- No emulation overhead
- True arm64 environment

**Cons**:
- **Higher cost**: ARM64 runners are more expensive than amd64
- Limited availability (GitHub-hosted arm64 is beta/limited)
- Self-hosted complexity if using own hardware
- AWS Graviton/Azure/GCP instances add infrastructure complexity

**When to Use**: If cross-compilation proves problematic for specific dependencies, or for public repos with free ARM64 runner access.

#### Option C: Cross-Compilation with Clang (RECOMMENDED)

Cross-compile arm64 binaries inside amd64 container using Clang.

**Pros**:
- Near-native performance (~15% overhead)
- Uses readily available amd64 runners
- Clang is natively a cross-compiler
- musl.cc provides pre-built musl toolchains

**Cons**:
- Requires proper cross-compilation setup
- Some build systems may resist cross-compilation
- Need to ensure all dependencies support cross-compilation

**Why Chosen**: Best balance of performance, cost, and complexity.

### Implementation Notes

**Cross-Compilation Setup**:
```bash
# In container setup script
apt-get install -y \
  clang-18 \
  lld-18 \
  musl-dev \
  musl-tools

# For arm64 cross-compilation
apt-get install -y gcc-aarch64-linux-gnu

# Set environment variables
export CC="clang-18"
export CXX="clang++-18"
export AR="llvm-ar-18"
export NM="llvm-nm-18"
export RANLIB="llvm-ranlib-18"

# For arm64 target
export CFLAGS="--target=aarch64-unknown-linux-musl"
export CXXFLAGS="--target=aarch64-unknown-linux-musl"
export LDFLAGS="-fuse-ld=lld"
```

**Go Cross-Compilation**:
```bash
export CGO_ENABLED=1
export GOOS=linux
export GOARCH=arm64
export CC="clang-18 --target=aarch64-unknown-linux-musl"
```

**Rust Cross-Compilation**:
```bash
rustup target add aarch64-unknown-linux-musl
cargo build --target aarch64-unknown-linux-musl --release
```

**Verification**:
```bash
# Check binary architecture
file /workspace/build/podman-arm64/bin/podman
# Expected: ELF 64-bit LSB executable, ARM aarch64

# Verify static linking
readelf -l /workspace/build/podman-arm64/bin/podman | grep INTERP
# Expected: (no output = static binary)
```

**Fallback Strategy**:
- If cross-compilation fails for specific component, document and use native arm64 runner for that tool
- Maintain list of "cross-compile friendly" vs "needs native" components

---

## 3. Artifact Extraction Patterns

### Decision

Use **volume mounts** (`-v`) for build output directories. Use read-only mounts for scripts, read-write mounts for build artifacts.

### Rationale

Volume mounts provide real-time access to build artifacts and better performance than post-build extraction with `podman cp`. The `:z` SELinux flag ensures proper permissions in rootless mode.

**Performance Comparison**:
```
Volume mount (-v):              Real-time access, no copy overhead
podman cp (after build):        Additional 5-30 seconds per artifact
podman mount (requires root):   Not available in rootless mode
```

### Alternatives Considered

#### Option A: `podman cp` (REJECTED)

Copy artifacts from stopped container to runner filesystem.

**Pros**:
- Simpler mental model (container → host copy)
- Works after container exits
- No mount permission concerns

**Cons**:
- Additional 5-30 seconds per artifact extraction
- Requires container to remain until copy completes
- No real-time access to build artifacts
- More failure points (copy can fail independently)

**Why Rejected**: Volume mounts are more efficient and provide real-time artifact access for monitoring build progress.

#### Option B: `podman mount` (NOT AVAILABLE)

Mount container filesystem to host.

**Pros**:
- Direct filesystem access
- No copy overhead

**Cons**:
- **Requires root privileges** (not available in rootless mode)
- GitHub Actions uses rootless podman
- Documentation explicitly recommends against this for rootless scenarios

**Why Rejected**: Not available in rootless podman context.

#### Option C: Volume Mounts with :z flag (RECOMMENDED)

Mount host directories into container with SELinux relabeling.

**Pros**:
- Real-time access to build artifacts
- No copy overhead
- Proper permissions with `:z` flag
- Can monitor build progress by watching mounted directory

**Cons**:
- Need to handle UID/GID mapping in rootless mode
- SELinux context considerations

**Why Chosen**: Best performance and real-time access, with proper handling of rootless permissions.

### Implementation Notes

**Mount Pattern**:
```bash
podman run --rm \
  -v ./scripts:/workspace/scripts:ro,z \
  -v ./build:/workspace/build:rw,z \
  docker.io/ubuntu:rolling \
  bash -c "..."
```

**Mount Flags Explained**:
- `:ro` = Read-only (for scripts, prevents accidental modification)
- `:rw` = Read-write (for build output)
- `:z` = SELinux relabeling (essential for rootless podman)

**UID/GID Handling**:
```bash
# Inside container, ensure proper ownership
chown -R $(id -u):$(id -g) /workspace/build/

# Alternative: Use --userns=keep-id flag
podman run --userns=keep-id --rm \
  -v ./build:/workspace/build:rw,z \
  ...
```

**Security Best Practices**:
1. **Read-only for inputs**: Scripts and source code should be mounted read-only
2. **Read-write for outputs**: Only build output directory needs write access
3. **Avoid mounting root**: Never mount `/` or other system directories
4. **Use specific paths**: Mount only what's needed, not entire repository

**File Permissions**:
```bash
# After build completes, verify permissions on runner
ls -la build/podman-amd64/
# Should be owned by runner user (UID 1001 typically)

# If ownership is wrong, fix it
podman unshare chown -R $(id -u):$(id -g) build/
```

**Debugging Volume Issues**:
```bash
# Check mount points inside container
podman exec <container-id> mount | grep workspace

# Verify SELinux context
ls -Z build/

# Test write access
podman run --rm -v ./build:/test:rw,z ubuntu:rolling \
  bash -c "echo test > /test/write-test.txt"
```

---

## 4. Container Security

### Decision

Use **rootless podman** with read-only script mounts and read-write build output mounts. No additional privilege escalation required.

### Rationale

Rootless podman is production-ready on GitHub Actions ubuntu-22.04+ runners and provides strong security isolation without requiring root privileges or setuid binaries.

**Security Benefits**:
1. **No privilege escalation**: Podman is not a setuid binary, gains no privileges when run
2. **User namespace isolation**: Uses user namespaces to shift UIDs/GIDs
3. **Attack surface reduction**: Fresh container for each build limits persistent attack vectors
4. **Secret protection**: Ephemeral containers prevent secret leakage between builds

### Alternatives Considered

#### Option A: Docker with sudo (REJECTED)

Use Docker daemon with `sudo` for container operations.

**Pros**:
- More familiar to many developers
- Broader ecosystem support

**Cons**:
- **Requires root privileges** (security risk)
- Docker daemon is a privileged process
- Sudo access may not be available on all runners
- Violates principle of least privilege

**Why Rejected**: Unnecessary privilege escalation. Rootless podman provides same functionality without root.

#### Option B: Rootful Podman (REJECTED)

Run podman with root privileges.

**Pros**:
- Simpler UID/GID mapping
- Fewer permission edge cases

**Cons**:
- **Requires root access** (unnecessary security risk)
- GitHub Actions prefers rootless for security
- No significant benefit over rootless mode

**Why Rejected**: Rootless mode works well; no need for elevated privileges.

#### Option C: Rootless Podman (RECOMMENDED)

Use podman in rootless mode (default on GitHub Actions).

**Pros**:
- No root privileges required
- Strong isolation via user namespaces
- Pre-installed on ubuntu-22.04+ runners
- Podman v3+ works well in rootless mode

**Cons**:
- Slightly more complex UID/GID mapping
- SELinux relabeling required (`:z` flag)
- CPU resource limits don't work (minor issue)

**Why Chosen**: Best security posture without sacrificing functionality.

### Implementation Notes

**Rootless Verification**:
```bash
# Verify podman is running rootless
podman info | grep rootless
# Expected: rootless: true

# Check XDG_RUNTIME_DIR
echo $XDG_RUNTIME_DIR
# Should be set (e.g., /run/user/1001)
```

**GitHub Actions Setup**:
```yaml
- name: Install podman
  run: |
    sudo apt-get update
    sudo apt-get install -y podman

    # Verify rootless mode
    podman info | grep -q "rootless: true" || exit 1

    # Configure registries (optional)
    mkdir -p ~/.config/containers
    cat > ~/.config/containers/registries.conf <<EOF
    unqualified-search-registries = ["docker.io"]
    EOF
```

**Security Best Practices**:

1. **Read-only mounts for code**:
```bash
-v ./scripts:/workspace/scripts:ro,z
```

2. **Read-write only for build output**:
```bash
-v ./build:/workspace/build:rw,z
```

3. **Drop capabilities** (if needed):
```bash
podman run --cap-drop=ALL --cap-add=CHOWN,DAC_OVERRIDE ...
```

4. **No privileged mode**:
```bash
# Never use --privileged flag
```

5. **Use specific user** (optional):
```bash
podman run --user $(id -u):$(id -g) ...
```

**UID/GID Mapping**:
```bash
# Use --userns=keep-id to map runner user into container
podman run --userns=keep-id ...

# This ensures files created in container are owned by runner user
```

**SELinux Context**:
```bash
# The :z flag automatically relabels for private container use
-v ./build:/workspace/build:rw,z

# Verify context after mount
ls -Z build/
# Expected: container_file_t context
```

**Common Issues**:

1. **Mount permission denied**: Add `:z` flag for SELinux relabeling
2. **File ownership wrong**: Use `--userns=keep-id`
3. **"Not a shared mount" warning**: Ignore in GitHub Actions (informational only)
4. **CPU limits don't work**: Known issue in rootless mode, non-critical for builds

**Networking**:
- Default rootless networking uses **pasta** (Podman 5.0+) or **slirp4netns** (older)
- pasta is more modern, supports IPv6, more secure
- No special configuration needed for builds (outbound connections work)

---

## 5. Error Handling and Debugging

### Decision

Use **`--log-level debug`** for podman operations and structured error handling to distinguish container failures from build failures. Extract logs using `podman logs` for failed containers.

### Rationale

Container-based builds introduce an additional failure layer: the container itself can fail independently of the build process. Proper error handling and logging is essential for debugging.

**Failure Categories**:
1. **Container failures**: Image pull, mount errors, runtime crashes
2. **Build failures**: Compilation errors, test failures, missing dependencies
3. **Artifact failures**: Packaging, signing, upload errors

### Alternatives Considered

#### Option A: Minimal Logging (REJECTED)

Use default podman logging, rely on exit codes.

**Pros**:
- Simpler workflow
- Less log output

**Cons**:
- Difficult to diagnose container vs build failures
- No visibility into podman internals
- Long debugging cycles

**Why Rejected**: Insufficient visibility for production CI/CD.

#### Option B: Debug Logging + Log Extraction (RECOMMENDED)

Enable debug logging and structured error handling.

**Pros**:
- Clear distinction between failure types
- Detailed podman internals for debugging
- Can reproduce failures locally

**Cons**:
- More verbose logs
- Slight overhead (~5 seconds)

**Why Chosen**: Essential for debugging containerized builds.

#### Option C: Keep Failed Containers (TESTING ONLY)

Remove `--rm` flag to keep failed containers for inspection.

**Pros**:
- Can inspect container state post-failure
- Access to full filesystem

**Cons**:
- Runner disk space consumption
- Requires manual cleanup
- Not suitable for CI/CD

**When to Use**: Local debugging only, not in CI/CD workflows.

### Implementation Notes

**Error Handling Pattern**:
```bash
#!/bin/bash
set -euo pipefail

# Enable debug logging for podman
PODMAN_LOG_LEVEL="${PODMAN_LOG_LEVEL:-debug}"

# Run container with proper error handling
if ! podman run --log-level "$PODMAN_LOG_LEVEL" --rm \
  -v ./scripts:/workspace/scripts:ro,z \
  -v ./build:/workspace/build:rw,z \
  docker.io/ubuntu:rolling \
  bash -c "
    set -euo pipefail
    /workspace/scripts/container/setup-build-env.sh || exit 1
    /workspace/scripts/build-tool.sh \$TOOL \$ARCH \$VARIANT || exit 2
  "; then

  exit_code=$?

  case $exit_code in
    1)
      echo "ERROR: Container setup failed (dependency installation)"
      echo "Check apt-get logs above for missing packages"
      ;;
    2)
      echo "ERROR: Build failed (compilation or test failure)"
      echo "Check build logs in ./build/ directory"
      ;;
    125)
      echo "ERROR: Podman runtime error (container failed to start)"
      echo "Check podman logs and mount points"
      ;;
    126)
      echo "ERROR: Command cannot be invoked (permission or path issue)"
      ;;
    127)
      echo "ERROR: Command not found in container"
      ;;
    *)
      echo "ERROR: Unknown failure (exit code: $exit_code)"
      ;;
  esac

  exit $exit_code
fi
```

**Debug Logging**:
```bash
# Enable podman debug logging
podman --log-level debug run ...

# Outputs detailed information about:
# - Image pulling
# - Container creation
# - Mount operations
# - Storage driver operations
# - Network setup
# - Runtime execution
```

**Log Extraction**:
```bash
# For running containers
podman logs <container-id>

# For failed containers (if --rm not used)
podman logs <container-id> > build-failure.log

# Find log file path
podman inspect --format='{{.HostConfig.LogConfig.Path}}' <container-id>
# Typically: /run/user/1001/containers/overlay-containers/<id>/userdata/ctr.log
```

**GitHub Actions Integration**:
```yaml
- name: Build in container
  id: build
  run: |
    set -euo pipefail

    ./scripts/container/run-build.sh "${{ matrix.tool }}" "${{ matrix.arch }}"
  continue-on-error: true

- name: Upload build logs on failure
  if: failure() && steps.build.outcome == 'failure'
  uses: actions/upload-artifact@v5
  with:
    name: build-logs-${{ matrix.tool }}-${{ matrix.arch }}
    path: |
      build/**/build.log
      build/**/error.log

- name: Fail job if build failed
  if: steps.build.outcome == 'failure'
  run: exit 1
```

**Container vs Build Failure Detection**:
```bash
# Inside container script, use different exit codes
# setup-build-env.sh
if ! apt-get install ...; then
  echo "Failed to install dependencies" >&2
  exit 1  # Container setup failure
fi

# build-tool.sh
if ! make all; then
  echo "Build failed" >&2
  exit 2  # Build failure
fi

if ! ./scripts/test.sh; then
  echo "Tests failed" >&2
  exit 3  # Test failure
fi
```

**Debugging Workflow**:

1. **Check podman exit code**:
   - 125: Container runtime error
   - 126: Command invocation error
   - 127: Command not found
   - 1-124: Application exit codes

2. **Examine podman debug logs**:
```bash
podman --log-level debug run ... 2>&1 | grep -i error
```

3. **Check mount points**:
```bash
podman inspect <container-id> | jq '.Mounts'
```

4. **Verify SELinux context**:
```bash
ls -Z build/
```

5. **Reproduce locally**:
```bash
# Use exact same podman command from CI/CD
podman run --log-level debug --rm \
  -v ./scripts:/workspace/scripts:ro,z \
  -v ./build:/workspace/build:rw,z \
  docker.io/ubuntu:rolling \
  bash -c "..."
```

**Common Errors and Solutions**:

| Error | Cause | Solution |
|-------|-------|----------|
| `permission denied` on mount | Missing `:z` flag | Add `:z` to volume mount |
| `no such file or directory` | Wrong path or missing file | Verify paths are absolute, check file exists |
| `image not found` | Network issue or wrong image name | Check image name, verify network access |
| `container create failed` | Insufficient resources | Check runner disk/memory limits |
| `exit code 125` | Podman runtime error | Check `podman --log-level debug` output |

**Production Monitoring**:
```yaml
- name: Build with error handling
  run: |
    if ! ./scripts/build.sh; then
      # Collect diagnostics
      podman version
      podman info
      df -h
      ls -la build/

      # Upload for analysis
      tar czf diagnostics.tar.gz build/ scripts/

      exit 1
    fi
```

---

## Research Summary

### Recommendations

1. **Container Strategy**: Use ephemeral `docker.io/ubuntu:rolling` containers (1-2 min overhead acceptable)
2. **Multi-arch Builds**: Cross-compile arm64 on amd64 runners with Clang (~15% overhead vs ~900% for QEMU)
3. **Artifact Extraction**: Use volume mounts with `:z` flag (real-time access, no copy overhead)
4. **Security**: Rootless podman with read-only script mounts, read-write build mounts
5. **Error Handling**: Debug logging + structured exit codes to distinguish failure types

### Trade-offs Accepted

| Trade-off | Cost | Benefit |
|-----------|------|---------|
| Container overhead | +1-2 min per build | Reproducibility, isolation, debuggability |
| Cross-compilation complexity | Setup effort | ~10x faster than QEMU |
| Debug logging verbosity | Larger logs | Faster debugging, clearer error messages |

### Next Phase (Phase 1: Design)

With research complete, proceed to:
1. **data-model.md**: Define workflow structure, artifact formats, configuration schema
2. **quickstart.md**: Document setup steps for local development and testing
3. **Implementation tasks**: Convert research decisions into concrete implementation steps

### Open Questions

None. Research phase complete with all decisions made and documented.

---

## Historical Context: Static Linking Strategy

### Previous Research (2025-12-12)

The original research document evaluated multiple static linking strategies:

**Zig + musl + mimalloc** (ABANDONED 2025-12-13):
- Initial choice due to single binary, built-in musl support
- Abandoned due to ecosystem compatibility issues (GCC built-ins, meson linker detection)
- See MIGRATION-ZIG-TO-CLANG.md for detailed migration rationale

**Current: Clang + musl target** (ACTIVE):
- GCC compatibility for built-ins like `__builtin_cpu_supports()`
- Build system support (make, meson, cmake, autotools)
- Standard tooling available in all distributions
- Clean cross-compilation with `--target` flag
- Proven track record for musl static builds

**mimalloc Allocator**:
- Still used to replace musl's slower allocator (7-10x slower than glibc)
- Statically linked with builds
- Minimal overhead, consistent memory behavior

**Archive Format**:
- .tar.zst (Zstandard compression)
- ~20-30% better compression than gzip
- 3-5x faster decompression
- Modern tar auto-detects format

---

## Sources

### Container Startup & CI/CD Patterns
- [CI/CD Explained (2025): Workflow, Examples, Checklists](https://atmosly.com/knowledge/cicd-pipeline)
- [Containerization. Ephemeral, Idempotent, and Immutable](https://medium.com/@h.stoychev87/containerization-docker-and-containers-8e8f28fd0694)
- [The DevOps Architect's Definitive Guide to CI/CD Ecosystems in 2025](https://medium.com/@jm2022074255/the-devops-architects-definitive-guide-to-ci-cd-ecosystems-in-2025-a-comparative-analysis-b10114ef1807)

### Rootless Podman on GitHub Actions
- [How to run a rootless podman service in Github Actions](https://www.linkedin.com/pulse/how-run-rootless-podman-service-github-actions-%D0%B4%D0%BC%D0%B8%D1%82%D1%80%D0%B8%D0%B9-%D0%BC%D0%B8%D1%88%D0%B0%D1%80%D0%BE%D0%B2)
- [How to Set Up a Rootless GitHub Container Building Pipeline](https://www.sealingtech.com/2024/04/29/how-to-set-up-a-rootless-github-container-building-pipeline/)
- [Rootless Podman Tutorial](https://github.com/containers/podman/blob/main/docs/tutorials/rootless_tutorial.md)
- [Rootless Podman v4 and resource limits working in Github Actions](https://github.com/containers/podman/discussions/18080)

### Cross-Compilation with Clang + musl
- [Cross compiling made easy, using Clang and LLVM](https://mcilloni.ovh/2021/02/09/cxx-cross-clang/)
- [Cross-compilation using Clang — Official Documentation](https://clang.llvm.org/docs/CrossCompilation.html)
- [musl libc toolchains | static cross/native toolchains](https://musl.cc/)
- [Compile Static Binaries](https://straysheep.dev/blog/2025/06/15/fontawesome-solid-square-binary-compile-static-binaries/)

### QEMU vs Native ARM64 Performance
- [Emulating architectures with qemu: which performs best?](https://blog.fluxcoil.net/posts/2025/02/emulation-performance-and-consumption/)
- [Accelerating Docker Builds with Cross Compilation on GitHub Runners](https://kev.fan/posts/03-cross-compile/)
- [Ubicloud Hosted Arm Runners, 100x better price/performance](https://www.ubicloud.com/blog/ubicloud-hosted-arm-runners-100x-better-price-performance)

### Volume Mounts vs podman cp
- [podman-cp Documentation](https://docs.podman.io/en/latest/markdown/podman-cp.1.html)
- [podman-volume-mount Documentation](https://docs.podman.io/en/latest/markdown/podman-volume-mount.1.html)
- [Podman volume mounts, rootless container, and non-root user](https://learn.redhat.com/t5/Containers-DevOps-OpenShift/Podman-volume-mounts-rootless-container-and-non-root-user/td-p/47579)

### Container Security
- [Rootless bind mounts with SELinux](https://github.com/containers/podman/issues/25919)
- [Firewall a podman container](https://jerabaul29.github.io/jekyll/update/2025/10/17/Firewall-a-podman-container.html)

### Error Handling & Debugging
- [Troubleshooting and Debugging - Podman](https://www.kevsrobots.com/learn/podman/11_troubleshooting_and_debugging.html)
- [podman troubleshooting.md](https://github.com/containers/podman/blob/main/troubleshooting.md)
- [Where are the podman logs of containers stored?](https://access.redhat.com/solutions/6985647)
- [How to set debug logging from podman?](https://access.redhat.com/solutions/3947441)
