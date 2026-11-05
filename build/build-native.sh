#!/bin/sh
# platform: macOS-only -- a host zig on this Mac builds the 10.9-hosted Zig, as zig-bootstrap's final step does
#   usage: build-native.sh     builds the patched Zig $ZIG_VERSION for Mac OS X 10.9 (x86_64, ReleaseFast, static LLVM from
#          fetch-llvm-dev.sh x86_64) with a host zig, stages it with the family's in-tree layout at
#          $NATIVE_STAGE_ROOT$NATIVE_PREFIX, records lib/mavergreen/BUILD-INFO, and prints the staged prefix.
#          The host zig is HOST_ZIG (a zig executable) when set, else build-host-zig.sh's stage for this machine:
#          $CROSS_STAGE_ROOT$CROSS_PREFIX on arm64, $NATIVE_STAGE_ROOT$NATIVE_PREFIX on x86_64. A host zig whose prefix
#          is the output stage (x86_64's, or a previous build-native.sh product) is moved to $WORK/builder-zig, replacing
#          any earlier one, once every fetch has succeeded and just before the stage is cleared, and builds from there;
#          the stage then holds only the product. When that stage has no zig and HOST_ZIG is unset, a zig left in
#          $WORK/builder-zig by an earlier run that failed is the host zig.
#          The build directory is $MAVERICKS_BUILD_ROOT/zig-native (default ${TMPDIR}/mm-build).
#          RECAULK_LIB is as for build-host-zig.sh: an unreleased Recaulk to try, never for a release.
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$HERE/.." && pwd)"
started="$(date +%s)"

ZIG_VARIANT=native; export ZIG_VARIANT
. "$HERE/versions.sh"; . "$HERE/msc.sh"; . "$HERE/lib-zig.sh"
STAGE="$NATIVE_STAGE_ROOT$NATIVE_PREFIX"
BUILD="${MAVERICKS_BUILD_ROOT:-${TMPDIR:-/tmp}/mm-build}/zig-native"

# platform: under Rosetta uname -m says x86_64; hw.optional.arm64 is 1 on Apple Silicon either way, absent on 10.9
if [ "$(sysctl -n hw.optional.arm64 2>/dev/null || true)" = 1 ]; then
  ARCH=arm64; HOST_STAGE="$CROSS_STAGE_ROOT$CROSS_PREFIX"
else
  ARCH=x86_64; HOST_STAGE="$NATIVE_STAGE_ROOT$NATIVE_PREFIX"
fi
BUILDER="${HOST_ZIG:-$HOST_STAGE/bin/zig}"
if [ -z "${HOST_ZIG:-}" ] && [ ! -x "$BUILDER" ] && [ "$HOST_STAGE" = "$STAGE" ] && [ -x "$WORK/builder-zig/bin/zig" ]; then
  BUILDER="$WORK/builder-zig/bin/zig"
  echo "build-native: no zig at $HOST_STAGE; building with the host zig an earlier run moved to $WORK/builder-zig" >&2
fi
[ -x "$BUILDER" ] || { echo "FATAL: no host zig at $BUILDER or $WORK/builder-zig/bin/zig (run build/build-host-zig.sh, or set HOST_ZIG)" >&2; exit 1; }
got="$("$BUILDER" version)"
[ "$got" = "$ZIG_VERSION" ] || { echo "FATAL: host zig $BUILDER says '$got', not $ZIG_VERSION" >&2; exit 1; }

SRC="$(sh "$HERE/fetch-zig-src.sh")"
sh "$SHIPYARD_SCRIPTS/apply_patches.sh" "$SRC" "$REPO_ROOT/patches" >&2
BUILD_INFO="$(build_info native)"
LLVM="$(sh "$HERE/fetch-llvm-dev.sh" x86_64)"
LIBCXX_FROM="$(sh "$HERE/fetch-llvm-dev.sh" arm64)"
[ -f "$LIBCXX_FROM/lib/x86_64-apple-darwin/libc++.a" ] && [ -d "$LIBCXX_FROM/include/c++/v1" ] \
  || { echo "FATAL: $LIBCXX_FROM has no x86_64 libc++.a and include/c++/v1" >&2; exit 1; }
