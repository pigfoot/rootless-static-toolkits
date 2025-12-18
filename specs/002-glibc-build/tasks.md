# Tasks: Dynamic glibc Build Variant

**Input**: Design documents from `/specs/002-glibc-build/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, quickstart.md

**Tests**: Not explicitly requested - implementation verification tasks included instead.

**Organization**: Tasks grouped by user story for independent implementation and testing.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions

- **Scripts**: `scripts/`
- **Container scripts**: `scripts/container/`
- **GitHub Actions**: `.github/workflows/`
- **Documentation**: `README.md`

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Foundational changes that enable all user stories

- [X] T001 [P] Add LIBC parameter support to Makefile (static/glibc)

---

## Phase 2: User Story 5 - Unified Ubuntu Container Base (Priority: P2)

**Goal**: Both build variants use ubuntu:latest as container base

**Independent Test**: Verify container uses ubuntu:latest and can produce both variants

**Note**: This is implemented first as it's foundational for other stories

### Implementation for User Story 5

- [X] T002 [US5] Update container image reference in Makefile to use ubuntu:latest
- [X] T003 [US5] Verify musl-tools package available in ubuntu:latest

**Checkpoint**: Container base unified - ready for build environment updates

---

## Phase 3: User Stories 3 & 4 - Build Environment (Priority: P2)

**Goal**: Minimize packages and use latest stable build tools via uv

**Independent Test**: Verify meson/cmake are latest stable versions, not distro packages

### Implementation for User Stories 3 & 4

- [X] T004 [US3] [US4] Install uv in scripts/container/setup-build-env.sh
- [X] T005 [P] [US3] [US4] Replace apt meson/ninja with uvx meson/ninja in scripts/container/setup-build-env.sh
- [X] T006 [P] [US3] [US4] Replace apt cmake with direct download from Kitware in scripts/container/setup-build-env.sh
- [X] T007 [US4] Remove gcc, g++, build-essential from apt install (using Clang) in scripts/container/setup-build-env.sh
- [X] T008 [US4] Remove redundant packages from apt install in scripts/container/setup-build-env.sh
- [X] T009 [US3] [US4] Add version verification output for installed tools in scripts/container/setup-build-env.sh

**Checkpoint**: Build environment minimized with latest tools

---

## Phase 4: User Story 1 - Build glibc Variant (Priority: P1) 🎯 MVP

**Goal**: Add glibc build mode to build-tool.sh producing glibc-dynamic binaries (only glibc dynamically linked)

**Independent Test**: Run glibc build target, verify ldd shows only glibc dependencies

### Implementation for User Story 1

- [X] T010 [US1] Add LIBC parameter parsing (static/glibc) to scripts/build-tool.sh
- [X] T011 [US1] Add glibc compiler configuration (CC=clang, no musl target) to scripts/build-tool.sh
- [X] T012 [US1] Add glibc EXTLDFLAGS (-static-libgcc -static-libstdc++, -Wl,-Bstatic/-Bdynamic) to scripts/build-tool.sh
- [X] T013 [US1] Add glibc mimalloc build configuration to scripts/build-mimalloc.sh
- [X] T014 [US1] Update output directory structure (static/ vs glibc/) in scripts/build-tool.sh
- [X] T015 [US1] Add ldd verification step for glibc variant in scripts/build-tool.sh
- [X] T016 [P] [US1] Update scripts/package.sh for glibc variant naming convention
- [X] T017 [P] [US1] Update scripts/test-static.sh to support glibc variant testing
- [X] T018 [US1] Add glibc variant to GitHub Actions matrix in .github/workflows/build-podman.yml
- [X] T019 [US1] Update release asset naming in .github/workflows/build-podman.yml
- [X] T020a [P] [US1] Add glibc variant to GitHub Actions matrix in .github/workflows/build-buildah.yml
- [X] T020b [P] [US1] Add glibc variant to GitHub Actions matrix in .github/workflows/build-skopeo.yml

**Checkpoint**: Glibc build variant functional - can produce and verify glibc binaries

---

## Phase 5: User Story 2 - Documentation (Priority: P1)

**Goal**: README documentation explaining variant differences and helping users choose

**Independent Test**: Review README and confirm decision tree is clear

### Implementation for User Story 2

- [X] T021 [US2] Add "Build Variants" section header to README.md
- [X] T022 [US2] Add comparison table (static vs glibc: portability, size, NSS support, glibc version requirement) to README.md
- [X] T023 [US2] Add detailed explanation of static vs glibc differences (what is statically/dynamically linked) to README.md
- [X] T024 [US2] Add OS compatibility matrix to README.md
- [X] T025 [US2] Add decision tree for choosing variant to README.md
- [X] T026 [US2] Add use case recommendations table to README.md
- [X] T027 [US2] Update download/usage instructions for both variants in README.md

**Checkpoint**: Users can choose correct variant using README guidance

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Final verification and cleanup

- [X] T028 Verify static variant still works after changes (regression test)
- [X] T029 Verify glibc variant works on Ubuntu 22.04+ container
- [X] T030 [P] Update CONTRIBUTING.md with glibc build instructions
- [X] T031 Run full build for both variants using podman with ubuntu:latest locally
- [X] T032 Verify packaging works in local ubuntu container before commit
- [X] T033 Verify release asset naming follows convention

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1 (Setup)**: No dependencies - start immediately
- **Phase 2 (US5)**: Depends on Phase 1 - container base update
- **Phase 3 (US3/US4)**: Depends on Phase 2 - build environment needs container ready
- **Phase 4 (US1)**: Depends on Phase 3 - glibc build needs new environment
- **Phase 5 (US2)**: Can start after Phase 1, but best after Phase 4 to document actual behavior
- **Phase 6 (Polish)**: Depends on all previous phases

### User Story Dependencies

```
Phase 1 (Setup)
    │
    ▼
