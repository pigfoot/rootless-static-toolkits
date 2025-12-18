# Feature Specification: Dynamic glibc Build Variant for All Tools

**Feature Branch**: `002-glibc-build`
**Created**: 2025-12-16
**Updated**: 2025-12-18
**Status**: Complete
**Input**: User description: "Add dynamic glibc build variant alongside musl static build for podman, buildah, and skopeo, with README documentation to help users choose. Switch container to ubuntu:latest, use latest stable build tools, minimize setup-build-env.sh packages."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Build glibc-linked Binaries for Modern Linux Systems (Priority: P1)

As a developer deploying to Ubuntu 22.04+/Debian 12+ environments, I want to build glibc-linked versions of podman, buildah, and skopeo so that I get optimal system integration and slightly smaller binaries while still benefiting from mimalloc memory allocation.

**Why this priority**: This is the core feature request. Users on modern Linux systems with glibc 2.34+ can choose this variant for better system integration while maintaining the same functionality across all three container tools.

**Independent Test**: Can be fully tested by running the glibc build target for each tool (podman, buildah, skopeo) and verifying the output binaries link dynamically to glibc while all other dependencies (mimalloc, libstdc++, pthread) remain statically linked.

**Acceptance Scenarios**:

1. **Given** the build environment is set up, **When** I run the glibc build target for podman/buildah/skopeo, **Then** each output binary shows only glibc as a dynamic dependency via `ldd`.
2. **Given** glibc-built binaries, **When** I run podman/buildah/skopeo on Ubuntu 22.04+, **Then** all tools execute successfully with all features working.
3. **Given** glibc-built binaries, **When** I check for mimalloc integration, **Then** it is statically linked via --whole-archive in all three tools.

---

### User Story 2 - Choose Between Build Variants (Priority: P1)

As a user downloading pre-built binaries, I want clear documentation explaining the differences between musl-static and glibc-dynamic variants so that I can choose the right one for my deployment environment.

**Why this priority**: Users need to understand which variant to use. Without clear guidance, they may choose incorrectly and encounter compatibility issues.

**Independent Test**: Can be tested by reviewing the README documentation and confirming it provides a clear decision tree for choosing between variants.

**Acceptance Scenarios**:

1. **Given** I read the README, **When** I look for variant information, **Then** I find a comparison table showing musl vs glibc trade-offs.
2. **Given** I read the README, **When** I check compatibility requirements, **Then** I see specific OS version requirements for glibc variant (Ubuntu 22.04+, Debian 12+, RHEL 9+).
3. **Given** I read the README, **When** I need portability guidance, **Then** I understand musl-static works everywhere while glibc-dynamic requires compatible glibc.

---

### User Story 3 - Use Latest Stable Build Tools (Priority: P2)

As a maintainer, I want the build environment to use the latest stable versions of meson, cmake, and other build tools so that builds benefit from latest fixes and optimizations without manual version management.

**Why this priority**: Using latest stable tools reduces maintenance burden and ensures builds use current best practices. The project already uses latest Go/Rust/Clang.

**Independent Test**: Can be tested by verifying the build environment installs tools via uv or direct download rather than distro packages.

**Acceptance Scenarios**:

1. **Given** the container build environment, **When** I check meson version, **Then** it is the latest stable release (not distro-packaged older version).
2. **Given** the container build environment, **When** I check cmake version, **Then** it is a recent stable release.
3. **Given** a new tool version is released, **When** I rebuild the container, **Then** it picks up the latest stable version automatically.

---

### User Story 4 - Minimal Build Environment Packages (Priority: P2)

As a maintainer, I want setup-build-env.sh to install only essential packages so that the build environment is leaner, faster to set up, and has fewer potential conflicts.

**Why this priority**: With latest toolchains (Go, Rust, Clang) already being installed separately, many distro packages become redundant. Reducing packages improves build speed and reduces maintenance.

**Independent Test**: Can be tested by comparing the package list before/after and verifying all builds still succeed.

**Acceptance Scenarios**:

1. **Given** the current setup-build-env.sh, **When** I review installed packages, **Then** redundant packages (those superseded by latest toolchains) are removed.
2. **Given** the minimal package set, **When** I run both musl and glibc builds, **Then** all builds complete successfully.
3. **Given** the minimal package set, **When** I compare with the previous version, **Then** the package count is noticeably reduced.

---

### User Story 5 - Unified Ubuntu Container Base (Priority: P2)

As a maintainer, I want both build variants to use ubuntu:latest as the container base so that we have a consistent build environment and access to both glibc and musl-tools.

**Why this priority**: Using a single container base simplifies maintenance. Ubuntu:latest provides glibc 2.39 for glibc builds and musl-tools package for musl builds.

**Independent Test**: Can be tested by verifying the build container uses ubuntu:latest and successfully produces both musl-static and glibc-dynamic binaries.

**Acceptance Scenarios**:

1. **Given** either build configuration, **When** I check the container base image, **Then** it uses ubuntu:latest.
2. **Given** ubuntu:latest container, **When** I run musl builds, **Then** it uses musl-tools to produce static binaries.
3. **Given** ubuntu:latest container, **When** I run glibc builds, **Then** the output links against glibc 2.34+ symbols.

---

### Edge Cases

- What happens when the target system has glibc older than 2.34? The glibc variant will fail to run; users should use musl variant.
- How does the system handle when uv or direct download fails? Build should fail with clear error message indicating the tool download failure.
- What happens if both variants are built in the same CI run? Both should produce distinct outputs without interference.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Build system MUST support a new glibc-dynamic build target alongside the existing musl-static target for podman, buildah, and skopeo.
- **FR-002**: Glibc-built binaries MUST dynamically link only to glibc system libraries (libc.so.6, libm.so.6, libresolv.so.2, ld-linux-x86-64.so.2, linux-vdso.so.1). Rust binaries MAY additionally link libgcc_s.so.1 (GCC unwinding support, unavoidable system library).
- **FR-003**: Glibc-built binaries MUST statically link mimalloc via --whole-archive.
- **FR-004**: Glibc-built binaries MUST statically link libstdc++ and libgcc.
- **FR-005**: README MUST include a comparison section explaining musl-static vs glibc-dynamic trade-offs.
- **FR-006**: README MUST specify minimum OS versions for glibc variant (glibc 2.34+ requirement).
- **FR-007**: README MUST include a decision tree or table to help users choose the right variant.
- **FR-008**: Build environment MUST use ubuntu:latest as base container for both build variants (musl via musl-tools package).
- **FR-009**: Build environment MUST install Python-based tools (meson, ninja, etc.) via `uv`, and non-Python tools (cmake) via direct download from official releases.
- **FR-010**: setup-build-env.sh MUST minimize installed packages by removing those superseded by latest toolchains.
- **FR-011**: GitHub Actions workflows for podman, buildah, and skopeo MUST produce both musl-static and glibc-dynamic artifacts.
- **FR-012**: Both build variants MUST integrate mimalloc memory allocator identically across all three tools.
- **FR-013**: Release assets MUST follow naming convention: `{tool}-{version}-linux-{arch}-{libc}[-{package}].tar.zst` for all three tools (e.g., `podman-v5.7.1-linux-amd64-static.tar.zst`, `buildah-v1.35.0-linux-amd64-glibc.tar.zst`, `skopeo-v1.15.0-linux-arm64-static.tar.zst`).

### Key Entities

- **Build Variant**: Configuration that determines linking strategy (musl-static or glibc-dynamic), affecting portability and system integration.
- **Build Environment**: Container-based environment with required compilers, tools, and libraries for producing binaries.
- **Build Artifact**: Output binary with specific linking characteristics (static/dynamic) and memory allocator integration.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Both build variants produce working binaries that pass functional tests.
- **SC-002**: Glibc variant binaries show only glibc as dynamic dependency when inspected with ldd.
- **SC-003**: Binary sizes for both variants remain within 10% of each other (based on research showing 43MB for both).
- **SC-004**: README documentation enables users to choose the correct variant without needing external guidance.
- **SC-005**: Build environment setup time is reduced or maintained after package minimization.
- **SC-006**: CI/CD pipeline successfully produces both variants in a single workflow run.

## Clarifications

### Session 2025-12-16

- Q: Build artifacts naming strategy? → A: Directory-based: `static/podman` (musl) and `glibc/podman` (glibc-dynamic)
- Q: Container base image for musl builds? → A: Both variants use `ubuntu:latest` (musl via musl-tools package)
- Q: Build tool installation method? → A: Use `uv` for all Python-based tools (meson, ninja, etc.), direct download for non-Python tools (cmake)
- Q: Release asset naming convention? → A: `{tool}-{version}-linux-{arch}-{libc}[-{package}].tar.zst` (e.g., `podman-v5.7.1-linux-amd64-static.tar.zst`, `podman-v5.7.1-linux-amd64-glibc-full.tar.zst`)
- Q: Compiler for glibc variant? → A: Use Clang for both variants (unified toolchain, no gcc needed)

## Assumptions

- Build artifacts use directory-based naming: `static/` for musl-static and `glibc/` for glibc-dynamic variants.
- Release assets use naming convention: `{tool}-{version}-linux-{arch}-{libc}[-{package}].tar.zst`.
- Both build variants use `ubuntu:latest` as container base; musl builds use the musl-tools package.
- Ubuntu:latest (currently 24.04) provides glibc 2.39, which is compatible with the glibc 2.34+ requirement.
- The existing musl-static build infrastructure remains unchanged; glibc-dynamic is additive.
- Users downloading binaries understand basic Linux distribution concepts (glibc vs musl).
- The --network=host workaround for pasta IPv6 issues applies to both build variants.
- Python-based build tools (meson, ninja, etc.) are installed via `uv`; non-Python tools (cmake) via direct download from official releases.
- Both build variants use Clang as the compiler (unified toolchain, gcc not required).
