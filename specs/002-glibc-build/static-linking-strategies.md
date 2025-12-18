# Static Linking Strategies: musl vs glibc-dynamic

Reference guide for building statically linked binaries with different libc strategies.
Covers C/C++, Go, and Rust projects.

---

## Strategy Comparison

| Aspect | Full Static (musl) | Glibc Dynamic |
|--------|-------------------|---------------|
| **Libc** | musl (statically linked) | glibc (dynamically linked) |
| **Other libs** | All static | All static (C/C++/Go)<br>All static except libgcc_s (Rust) |
| **Binary portability** | Maximum (no deps) | Good (only glibc + libgcc_s) |
| **DNS resolution** | musl resolver | glibc NSS (libresolv.so.2) |
| **Size** | Larger (includes libc) | Smaller (shares glibc) |
| **Use case** | True portability, containers | System integration, avoid musl issues |
| **Rust libgcc_s** | Not needed (musl) | Required (unwinding support) |

### Expected ldd Output

**Full Static (musl)**:
```bash
$ ldd ./binary
not a dynamic executable
```

**Glibc Dynamic - C/C++/Go binaries** (only these allowed):
```bash
$ ldd ./binary
linux-vdso.so.1 (kernel-provided)
libc.so.6 => /lib/x86_64-linux-gnu/libc.so.6
libm.so.6 => /lib/x86_64-linux-gnu/libm.so.6         # math (optional)
libresolv.so.2 => /lib/x86_64-linux-gnu/libresolv.so.2  # DNS (optional)
ld-linux-x86-64.so.2  # dynamic linker
```

**Glibc Dynamic - Rust binaries** (these are allowed):
```bash
$ ldd ./binary
linux-vdso.so.1 (kernel-provided)
libgcc_s.so.1 => /lib/x86_64-linux-gnu/libgcc_s.so.1  # GCC runtime (required)
libc.so.6 => /lib/x86_64-linux-gnu/libc.so.6
libm.so.6 => /lib/x86_64-linux-gnu/libm.so.6
ld-linux-x86-64.so.2  # dynamic linker
```

**WRONG** (should NOT appear in any glibc-dynamic):
```
❌ libcap.so.2        # Should be statically linked
❌ libglib-2.0.so.0   # Should be statically linked
❌ libstdc++.so.6     # Should be statically linked
❌ libunwind.so       # Should be statically linked
```

**Note**: `libgcc_s.so.1` is:
- ❌ NOT allowed for C/C++/Go binaries (use `-static-libgcc`)
- ✅ **Unavoidable** for Rust binaries (system dependency, acceptable)

---

## Compiler Choice: GCC vs Clang

Both GCC and Clang work for static linking, but have important differences:

### Key Differences

| Feature | GCC | Clang |
|---------|-----|-------|
| **musl support** | Needs `musl-gcc` wrapper or musl toolchain | Can use `-target` or manual paths |
| **Cross-compile flag** | Requires separate toolchain (e.g., `x86_64-linux-musl-gcc`) | `-target x86_64-linux-musl` |
| **Manual musl paths** | ❌ Doesn't work reliably | ✅ Works (`-I/usr/include/x86_64-linux-musl`) |
| **-Wl,-Bstatic** | ✅ Works (passed to ld) | ✅ Works (passed to ld/lld) |
| **-static-libgcc** | ✅ Native support | ✅ Works (uses GCC runtime) |
| **Default linker** | GNU ld (via collect2) | GNU ld (can use lld with `-fuse-ld=lld`) |
| **lld support** | ❌ No (must use ld) | ✅ Optional (`-fuse-ld=lld`) |

### musl Linking Methods

**GCC approach**:
```bash
# Must use musl-gcc wrapper (installed with musl-tools)
musl-gcc -static -o binary main.c

# Manual paths don't work reliably with GCC
gcc -I/usr/include/x86_64-linux-musl -L/usr/lib/x86_64-linux-musl -static main.c
# ❌ Often fails with obscure linker errors
```

**Clang approach** (recommended):
```bash
# Method 1: Manual paths (what we use)
clang \
  -I/usr/include/x86_64-linux-musl \
  -L/usr/lib/x86_64-linux-musl \
  -static -o binary main.c
# ✅ Works reliably

# Method 2: Use -target flag (requires musl sysroot)
clang -target x86_64-linux-musl -static -o binary main.c
# ✅ Works if musl is properly installed
```

**Why clang?**
- More flexible for cross-compilation
- Can specify musl paths without wrapper
- Better multi-target support
- Used by mgoltzsche/podman-static (proven approach)

### Linker Flag Compatibility

Good news: `-Wl,-Bstatic` and `-Wl,-Bdynamic` work identically:

```bash
# Both compilers produce identical results
gcc -Wl,-Bstatic -lcap -Wl,-Bdynamic -static-libgcc main.o
clang -Wl,-Bstatic -lcap -Wl,-Bdynamic -static-libgcc main.o
```

These flags are passed to the linker (`ld`), so behavior is the same.

