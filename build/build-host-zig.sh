#!/bin/sh
# platform: macOS-only -- Zig's CMake bootstrap with Apple clang on arm64, or clang22 on 10.9
#   usage: build-host-zig.sh     builds a patched Zig $ZIG_VERSION for the machine it runs on and stages it
#          with the family's in-tree layout: arm64 (Apple clang, pinned 11.3 SDK, minos 11.0) at
#          $CROSS_STAGE_ROOT$CROSS_PREFIX, x86_64 (clang22, pinned 10.9 SDK) at $NATIVE_STAGE_ROOT$NATIVE_PREFIX.
#          The arm64 stage records lib/mavergreen/BUILD-INFO (lib-zig.sh's build_info cross), which
#          package-cross-pkg.sh checks. Prints the staged prefix. CLANG22 (default /usr/local/mavergreen/clang22) is the x86_64 compiler;
#          the build directory is $MAVERICKS_BUILD_ROOT/zig-host (default ${TMPDIR}/mm-build). x86_64 needs ninja.
#          RECAULK_LIB names a librecaulk.a (with ../include/recaulk beside its lib/) to build with instead of the
#          pinned release, to try an unreleased Recaulk; never for a release.
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$HERE/.." && pwd)"
started="$(date +%s)"

# platform: under Rosetta uname -m says x86_64; hw.optional.arm64 is 1 on Apple Silicon either way, absent on 10.9
if [ "$(sysctl -n hw.optional.arm64 2>/dev/null || true)" = 1 ]; then
  ARCH=arm64; ZIG_VARIANT=cross
else
  ARCH=x86_64; ZIG_VARIANT=native
fi
export ZIG_VARIANT
. "$HERE/versions.sh"; . "$HERE/msc.sh"; . "$HERE/lib-zig.sh"

TOOLCHAIN_FILE="$SHIPYARD_SCRIPTS/../MavericksToolchain.cmake"
[ -f "$TOOLCHAIN_FILE" ] || { echo "FATAL: no MavericksToolchain.cmake beside $SHIPYARD_SCRIPTS" >&2; exit 1; }
BUILD="${MAVERICKS_BUILD_ROOT:-${TMPDIR:-/tmp}/mm-build}/zig-host"
JOBS="$(sysctl -n hw.ncpu)"

# spec: PORT.md 0004-llvm-targets-x86-aarch64.patch -- the langref's examples build for wasm32, a target this LLVM lacks
NO_LANGREF=-Dno-langref
if [ "$ARCH" = arm64 ]; then
  STAGE="$CROSS_STAGE_ROOT$CROSS_PREFIX"
  SDK="$(sh "$SHIPYARD_SCRIPTS/fetch_sdk.sh" --arch arm64)"
  # platform: an explicit aarch64-macos.11.0 is not the native target, so Zig takes its own bundled libc and
  #           SDKSettings.json (sdk 27.0) and no SDK library directory; --libc makes the pinned SDK the libc
  #           installation, its SDKSettings.json the recorded sdk, and --search-prefix /usr (sysroot-relative)
  #           its usr/lib the place -lz is found
  LIBC_FILE="$BUILD/libc-$ARCH.txt"
  set -- -DCMAKE_C_COMPILER=/usr/bin/clang -DCMAKE_CXX_COMPILER=/usr/bin/clang++ \
    -DZIG_TARGET_TRIPLE=aarch64-macos.11.0 -DZIG_TARGET_MCPU=baseline \
    "-DZIG_EXTRA_BUILD_ARGS=--sysroot;$SDK;--libc;$LIBC_FILE;--search-prefix;/usr;$NO_LANGREF"
else
  STAGE="$NATIVE_STAGE_ROOT$NATIVE_PREFIX"
  CLANG22="${CLANG22:-/usr/local/mavergreen/clang22}"
  [ -x "$CLANG22/bin/clang" ] || { echo "FATAL: no clang22 at $CLANG22 (set CLANG22)" >&2; exit 1; }
  : "${LIPO:=$CLANG22/bin/llvm-lipo}"; export LIPO
  SDK="$(sh "$SHIPYARD_SCRIPTS/fetch_sdk.sh" --arch x86_64)"
  set -- -DCMAKE_C_COMPILER="$CLANG22/bin/clang" -DCMAKE_CXX_COMPILER="$CLANG22/bin/clang++" \
    -DCMAKE_AR="$CLANG22/bin/llvm-ar" -DCMAKE_RANLIB="$CLANG22/bin/llvm-ranlib" "-DZIG_EXTRA_BUILD_ARGS=--sysroot;$SDK;$NO_LANGREF" \
    -DZIG_TARGET_TRIPLE=x86_64-macos.10.9 -DZIG_TARGET_MCPU=baseline
