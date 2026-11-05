#!/bin/sh
# platform: host-agnostic
#   usage: fetch-llvm-dev.sh ARCH     ARCH is x86_64 or arm64; prints the unpacked llvm22-dev/ under $WORK
#          (WORK_ROOT/work-src when ZIG_VARIANT is unset), verified against the SHA256SUMS of the clang-22
#          release tagged CLANG_VERSION; the tarball must hold a top-level llvm22-dev/.
#          MAVERGREEN_RELEASES replaces https://github.com
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"
[ $# -eq 1 ] || { echo "usage: fetch-llvm-dev.sh ARCH" >&2; exit 2; }
ARCH="$1"
case "$ARCH" in x86_64|arm64) : ;; *) echo "FATAL: ARCH must be x86_64 or arm64, not '$ARCH'" >&2; exit 2 ;; esac
. "$HERE/versions.sh"; . "$HERE/msc.sh"; . "$SHIPYARD_SCRIPTS/mavericks_fetch.sh"; . "$HERE/lib-zig.sh"
: "${WORK:=$WORK_ROOT/work-src}"
BASE="${MAVERGREEN_RELEASES:-https://github.com}/Mavergreen/clang-22/releases/download/$CLANG_VERSION"
CACHE="$WORK/llvm-dev-dl"; OUT="$WORK/llvm22-dev-$ARCH"
asset="llvm22-dev-$CLANG_VERSION-darwin-$ARCH.tar.gz"
mkdir -p "$CACHE"
shipyard_curl --quiet "$BASE/SHA256SUMS" "$CACHE/SHA256SUMS-$ARCH" \
  || { echo "FATAL: could not fetch $BASE/SHA256SUMS" >&2; exit 1; }
want="$(sums_lookup "$asset" < "$CACHE/SHA256SUMS-$ARCH")" \
  || { echo "FATAL: $asset is not listed (once, with a sha256) in $BASE/SHA256SUMS" >&2; exit 1; }
shipyard_fetch_verified "$BASE/$asset" "$want" "$CACHE" "$asset" \
  || { echo "FATAL: $BASE/$asset did not verify against SHA256SUMS" >&2; exit 1; }
rm -rf "$OUT"; mkdir -p "$OUT"
tar -xf "$CACHE/$asset" -C "$OUT"
[ -d "$OUT/llvm22-dev" ] || { echo "FATAL: $asset holds no llvm22-dev/" >&2; exit 1; }
echo "$OUT/llvm22-dev"