Phase 2 (US5: Container Base)
    │
    ▼
Phase 3 (US3/US4: Build Environment)
    │
    ▼
Phase 4 (US1: Glibc Build) ←── MVP Milestone
    │
    ▼
Phase 5 (US2: Documentation)
    │
    ▼
Phase 6 (Polish)
```

### Within Each Phase

- Tasks marked [P] can run in parallel
- Sequential tasks depend on previous task in same phase
- Complete phase before moving to next

### Parallel Opportunities

**Phase 3**:
```
T005 (uvx meson/ninja) ─┬─ parallel
T006 (cmake download)  ─┘
```

**Phase 4**:
```
T016 (package.sh) ────┬─ parallel
T017 (test-static.sh) ┤
T020a (build-buildah) ┤
T020b (build-skopeo)  ┘
```

---

## Implementation Strategy

### MVP First (Phases 1-4)

1. Complete Phase 1: Setup (Makefile updates)
2. Complete Phase 2: US5 Container Base
3. Complete Phase 3: US3/US4 Build Environment
4. Complete Phase 4: US1 Glibc Build
5. **STOP and VALIDATE**: Build both variants, verify with ldd
6. Deploy if ready (glibc builds work)

### Full Feature (Add Phase 5-6)

7. Complete Phase 5: US2 Documentation
8. Complete Phase 6: Polish and verification
9. All user stories complete

### Task Summary

| Phase | User Story | Tasks | Description |
|-------|------------|-------|-------------|
| 1 | Setup | T001 | Makefile LIBC parameter |
| 2 | US5 | T002-T003 | Container base |
| 3 | US3/US4 | T004-T009 | Build environment |
| 4 | US1 | T010-T020b | Glibc build (MVP) - includes all three tools |
| 5 | US2 | T021-T027 | Documentation (includes static vs glibc explanation) |
| 6 | Polish | T028-T033 | Verification (includes local podman test) |

**Total Tasks**: 34
**MVP Tasks**: 21 (Phases 1-4)

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps task to specific user story
- Both variants use unified Clang toolchain
- Constitution v1.4.0 explicitly supports both libc variants
- Verify with ldd after glibc build
- Commit after each task or logical group
