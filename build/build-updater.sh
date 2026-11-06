#!/bin/sh
# platform: macOS-only -- ditto copies a built app bundle that find lays out deeper than the build root
#   usage: build-updater.sh native|cross     prints the built .app path. Builds with the clang22 components/clang/version
#          pins (shipyard's fetch_clang22.sh: on 10.9 the native clang22, elsewhere clang22-cross), in a fresh build
#          directory. The icon is updater/zig.icns, Zig's logomark (see updater/ICON-CREDIT.txt).
# spec: shipyard SKILL.md "Sparkle updater" -- the updater builds with clang22 on every host, one configure per arch
set -eu
v="${1:?usage: build-updater.sh native|cross}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MAVERICKS_ROOT="$ROOT"; export MAVERICKS_ROOT
. "$ROOT/build/msc.sh"
case "$v" in native) short=zig; arch=x86_64; floor=10.9 ;; cross) short=zig-cross; arch=arm64; floor=11.0 ;; *) echo "native|cross" >&2; exit 2 ;; esac
B="${MAVERICKS_BUILD_ROOT:-${TMPDIR:-/tmp}/mm-build}/mavergreen-zig-updater-$v"
# platform: /usr/local/mavergreen/bin reaches PATH only through a login shell's paths.d
SYCM="$(command -v shipyard-cmake || echo /usr/local/mavergreen/bin/shipyard-cmake)"
CL="$(sh "$SHIPYARD_SCRIPTS/fetch_clang22.sh" "$ROOT/components/clang")" || { echo "FATAL: no clang22 $(cat "$ROOT/components/clang/version") for this host" >&2; exit 1; }
# platform: a build directory configured before keeps its cached compiler, so a reconfigure could not move to clang22
rm -rf "$B"
"$SYCM" -S "$ROOT" -B "$B" -DZIG_VARIANT="$v" -DCMAKE_OSX_ARCHITECTURES="$arch" \
  -DCMAKE_OBJC_COMPILER="$CL/bin/clang" -DCMAKE_OBJC_COMPILER_TARGET="$arch-apple-macos$floor" \
  -DCMAKE_OBJC_FLAGS=--no-default-config -DCMAKE_EXE_LINKER_FLAGS=-fuse-ld=lld \
  -DCMAKE_TOOLCHAIN_FILE="$(dirname "$SHIPYARD_SCRIPTS")/MavericksToolchain.cmake" >&2
"$SYCM" --build "$B" >&2
app="$(find "$B" -maxdepth 3 -name "$short-updater.app" -type d | head -1)"
[ -n "$app" ] || { echo "FATAL: no $short-updater.app under $B" >&2; exit 1; }
[ "$app" = "$B/$short-updater.app" ] || { rm -rf "$B/$short-updater.app"; ditto "$app" "$B/$short-updater.app"; }
echo "$B/$short-updater.app"