**About linkers**:
- **GCC**: Always uses GNU ld (ld.bfd) via `collect2` wrapper
- **Clang**: Uses GNU ld by default, can switch to lld with `-fuse-ld=lld`
- **lld compatibility**: lld supports `-Wl,-Bstatic/-Bdynamic` (compatible with GNU ld)

**When to use lld**:
```bash
# Default (GNU ld)
clang -Wl,-Bstatic -lcap -Wl,-Bdynamic main.o

# Use lld (faster linking, required for some cross-compilation scenarios)
clang -fuse-ld=lld -Wl,-Bstatic -lcap -Wl,-Bdynamic main.o
```

**Note**: lld is not installed by default on most systems.
```bash
# Install lld (Debian/Ubuntu)
apt-get install lld

# lld is now available as ld.lld
```

For static linking strategies in this guide, **either linker works** - no changes needed.

### Recommendation

**For static builds**: Use Clang
- More flexible musl support
- Simpler cross-compilation
- No need for wrapper scripts

**For existing projects**: Follow project convention
- If Makefile uses `$(CC)`, either works
- Set `CC=clang` or `CC=gcc` as needed

**For glibc dynamic builds**: Either works fine
- `-Wl,-Bstatic/-Bdynamic` identical behavior
- `-static-libgcc` identical behavior

---

## C/C++ Projects

### Full Static (musl)

**Architecture-specific musl paths**:
- x86_64: `x86_64-linux-musl`
- aarch64: `aarch64-linux-musl`

**Clang Setup** (recommended):
```bash
export CC="clang"
export CXX="clang++"

# Point to musl instead of glibc
export CFLAGS="-I/usr/include/x86_64-linux-musl -w"
export CXXFLAGS="$CFLAGS"
export LDFLAGS="-L/usr/lib/x86_64-linux-musl -static"
```

**Link command**:
```bash
clang -static -o binary main.o -lfoo -lbar
```

**GCC Setup** (alternative):
```bash
# Use musl-gcc wrapper
export CC="musl-gcc"
export CXX="musl-g++"
export CFLAGS="-w"
export LDFLAGS="-static"
```

**Link command**:
```bash
musl-gcc -static -o binary main.o -lfoo -lbar
```

**Critical**: Must use `-static` flag AND musl (via paths or wrapper) to avoid glibc NSS issues (SIGFPE).

### Glibc Dynamic

**Compiler Setup** (clang or gcc - both work):
```bash
export CC="clang"  # or "gcc"
export CXX="clang++"  # or "g++"
export CFLAGS="-w"
export CXXFLAGS="$CFLAGS"
export LDFLAGS=""  # No -static
```

**Link command pattern** (same for both compilers):
```bash
${CC} \
  -static-libgcc \
  -static-libstdc++ \
  -Wl,-Bstatic \
    -lfoo -lbar -lcap \  # All non-glibc libs here
  -Wl,-Bdynamic \
  -o binary main.o
```
(Replace `${CC}` with `clang` or `gcc`)

**Key principles**:
1. `-static-libgcc -static-libstdc++`: Static GCC/C++ runtime
2. `-Wl,-Bstatic ... -Wl,-Bdynamic`: Force static linking of libraries between flags
3. **Order matters**: `-Wl,-Bstatic` MUST come BEFORE library flags
4. glibc (libc, libm, libresolv) defaults to dynamic - no special handling needed

**Common mistake** (both compilers):
```bash
# WRONG: -lcap comes after -Wl,-Bdynamic
${CC} -Wl,-Bstatic -Wl,-Bdynamic main.o -lcap
→ libcap.so.2 dynamically linked ❌

# CORRECT: -lcap between -Bstatic and -Bdynamic
${CC} -Wl,-Bstatic -lcap -Wl,-Bdynamic main.o
→ libcap.a statically linked ✅
```

**Makefile example** (passing libs to make):
```makefile
# WRONG: Libraries added by configure come after -Bdynamic
make LDFLAGS="-Wl,-Bstatic ... -Wl,-Bdynamic"
# configure adds: [object files] -lcap

# CORRECT: Wrap libraries explicitly
LIBS="-Wl,-Bstatic -lcap -lseccomp -Wl,-Bdynamic"
make LDFLAGS="..." LIBS="$LIBS"
```

### Using pkg-config/pkgconf

**Background**: pkg-config (or its replacement pkgconf) helps find compiler/linker flags for libraries.
Many C projects use it in Makefiles to auto-detect dependencies.

**Key limitation**: `pkg-config --static` returns static library dependencies but **does NOT** make the linker use `.a` files.
You still need `-Wl,-Bstatic` to force static linking.

#### Full Static (musl)

**Approach 1**: Use pkg-config normally with `-static` linker flag
```bash
# pkg-config finds flags, -static forces static linking
CFLAGS="$(pkg-config --cflags glib-2.0)"
LIBS="$(pkg-config --libs glib-2.0)"
clang $CFLAGS -static -o binary main.o $LIBS
```

