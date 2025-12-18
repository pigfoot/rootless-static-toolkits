# static-rootless-container-tools Development Guidelines

Auto-generated from all feature plans. Last updated: 2025-12-12

## Active Technologies
- Bash scripts, YAML (GitHub Actions), Containerized builds (podman + Ubuntu:rolling) (001-static-build)
- N/A (version tracking via GitHub Releases) (001-static-build)
- Bash scripts, Go 1.21+ (for built tools), Rust stable (for netavark/aardvark-dns) + Clang/LLVM (both variants), mimalloc, musl-tools (002-glibc-build)
- N/A (build scripts produce binaries) (002-glibc-build)

- Bash scripts, YAML (GitHub Actions), Dockerfile (optional fallback) + Go toolchain, Zig, cosign, gh CLI (001-static-build)

## Project Structure

```text
src/
tests/
```

## Commands

# Add commands for Bash scripts, YAML (GitHub Actions), Dockerfile (optional fallback)

## Code Style

Bash scripts, YAML (GitHub Actions), Dockerfile (optional fallback): Follow standard conventions

## Recent Changes
- 002-glibc-build: Added Bash scripts, Go 1.21+ (for built tools), Rust stable (for netavark/aardvark-dns) + Clang/LLVM (both variants), mimalloc, musl-tools
- 001-static-build: Added Bash scripts, YAML (GitHub Actions), Containerized builds (podman + Ubuntu:rolling)

- 001-static-build: Added Bash scripts, YAML (GitHub Actions), Dockerfile (optional fallback) + Go toolchain, Zig, cosign, gh CLI

<!-- MANUAL ADDITIONS START -->
<!-- MANUAL ADDITIONS END -->
