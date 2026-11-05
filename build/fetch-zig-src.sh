#!/bin/sh
# platform: host-agnostic
#   usage: fetch-zig-src.sh     prints a fresh, unpatched zig-$ZIG_VERSION/ under $WORK (WORK_ROOT/work-src
#          when ZIG_VARIANT is unset); the tarball is verified against the shasum in ziglang.org's index.json.
#          ZIG_INDEX_URL and ZIG_DOWNLOAD_BASE replace https://ziglang.org/download/index.json and
#          https://ziglang.org/download
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/versions.sh"; . "$HERE/msc.sh"; . "$SHIPYARD_SCRIPTS/mavericks_fetch.sh"; . "$HERE/lib-zig.sh"
: "${WORK:=$WORK_ROOT/work-src}"
INDEX_URL="${ZIG_INDEX_URL:-https://ziglang.org/download/index.json}"
BASE="${ZIG_DOWNLOAD_BASE:-https://ziglang.org/download}"
CACHE="$WORK/zig-src-dl"; OUT="$WORK/zig-$ZIG_VERSION"
mkdir -p "$CACHE"
shipyard_curl --quiet "$INDEX_URL" "$CACHE/index.json" \
  || { echo "FATAL: could not fetch $INDEX_URL" >&2; exit 1; }
want="$(zig_src_shasum "$ZIG_VERSION" < "$CACHE/index.json")" || want=""
case "$want" in
  *[!0-9a-f]*|'') echo "FATAL: no src shasum for Zig $ZIG_VERSION in $INDEX_URL" >&2; exit 1 ;;
esac
[ "${#want}" -eq 64 ] || { echo "FATAL: no src shasum for Zig $ZIG_VERSION in $INDEX_URL" >&2; exit 1; }
name="zig-$ZIG_VERSION.tar.xz"
shipyard_fetch_verified "$BASE/$ZIG_VERSION/$name" "$want" "$CACHE" "$name" \
  || { echo "FATAL: $BASE/$ZIG_VERSION/$name did not verify against $INDEX_URL" >&2; exit 1; }
rm -rf "$OUT"
tar -xf "$CACHE/$name" -C "$WORK"
[ -f "$OUT/build.zig" ] || { echo "FATAL: $OUT/build.zig not found after extract" >&2; exit 1; }
echo "$OUT"