**Approach 2**: Get static dependencies explicitly
```bash
# --static returns all transitive dependencies
LIBS="$(pkg-config --static --libs glib-2.0)"
# -static flag still required to use .a files
clang -static -o binary main.o $LIBS
```

**Both work** because `-static` global flag overrides all library linking.

#### Glibc Dynamic

**Approach**: Manually wrap pkg-config libs with `-Wl,-Bstatic`
```bash
# Get compile flags (always safe)
CFLAGS="$(pkg-config --cflags glib-2.0)"

# Get STATIC dependency list (--static flag)
GLIB_LIBS="$(pkg-config --static --libs glib-2.0)"

# Wrap with -Bstatic/-Bdynamic
clang $CFLAGS \
  -static-libgcc \
  -Wl,-Bstatic $GLIB_LIBS -Wl,-Bdynamic \
  -o binary main.o
```

**Why `--static` flag needed**:
```bash
$ pkg-config --libs glib-2.0
-lglib-2.0

$ pkg-config --static --libs glib-2.0
-lglib-2.0 -lpcre2-8 -pthread
#         ^^^^^^^^^^^^^^^^^ transitive dependencies
```
Without `--static`, you'd miss transitive deps → undefined symbols when static linking.

**Example: conmon with glib-2.0**
```bash
# Get all dependencies
CFLAGS="$(pkg-config --cflags glib-2.0)"
GLIB_LIBS="$(pkg-config --static --libs glib-2.0)"

# Build with static glib, dynamic glibc
clang $CFLAGS \
  -static-libgcc -static-libstdc++ \
  -Wl,-Bstatic $GLIB_LIBS -Wl,-Bdynamic \
  -o conmon src/*.o
```

Result:
```bash
$ ldd conmon
libc.so.6 => /lib/x86_64-linux-gnu/libc.so.6  ✅
# No libglib-2.0.so.0  ✅
```

#### Disabling pkg-config (Avoiding Auto-Detection)

**Problem**: Some Makefiles use pkg-config to auto-detect optional features:
```makefile
# conmon Makefile example
ifeq ($(shell $(PKG_CONFIG) --exists libsystemd && echo "0"), 0)
  LIBS += $(shell $(PKG_CONFIG) --libs libsystemd)
  CFLAGS += -D USE_JOURNALD=1
endif
```

If libsystemd is installed, pkg-config succeeds → systemd enabled → requires systemd headers.
But we want to disable systemd support.

**Solution**: Override PKG_CONFIG to always fail
```bash
# Disable all pkg-config checks
make PKG_CONFIG=/bin/false

# Or use 'true' if checks use exit code only (less reliable)
make PKG_CONFIG=true  # Returns success but outputs nothing
```

**Example: conmon without systemd**
```bash
# Get glib deps manually
CFLAGS="$(pkg-config --cflags glib-2.0)"
GLIB_LIBS="$(pkg-config --static --libs glib-2.0)"

# Disable pkg-config in Makefile to prevent systemd detection
make bin/conmon \
  PKG_CONFIG=/bin/false \
  CFLAGS="$CFLAGS" \
  LDFLAGS="-static-libgcc -Wl,-Bstatic $GLIB_LIBS -Wl,-Bdynamic"
```

**When to disable**:
- Makefile tries to enable optional features you don't want
- Missing headers for auto-detected libraries
- Want explicit control over dependencies

**Alternative**: Provide libs manually via LIBS variable (if Makefile supports it)
```bash
make PKG_CONFIG=/bin/false LIBS="$EXPLICIT_LIBS"
```

#### pkg-config Paths

pkg-config searches for `.pc` files in:
```bash
# Default search path
/usr/lib/pkgconfig
/usr/lib/x86_64-linux-gnu/pkgconfig
/usr/local/lib/pkgconfig

# Custom libraries (add to search path)
export PKG_CONFIG_PATH="/opt/mylib/lib/pkgconfig:$PKG_CONFIG_PATH"

# Verify which .pc file is found
pkg-config --debug glib-2.0 2>&1 | grep "Parsing package file"
```

**Common scenario**: Building library from source that other tools depend on
```bash
# Build libseccomp from source
cd libseccomp-src
./configure --prefix=/workspace/libseccomp-install --enable-static
make install

# Export path so crun can find it
export PKG_CONFIG_PATH="/workspace/libseccomp-install/lib/pkgconfig:$PKG_CONFIG_PATH"

# Build crun (configure script uses pkg-config)
cd crun-src
./configure  # Automatically finds libseccomp via pkg-config
```

#### Summary

| Goal | pkg-config Usage |
|------|------------------|
| **Full static** | `pkg-config --libs` + `-static` linker flag |
| **Glibc dynamic** | `pkg-config --static --libs` wrapped in `-Wl,-Bstatic ... -Wl,-Bdynamic` |
| **Get CFLAGS** | `pkg-config --cflags` (always safe) |
| **Disable detection** | `make PKG_CONFIG=/bin/false` |
| **Custom .pc path** | `export PKG_CONFIG_PATH=/path/to/pc:$PKG_CONFIG_PATH` |

