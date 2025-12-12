# Data Model: Static Container Tools Build System

**Date**: 2025-12-12
**Branch**: `001-static-build`

## Overview

This project is a build infrastructure system, not a traditional application. The "data model" describes the entities and relationships in the build/release pipeline.

---

## Entities

### Tool

Represents one of the container tools being built.

| Field | Type | Description |
|-------|------|-------------|
| name | string | Tool identifier: `podman`, `buildah`, `skopeo` |
| upstream_repo | string | GitHub repo path (e.g., `containers/podman`) |
| has_variants | boolean | Whether tool has full/minimal variants |
| runtime_components | string[] | List of additional binaries to bundle (podman only) |

**Instances:**

```yaml
podman:
  name: podman
  upstream_repo: containers/podman
  has_variants: true
  runtime_components:
    - crun
    - conmon
    - fuse-overlayfs
    - netavark
    - aardvark-dns
    - pasta
    - catatonit

buildah:
  name: buildah
  upstream_repo: containers/buildah
  has_variants: false
  runtime_components: []

skopeo:
  name: skopeo
  upstream_repo: containers/skopeo
  has_variants: false
  runtime_components: []
```

---

### Version

Represents a specific version of a tool.

| Field | Type | Description |
|-------|------|-------------|
| tool | Tool | Reference to the tool |
| version | string | Semantic version (e.g., `5.3.1`) |
| upstream_tag | string | Git tag in upstream repo (e.g., `v5.3.1`) |
| is_prerelease | boolean | Whether this is alpha/beta/rc |

**Validation Rules:**
- Skip if `is_prerelease = true`
- Version must match semver pattern

---

### Release

Represents a published release in this repository.

| Field | Type | Description |
|-------|------|-------------|
| tool | Tool | Reference to the tool |
| version | Version | Reference to the version |
| tag | string | Git tag (e.g., `podman-v5.3.1`) |
| created_at | datetime | Release timestamp |
| artifacts | Artifact[] | List of release artifacts |

**State Transitions:**

```
[Not Exists] --> [Building] --> [Published]
                     |
                     v
                 [Failed]
```

---

### Artifact

Represents a single downloadable file in a release.

| Field | Type | Description |
|-------|------|-------------|
| release | Release | Parent release |
| filename | string | File name (e.g., `podman-full-linux-amd64.tar.zst`) |
| architecture | string | `amd64` or `arm64` |
| variant | string | `full`, `minimal`, or `null` |
| checksum_sha256 | string | SHA256 hash |
| signature | string | Cosign signature reference |
| size_bytes | integer | File size |

**Naming Convention:**

```
{tool}[-{variant}]-linux-{arch}.tar.zst

Examples:
- podman-full-linux-amd64.tar.zst
- podman-minimal-linux-arm64.tar.zst
- buildah-linux-amd64.tar.zst
- skopeo-linux-arm64.tar.zst
```

---

### BuildJob

Represents a single build execution.

| Field | Type | Description |
|-------|------|-------------|
| id | string | GitHub Actions run ID |
| tool | Tool | Tool being built |
| version | Version | Version being built |
| architecture | string | Target architecture |
| variant | string | Variant (if applicable) |
| status | enum | `pending`, `running`, `success`, `failed` |
| started_at | datetime | Build start time |
| completed_at | datetime | Build completion time |
| logs_url | string | Link to GitHub Actions logs |

---

### RuntimeComponent

Represents an additional binary bundled with podman-full.

| Field | Type | Description |
|-------|------|-------------|
| name | string | Component name |
| source_repo | string | GitHub repo path |
| language | string | `go`, `rust`, `c` |
| build_command | string | Command to build from source |

**Instances:**

| Component | Repo | Language |
|-----------|------|----------|
| crun | containers/crun | C |
| conmon | containers/conmon | C |
| fuse-overlayfs | containers/fuse-overlayfs | C |
| netavark | containers/netavark | Rust |
| aardvark-dns | containers/aardvark-dns | Rust |
| pasta | passt/passt | C |
| catatonit | openSUSE/catatonit | C |

---

## Relationships

```
Tool 1──* Version
Tool 1──* RuntimeComponent (podman only)
Version 1──1 Release (when published)
Release 1──* Artifact
BuildJob *──1 Tool
BuildJob *──1 Version
```

---

## Configuration Files

### etc/containers/policy.json

Default image signature policy:

```json
{
  "default": [
    {
      "type": "insecureAcceptAnything"
    }
  ]
}
```

### etc/containers/registries.conf

Default registry configuration:

```toml
unqualified-search-registries = ["docker.io"]

[[registry]]
location = "docker.io"
```

---

## Version Tracking

Version state is tracked via GitHub Releases API:

```bash
# Check if version is already released
gh release view "{tool}-v{version}" --repo $REPO 2>/dev/null
# Exit code 0 = exists, non-zero = not released
```

No database or state file is required.