if [ "$ARCH" = x86_64 ]; then : "${LIPO:=${CLANG22:-/usr/local/mavergreen/clang22}/bin/llvm-lipo}"; export LIPO; fi
RECAULK_A="$(fetch_recaulk)"
RECAULK_INCLUDE="${RECAULK_A%/lib/librecaulk.a}/include/recaulk"
SDK="$(sh "$SHIPYARD_SCRIPTS/fetch_sdk.sh" --arch x86_64)"

LLVM_CMAKE="$LLVM/lib/cmake/llvm/LLVMConfig.cmake"
[ -f "$LLVM_CMAKE" ] || { echo "FATAL: $LLVM has no lib/cmake/llvm/LLVMConfig.cmake" >&2; exit 1; }
llvm_set() { sed -n "s/^set($1 \\(.*\\))\$/\\1/p" "$LLVM_CMAKE" | head -n 1; }
llvm_on() { case "$(llvm_set "$1")" in ""|0|OFF|FALSE|NO|N|IGNORE|NOTFOUND|*-NOTFOUND) echo false ;; *) echo true ;; esac; }
LLVM_TARGETS="$(llvm_set LLVM_TARGETS_TO_BUILD | tr ';' ' ')"
[ -n "$LLVM_TARGETS" ] || { echo "FATAL: $LLVM_CMAKE sets no LLVM_TARGETS_TO_BUILD" >&2; exit 1; }

builder_prefix="$(cd "$(dirname "$BUILDER")/.." && pwd -P)"
if [ -d "$STAGE" ] && [ "$builder_prefix" = "$(cd "$STAGE" && pwd -P)" ]; then
  rm -rf "$WORK/builder-zig"; mkdir -p "$WORK"
  mv "$STAGE" "$WORK/builder-zig"
  BUILDER="$WORK/builder-zig/bin/$(basename "$BUILDER")"
  echo "build-native: the host zig was the output stage; building with it from $WORK/builder-zig" >&2
fi
rm -rf "$BUILD" "$STAGE"
mkdir -p "$BUILD"
ZIG_GLOBAL_CACHE_DIR="$BUILD/zig-global-cache"; ZIG_LOCAL_CACHE_DIR="$BUILD/zig-local-cache"
export ZIG_GLOBAL_CACHE_DIR ZIG_LOCAL_CACHE_DIR
# platform: --sysroot would re-root --search-prefix's -L under the SDK; SDKROOT names the SDK of every 10.9 target alone
SDKROOT="$SDK"; export SDKROOT
# platform: GitHub's macos-26 runners have 7 GiB; Zig refuses its compiler step (max_rss 8 GB) on less unless told --maxrss
# spec: PORT.md 0004-llvm-targets-x86-aarch64.patch -- the langref's examples build for wasm32, a target this LLVM lacks
(cd "$SRC" && "$BUILDER" build -Doptimize=ReleaseFast -Dtarget=x86_64-macos.10.9 -Dcpu=x86_64 -Denable-llvm -Dstatic-llvm \
  --search-prefix "$LLVM" -Dversion-string="$ZIG_VERSION" --prefix "$STAGE" \
  --maxrss 8000000000 -Dno-langref "-Dllvm-targets=$LLVM_TARGETS" \
  -Dllvm-has-zlib="$(llvm_on LLVM_ENABLE_ZLIB)" -Dllvm-has-zstd="$(llvm_on LLVM_ENABLE_ZSTD)") >&2

[ -f "$STAGE/bin/zig" ] && [ -d "$STAGE/lib/zig/std" ] || { echo "FATAL: zig build left no bin/zig and lib/zig/ in $STAGE" >&2; exit 1; }
if [ "$ARCH" = x86_64 ]; then
  got="$("$STAGE/bin/zig" version)"
  [ "$got" = "$ZIG_VERSION" ] || { echo "FATAL: staged zig says '$got', not $ZIG_VERSION" >&2; exit 1; }
fi

lay_out_mavergreen "$STAGE/lib/mavergreen"
ln -s ../sdk109/SDKs "$STAGE/SDKs"
echo "$BUILD_INFO" > "$STAGE/lib/mavergreen/BUILD-INFO"

echo "build-native: zig $ZIG_VERSION for x86_64-macos.10.9 built by $BUILDER, staged in $(( $(date +%s) - started ))s" >&2
echo "$STAGE"