fi
# platform: 10.9's make is a Command Line Tools stub; ninja is not
if command -v ninja >/dev/null 2>&1; then
  set -- -G Ninja "$@"
elif [ "$ARCH" = x86_64 ]; then
  echo "FATAL: no ninja on PATH; on Mac OS X 10.9, install Mavergreen's ninja (make is a Command Line Tools stub)" >&2; exit 1
fi

SRC="$(sh "$HERE/fetch-zig-src.sh")"
sh "$SHIPYARD_SCRIPTS/apply_patches.sh" "$SRC" "$REPO_ROOT/patches" >&2
BUILD_INFO="$(build_info cross)"
LLVM="$(sh "$HERE/fetch-llvm-dev.sh" "$ARCH")"
if [ "$ARCH" = arm64 ]; then LIBCXX_FROM="$LLVM"; else LIBCXX_FROM="$(sh "$HERE/fetch-llvm-dev.sh" arm64)"; fi
[ -f "$LIBCXX_FROM/lib/x86_64-apple-darwin/libc++.a" ] && [ -d "$LIBCXX_FROM/include/c++/v1" ] \
  || { echo "FATAL: $LIBCXX_FROM has no x86_64 libc++.a and include/c++/v1" >&2; exit 1; }
RECAULK_A="$(fetch_recaulk)"
RECAULK_INCLUDE="${RECAULK_A%/lib/librecaulk.a}/include/recaulk"
if [ "$ARCH" = x86_64 ]; then
  set -- "$@" -DCMAKE_C_STANDARD_LIBRARIES="$RECAULK_A" -DCMAKE_CXX_STANDARD_LIBRARIES="$RECAULK_A"
  SDKROOT="$SDK"; export SDKROOT
fi

rm -rf "$BUILD" "$STAGE"
mkdir -p "$BUILD"
if [ "$ARCH" = arm64 ]; then darwin_libc_file "$SDK" > "$LIBC_FILE"; fi
lay_out_mavergreen "$SRC/mavergreen"
ZIG_GLOBAL_CACHE_DIR="$BUILD/zig-global-cache"; ZIG_LOCAL_CACHE_DIR="$BUILD/zig-local-cache"
export ZIG_GLOBAL_CACHE_DIR ZIG_LOCAL_CACHE_DIR
shipyard-cmake -S "$SRC" -B "$BUILD" "$@" \
  -DCMAKE_TOOLCHAIN_FILE="$TOOLCHAIN_FILE" -DCMAKE_OSX_ARCHITECTURES="$ARCH" \
  -DCMAKE_BUILD_TYPE=Release -DCMAKE_PREFIX_PATH="$LLVM" -DZIG_USE_LLVM_CONFIG=ON \
  -DZIG_STATIC_LLVM=ON -DZIG_VERSION="$ZIG_VERSION" -DCMAKE_INSTALL_PREFIX="$STAGE" >&2
shipyard-cmake --build "$BUILD" --target zig2 -j "$JOBS" >&2
shipyard-cmake --install "$BUILD" >&2

[ -x "$STAGE/bin/zig" ] && [ -d "$STAGE/lib/zig/std" ] || { echo "FATAL: install left no bin/zig and lib/zig/ in $STAGE" >&2; exit 1; }
got="$("$STAGE/bin/zig" version)"
[ "$got" = "$ZIG_VERSION" ] || { echo "FATAL: staged zig says '$got', not $ZIG_VERSION" >&2; exit 1; }

lay_out_mavergreen "$STAGE/lib/mavergreen"
ln -s ../sdk109/SDKs "$STAGE/SDKs"
if [ "$ARCH" = arm64 ]; then echo "$BUILD_INFO" > "$STAGE/lib/mavergreen/BUILD-INFO"; fi

echo "build-host-zig: zig $got for $ARCH staged in $(( $(date +%s) - started ))s" >&2
echo "$STAGE"