**Remember**: `pkg-config --static` lists deps, `-Wl,-Bstatic` forces linking.

### Autotools + libtool Linking Issues

**Problem**: Projects using autotools (configure script) with libtool have a fundamental incompatibility with `-Wl,-Bstatic` selective static linking.

#### Why libtool Breaks -Wl,-Bstatic

**Root Cause**: libtool wraps the linker command and **rewrites flags into its own preferred order**, filtering out `-Wl,-Bstatic` and `-Wl,-Bdynamic` flags entirely.

Example from crun build:
```bash
# What you pass to make
make LDFLAGS="-Wl,-Bstatic" LIBS="-lcap -Wl,-Bdynamic"

# What libtool actually executes
./libtool --mode=link clang -o crun [objects] -lcap
# ❌ Your -Wl,-Bstatic flags are gone!
```

**Why this happens**:
1. autotools generates Makefile with: `$(CC) $(LDFLAGS) objects $(LDADD) $(LIBS)`
2. configure sets `FOUND_LIBS = -lcap -lseccomp` (added to LDADD)
3. libtool processes the entire command: `./libtool --mode=link clang $(LDFLAGS) ... $(LDADD) $(LIBS)`
4. libtool **rearranges and filters** flags to ensure its own linking logic works
5. `-Wl,-Bstatic` / `-Wl,-Bdynamic` are discarded because libtool controls static/dynamic via `--static` flag

**Documented Issue**:
> "libtool rearranges ld flags into its own preferred order rather than the specific order needed, often placing `-static -dynamic` at the beginning"
> — [GNU Libtool Mailing List](https://lists.gnu.org/archive/html/libtool/2009-09/msg00030.html)

#### The Correct Solution: Use .a File Paths

**Instead of using `-l` flags, provide direct paths to `.a` files.**

libtool only rewrites `-l` flags; it **cannot modify explicit file paths**.

**Example: crun glibc dynamic build**

```bash
# ❌ WRONG: Using -l flags (libtool will ignore -Wl,-Bstatic)
make FOUND_LIBS="-Wl,-Bstatic -lcap -lseccomp -Wl,-Bdynamic -lm"

# ✅ CORRECT: Using .a file paths (libtool cannot rewrite paths)
LIBCAP_A="/usr/lib/x86_64-linux-gnu/libcap.a"
LIBSECCOMP_A="/workspace/install/lib/libseccomp.a"
make FOUND_LIBS="$LIBCAP_A $LIBSECCOMP_A -lm"
```

**Result**:
```bash
# With -l flags: dynamic linking
$ ldd crun | grep libcap
libcap.so.2 => /lib/x86_64-linux-gnu/libcap.so.2  ❌

# With .a paths: static linking
$ ldd crun | grep libcap
# (empty - statically linked)  ✅
```

#### Implementation Pattern

**Step 1**: Find static library paths
```bash
# System libraries
LIBCAP_A=$(find /usr/lib* -name "libcap.a" 2>/dev/null | head -1)

# Custom-built libraries
LIBSECCOMP_A="$INSTALL_DIR/lib/libseccomp.a"
```

**Step 2**: Override FOUND_LIBS with paths
```bash
# Override the variable configure set
make FOUND_LIBS="$LIBCAP_A $LIBSECCOMP_A -lm" ...

# Or override directly in Makefile (after configure)
sed -i "s|^FOUND_LIBS = .*|FOUND_LIBS = $LIBCAP_A $LIBSECCOMP_A -lm|" Makefile
make
```

**Step 3**: Keep glibc libraries as `-l` flags
```bash
# ✅ -lm stays dynamic (glibc math library)
FOUND_LIBS="$LIBCAP_A $LIBSECCOMP_A -lm"

# ❌ Don't use -lc (libc is default, shouldn't be explicit)
```

#### Why This Works

| Method | What libtool does | Result |
|--------|------------------|--------|
| `-lcap` | Searches for libcap.so → finds .so → dynamic link | ❌ Dynamic |
| `-Wl,-Bstatic -lcap` | **Filters out -Wl,-Bstatic**, then `-lcap` → finds .so | ❌ Still dynamic |
| `/usr/lib/.../libcap.a` | **Cannot rewrite file paths** → uses .a directly | ✅ Static |

**Key insight**: libtool's rewriting logic only applies to flags (`-l`, `-L`, `-Wl`), not to actual file paths.

#### Alternative Approaches (Less Reliable)

**Option 1**: Disable libtool (invasive)
```bash
# After configure, before make
sed -i 's|^LIBTOOL = .*|LIBTOOL = $(SHELL)|' Makefile
```
This breaks libtool library handling and may cause build failures.

**Option 2**: Use `--static-libtool-libs` (limited)
```bash
./configure --enable-static --disable-shared
make LDFLAGS="-static-libtool-libs"
```
Only works for libraries built with libtool (has `.la` files). Doesn't help with system libraries.

**Option 3**: Build without libtool
```bash
./configure --disable-libtool  # If supported
```
Very rare; most projects don't support this.

**Conclusion**: Use `.a` file paths — it's the only reliable method.

#### Summary

| Build System | -Wl,-Bstatic Works? | Solution |
|-------------|-------------------|----------|
| **Plain Makefile** (conmon) | ✅ Yes | Use LIBS variable with `-Wl,-Bstatic ... -Wl,-Bdynamic` |
| **Autotools + libtool** (crun) | ❌ No (filtered) | Use direct `.a` file paths in FOUND_LIBS |
| **CMake** | ✅ Usually | Use `-Wl,-Bstatic` or `target_link_libraries(... STATIC)` |
| **Meson** | ✅ Yes | Use `static: true` in `dependency()` |

**When in doubt**: Try the `.a` file path method first — it works universally.

#### Case Study: Debugging crun libcap Linking (Real-world Example)

**Context**: Building crun (OCI runtime) for glibc-dynamic variant. Goal: statically link libcap and libseccomp, dynamically link only glibc.

**Initial Symptom**:
```bash
$ ldd crun
    libcap.so.2 => /lib/x86_64-linux-gnu/libcap.so.2  ❌ Should be static
    libc.so.6 => /lib/x86_64-linux-gnu/libc.so.6      ✅ Correct (glibc)
```

**Project Structure**:
- Build system: autotools (./configure + make)
- Uses libtool for linking: `./libtool --mode=link clang ...`
- configure sets: `FOUND_LIBS = -lcap -lseccomp -lm`
- Makefile.am: `crun_LDADD = libcrun.la $(FOUND_LIBS)`

---

##### Debugging Process (Systematic Approach)

**Phase 1: Understand Makefile Linking Order**

Examined generated Makefile:
```makefile
# autotools linking command structure
$(CC) $(LDFLAGS) objects $(LDADD) $(LIBS)
      ↑                   ↑        ↑
      before objects      middle   after objects
```

Key variables:
- `LDADD = libcrun.la $(FOUND_LIBS)` ← configure adds libraries here
- `FOUND_LIBS = -lcap -lseccomp -lm` ← detected by configure
- `LIBS = ` ← empty by default

**Phase 2: Attempted Fixes (All Failed)**

**Attempt 1**: Put `-Wl,-Bstatic` in LDFLAGS, `-Wl,-Bdynamic` in LIBS
```bash
make LDFLAGS="$LDFLAGS -Wl,-Bstatic" LIBS="-Wl,-Bdynamic" -j$(nproc)
```
**Result**: ❌ Still dynamically linked to libcap.so.2

**Reason**: libtool filters out `-Wl,-Bstatic` flags before calling linker.

---

**Attempt 2**: Override FOUND_LIBS with wrapped flags
```bash
make FOUND_LIBS="-Wl,-Bstatic -lcap -lseccomp -Wl,-Bdynamic -lm" -j$(nproc)
```
**Result**: ❌ Still dynamically linked to libcap.so.2

**Reason**: libtool strips `-Wl,-Bstatic` from FOUND_LIBS during processing.

---

**Attempt 3**: Override crun_LDADD directly
```bash
make crun_LDADD="libcrun.la -Wl,-Bstatic -lcap -lseccomp -Wl,-Bdynamic -lm" -j$(nproc)
```
**Result**: ❌ Still dynamically linked to libcap.so.2

**Reason**: Same issue - libtool processes all variables and filters static linking flags.

---

**Attempt 4**: Modify libcrun.la dependency_libs
```bash
# Edit libcrun.la to use .a paths
sed -i 's|-lcap|/usr/lib/x86_64-linux-gnu/libcap.a|' libcrun.la
make -j$(nproc)
```
**Result**: ❌ Still dynamically linked to libcap.so.2

**Reason**: libtool regenerates or ignores modifications to .la files during build.

---

**Attempt 5**: Use -all-static with selective -Wl,-Bdynamic
```bash
make LDFLAGS="$LDFLAGS -all-static" LIBS="-Wl,-Bdynamic -lm" -j$(nproc)
```
**Result**: ❌ Linker error (cannot find -lc)

**Reason**: `-all-static` forces ALL libraries static, including glibc. Adding `-Wl,-Bdynamic` after doesn't help because libtool processes it.

---

**Phase 3: Root Cause Investigation**

Examined actual libtool command being executed:
```bash
# Enable verbose output
make V=1 -j$(nproc)

# Observed command
./libtool --mode=link clang \
  -static-libgcc -static-libstdc++ \
  -o crun crun.o ... \
  libcrun.la -lcap -lseccomp -lm

# libtool then calls linker WITHOUT our -Wl,-Bstatic flags
```

**Discovery**: libtool's `--mode=link` has its own logic for handling static vs dynamic linking. It:
1. Parses all arguments
2. Rearranges them according to its own rules
3. **Filters out** `-Wl,-Bstatic` and `-Wl,-Bdynamic` because it controls static/dynamic via `--static` flag instead
4. Calls the actual linker with modified arguments

**Proof**: Web research confirmed this is a known limitation
> "libtool makes static linking impossible" — Bug report #11064
> "libtool rearranges ld flags into its own preferred order" — GNU mailing list

---

**Phase 4: The Solution - Use .a File Paths**

**Key Insight**: libtool only processes `-l` flags. It **cannot modify explicit file paths**.

**Implementation**:
```bash
# Find .a files
LIBCAP_A=$(find /usr/lib* -name "libcap.a" 2>/dev/null | head -1)
LIBSECCOMP_A="/workspace/libseccomp-install/lib/libseccomp.a"

# Override FOUND_LIBS with .a paths (not -l flags)
make FOUND_LIBS="$LIBCAP_A $LIBSECCOMP_A -lm" \
     LDFLAGS="$LDFLAGS -static-libgcc -static-libstdc++" \
     EXTRA_LDFLAGS='-s -w' \
     -j$(nproc)
```

**Why this works**:
- libtool sees `/usr/lib/x86_64-linux-gnu/libcap.a` as a file dependency, not a library flag
- Passes it directly to linker without modification
- Linker uses the `.a` file → static linking ✅
- `-lm` (glibc math) stays as `-l` flag → dynamic linking ✅

**Verification**:
```bash
$ ldd crun
    linux-vdso.so.1
    libm.so.6 => /lib/x86_64-linux-gnu/libm.so.6    ✅ glibc (dynamic)
    libc.so.6 => /lib/x86_64-linux-gnu/libc.so.6    ✅ glibc (dynamic)
    /lib64/ld-linux-x86-64.so.2

$ ldd crun | grep libcap
# (empty)  ✅ libcap statically linked
```

**Success!** 🎉

---

##### Lessons Learned

1. **Don't fight libtool** - It has its own design philosophy about static/dynamic linking
2. **Use .a file paths** - The only reliable method that works universally
3. **Systematic debugging** - Test one variable at a time, document failures
4. **Read the source** - Use `make V=1` to see actual commands being executed
5. **Research known issues** - libtool's limitations are well-documented

---

##### Quick Diagnostic Commands

**Check if project uses libtool**:
```bash
ls -la | grep libtool
# If you see: libtool, ltmain.sh, or libfoo.la files → uses libtool
```

**See actual linker commands**:
```bash
make V=1          # autotools verbose mode
make VERBOSE=1    # CMake verbose mode
```

**Test if .a file exists**:
```bash
find /usr/lib* -name "libfoo.a" 2>/dev/null
# If empty → library not installed with static version
# Install: apt-get install libfoo-dev (Debian/Ubuntu)
```

**Verify static linking worked**:
```bash
ldd ./binary | grep libfoo
# Empty = statically linked ✅
# Shows libfoo.so = dynamically linked ❌
```

---

##### When to Use This Approach

**Use .a file paths when**:
- ✅ Project uses libtool (has `.la` files, `./libtool` script)
- ✅ `-Wl,-Bstatic` flags being ignored
- ✅ Need selective static linking (some libs static, some dynamic)
- ✅ Build system is complex and you can't modify it easily

**Stick with -Wl,-Bstatic when**:
- ✅ Plain Makefile without libtool
- ✅ CMake projects (usually respects linker flags)
- ✅ Meson projects (has native `static: true` option)
- ✅ Direct compiler invocations

---

#### References

- [GNU Libtool: Linking libraries](https://www.gnu.org/software/libtool/manual/html_node/Linking-libraries.html)
- [Libtool static library issues](https://lists.gnu.org/archive/html/libtool/2009-09/msg00030.html)
- [Autotools selective static linking guide](https://sourceware.org/autobook/autobook/autobook_51.html)
- [Epic journey with static libraries](https://maelvls.dev/static-libraries-and-autoconf-hell/)
- [Bug#11064: libtool makes static linking impossible](https://bug-libtool.gnu.narkive.com/OKGVfnB3/bug-11064-critical-libtool-makes-static-linking-impossible)

---

## Go Projects

### Full Static (musl)

**Environment**:
```bash
export CGO_ENABLED=1
export GOOS=linux
export GOARCH=amd64  # or arm64

# Point CGO to musl
export CGO_CFLAGS="-I/usr/include/x86_64-linux-musl -w"
export CGO_LDFLAGS="-L/usr/lib/x86_64-linux-musl -static"
```

**Build command**:
```bash
go build \
  -tags "..." \
  -ldflags "-linkmode external -extldflags \"-static\" -s -w" \
  -o binary ./cmd/app
```

**Why this works**:
- `-linkmode external`: Use external linker (clang)
- `-extldflags "-static"`: Pass -static to linker
- CGO_LDFLAGS points to musl → truly static binary

### Glibc Dynamic

**Environment**:
```bash
export CGO_ENABLED=1
export GOOS=linux
export GOARCH=amd64

# No musl paths - use system glibc
export CGO_CFLAGS="-w"
export CGO_LDFLAGS=""
```

**Build command**:
```bash
# Template for extldflags
EXTLDFLAGS="-static-libgcc -static-libstdc++ \
  -Wl,-Bstatic \
    -lcap -lseccomp \  # Add all non-glibc libs here
  -Wl,-Bdynamic"

go build \
  -tags "..." \
  -ldflags "-linkmode external -extldflags \"${EXTLDFLAGS}\" -s -w" \
  -o binary ./cmd/app
```

**Key points**:
- `-linkmode external`: Required to pass custom linker flags
- List all CGO dependencies between `-Wl,-Bstatic` and `-Wl,-Bdynamic`
- Don't include glibc libs (libc, libm, etc.) - they default to dynamic

**Verification**:
```bash
ldd binary | grep -v "linux-vdso\|libc.so\|ld-linux\|libresolv.so"
# Should be empty
```

---

## Rust Projects

### Full Static (musl)

**Target setup**:
```bash
# Architecture-specific musl targets
x86_64: x86_64-unknown-linux-musl
aarch64: aarch64-unknown-linux-musl

# Add target if not installed
rustup target add x86_64-unknown-linux-musl
```

**Build command**:
```bash
# Option 1: Use musl target (preferred)
export RUSTFLAGS='-C link-arg=-s'
cargo build --release --target x86_64-unknown-linux-musl

# Option 2: Force static with default target
export RUSTFLAGS='-C target-feature=+crt-static -C link-arg=-s'
cargo build --release
```

**Binary location**:
- With target: `target/x86_64-unknown-linux-musl/release/binary`
- Without: `target/release/binary`

### Glibc Dynamic

**Standard approach** (this is the expected behavior):
```bash
# Use default gnu target (x86_64-unknown-linux-gnu)
export RUSTFLAGS='-C link-arg=-s'
cargo build --release
```

**Result**: Binary will dynamically link to **glibc AND libgcc_s.so.1**:
```bash
$ ldd target/release/binary
    linux-vdso.so.1
    libgcc_s.so.1 => /lib/x86_64-linux-gnu/libgcc_s.so.1  ← GCC runtime
    libc.so.6 => /lib/x86_64-linux-gnu/libc.so.6          ← glibc
    /lib64/ld-linux-x86-64.so.2
```

**Why libgcc_s.so.1 is unavoidable**:

1. **Rust std library uses unwinding** for panic handling (`_Unwind_*` symbols)
2. **libgcc_s.so.1 provides these symbols** with version tags (`@GCC_3.0`, etc.)
3. **Only dynamic version exists** - libgcc_s is not available as a static library
4. **Precompiled std** - Rust's official `x86_64-unknown-linux-gnu` std is already compiled with libgcc_s dependency

**What doesn't work** (tested and confirmed):
- ❌ `-C link-arg=-static-libgcc` - Flag ignored, std already depends on libgcc_s.so.1
- ❌ `-Wl,-Bstatic -lgcc -Wl,-Bdynamic` - Links libgcc.a but still needs libgcc_s.so.1 for unwinding
- ❌ Direct `libgcc.a` linking - Unwinding symbols still require libgcc_s.so.1
- ❌ `panic=abort` - Still compiles panic_unwind crate in std
- ❌ `build-std` + `llvm-libunwind` - Feature incomplete, duplicate lang item errors

**Is libgcc_s.so.1 acceptable?**

✅ **Yes, it's a system library** (like libc.so.6):
- Present on all Linux systems with GCC (universal)
- Size: ~175 KB (negligible)
- Maintained by GCC project (stable ABI)
- Same compatibility guarantees as glibc

**Official Rust documentation**:
> "Default Rust builds shipped in rustup are dynamically linked against libgcc_s"
>
> — [Rust Issue #119504](https://github.com/rust-lang/rust/issues/119504)

**Alternative for truly static Rust binaries**:

Use **musl target** instead (see "Full Static (musl)" section above):
```bash
cargo build --release --target x86_64-unknown-linux-musl
→ Fully static, no dynamic dependencies at all (including no libgcc_s)
```

**Summary**: For Rust + glibc, accept both `libc.so.6` and `libgcc_s.so.1` as system dependencies

---

## Verification Checklist

### After Build

1. **Check dynamic dependencies**:
   ```bash
   ldd ./binary
   ```

2. **For full static**:
   ```bash
   ldd ./binary 2>&1 | grep -q "not a dynamic executable"
   # Exit code 0 = success
   ```

3. **For glibc dynamic (C/C++ binaries)**:
   ```bash
   # Should only show glibc and vdso
   ldd ./binary | grep -v "linux-vdso\|libc.so\|ld-linux\|libresolv.so\|libm.so" | grep "=>"
   # Should be empty
   ```

4. **For glibc dynamic (Rust binaries)**:
   ```bash
   # Should show glibc + libgcc_s only
   ldd ./binary | grep -v "linux-vdso\|libc.so\|ld-linux\|libgcc_s.so\|libm.so" | grep "=>"
   # Should be empty
   ```

5. **Check for forbidden libs** (applies to both C/C++ and Rust):
   ```bash
   # These should NOT appear in glibc-dynamic builds
   ldd ./binary | grep -E "libcap\.so|libglib.*\.so|libstdc\+\+\.so|libunwind\.so"
   # Should be empty

   # Note: libgcc_s.so.1 is ALLOWED for Rust binaries (system library)
   ```

### Common Issues

**Issue**: `libfoo.so.X` still appears dynamically
**Cause**: Library flag came after `-Wl,-Bdynamic`
**Fix**: Ensure library is between `-Wl,-Bstatic` and `-Wl,-Bdynamic`

**Issue**: `undefined reference to symbol` with musl
**Cause**: Missing library or wrong library order
**Fix**: Add library explicitly, check if musl provides it

**Issue**: SIGFPE during execution (musl build)
**Cause**: Binary using glibc NSS despite musl linking
**Fix**: Ensure CGO_CFLAGS/LDFLAGS point to musl paths, verify with ldd

**Issue**: Makefile ignores LDFLAGS
**Cause**: Library flags added by configure come after your LDFLAGS
**Fix**: Override LIBS variable instead, or patch Makefile

**Issue**: pkg-config pulling in unwanted dependencies
**Cause**: pkg-config defaults to dynamic libraries
**Fix**: Disable pkg-config (`PKG_CONFIG=/bin/false`) and specify libs manually

**Issue**: Rust binary has `libgcc_s.so.1` (glibc-dynamic build)
**Cause**: Rust std library requires unwinding support from libgcc_s
**Fix**: This is **expected and unavoidable** for Rust + glibc. Options:
- ✅ Accept it (libgcc_s is a system library like libc)
- ✅ Use musl target for fully static binary (`--target x86_64-unknown-linux-musl`)
- ❌ Cannot eliminate with `-static-libgcc` or `build-std` (tested, doesn't work)

---

## Testing in Container (Quick Validation)

```bash
# Spin up test environment
podman run -it --rm ubuntu:rolling bash

# Install minimal tools
apt-get update && apt-get install -y clang libcap-dev

# Test C program
cat > test.c << 'EOF'
#include <sys/capability.h>
int main() {
    cap_t caps = cap_get_proc();
    if (caps) cap_free(caps);
    return 0;
}
EOF

# Test static linking
clang test.c -Wl,-Bstatic -lcap -Wl,-Bdynamic -static-libgcc
ldd a.out | grep libcap
# Should be empty (statically linked)

# Test dynamic linking (wrong)
clang test.c -lcap -static-libgcc
ldd a.out | grep libcap
# Shows libcap.so.2 (dynamically linked)
```

---

## Architecture Notes

### x86_64 (amd64)
- musl: `x86_64-linux-musl`
- Go: `GOARCH=amd64`
- Rust: `x86_64-unknown-linux-musl`

### aarch64 (arm64)
- musl: `aarch64-linux-musl`
- Go: `GOARCH=arm64`
- Rust: `aarch64-unknown-linux-musl`

---

## Quick Reference: Compiler Selection

| Scenario | Use GCC | Use Clang | Notes |
|----------|---------|-----------|-------|
| **musl static (single arch)** | ✅ musl-gcc wrapper | ✅ Manual paths (preferred) | Clang more flexible |
| **musl static (cross-compile)** | ❌ Need separate toolchain | ✅ `-target` flag | Clang easier |
| **glibc dynamic** | ✅ Works perfectly | ✅ Works perfectly | No difference |
| **Existing project (Makefile)** | ✅ If `CC=gcc` | ✅ If `CC=clang` | Follow convention |
| **CI/CD container builds** | ⚠️ Need musl-tools | ✅ More portable | Clang recommended |
| **Debug/development** | ✅ Familiar to most | ✅ Better diagnostics | Personal preference |

### Installation Requirements

**For GCC musl static**:
```bash
# Debian/Ubuntu
apt-get install gcc musl-dev musl-tools

# Gentoo
emerge sys-devel/gcc dev-libs/musl
```

**For Clang musl static**:
```bash
# Debian/Ubuntu
apt-get install clang musl-dev

# Gentoo
emerge sys-devel/clang dev-libs/musl
```

Note: `musl-tools` (with musl-gcc wrapper) not needed for Clang.

---

## References

- musl libc: https://musl.libc.org/
- Linker control: `man ld` (search for -Bstatic, -Bdynamic)
- Go external linking: https://pkg.go.dev/cmd/cgo
- Rust targets: https://doc.rust-lang.org/rustc/platform-support.html
- Rust libgcc_s issue: https://github.com/rust-lang/rust/issues/119504
- Rust CRT static RFC: https://rust-lang.github.io/rfcs/1721-crt-static.html

**Last updated**: 2025-12-17
**Based on**: static-rootless-container-tools glibc build experience (extensively tested)
