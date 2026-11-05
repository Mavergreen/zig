#!/bin/sh
# platform: host-agnostic
#   usage: fetch-zig-src-test.sh     offline: serves a file:// tree, never the network
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$HERE/.." && pwd)"
command -v xz >/dev/null 2>&1 || { echo "SKIP no xz to build the fixture tarball"; exit 77; }
t="$(mktemp -d "${TMPDIR:-/tmp}/fetch-zig.XXXXXX")"; trap 'rm -rf "$t"' EXIT
fail() { echo "FAIL $1"; exit 1; }
. "$ROOT/build/versions.sh"; . "$ROOT/build/lib-zig.sh"
IDX="$HERE/fixtures/index.json"

got="$(zig_src_shasum 0.17.0 < "$IDX")"
[ "$got" = b6c7f1728f043700d6529bac980800792f824256a9d2f1839b3d62beed0b8abd ] || fail "0.17.0 shasum (got '$got')"
got="$(zig_src_shasum 0.17.1 < "$IDX")"
[ "$got" != b6c7f1728f043700d6529bac980800792f824256a9d2f1839b3d62beed0b8abd ] && [ "${#got}" -eq 64 ] || fail "0.17.1 shasum (got '$got')"
got="$(tr -d '\n ' < "$IDX" | zig_src_shasum 0.17.0)"
[ "$got" = b6c7f1728f043700d6529bac980800792f824256a9d2f1839b3d62beed0b8abd ] || fail "minified 0.17.0 shasum (got '$got')"
! zig_src_shasum 0.99.0 < "$IDX" >/dev/null || fail "absent version must fail"
! zig_src_shasum 0.17 < "$IDX" >/dev/null || fail "a version prefix must not match"

mkdir -p "$t/dl/$ZIG_VERSION" "$t/src/zig-$ZIG_VERSION"
echo 'pub fn build() void {}' > "$t/src/zig-$ZIG_VERSION/build.zig"
tar -cJf "$t/dl/$ZIG_VERSION/zig-$ZIG_VERSION.tar.xz" -C "$t/src" "zig-$ZIG_VERSION" 2>/dev/null || { echo "SKIP tar cannot write xz"; exit 77; }
sum="$(shasum -a 256 "$t/dl/$ZIG_VERSION/zig-$ZIG_VERSION.tar.xz" | awk '{print $1}')"
printf '{"%s":{"version":"%s","src":{"tarball":"x","shasum":"%s","size":"1"},"x86_64-linux":{"shasum":"%064d"}}}\n' \
  "$ZIG_VERSION" "$ZIG_VERSION" "$sum" 0 > "$t/dl/index.json"
export MAVERICKS_WORK="$t/w" ZIG_INDEX_URL="file://$t/dl/index.json" ZIG_DOWNLOAD_BASE="file://$t/dl"

out="$(sh "$ROOT/build/fetch-zig-src.sh")" || fail "fetch must succeed"
[ "$out" = "$t/w/work-src/zig-$ZIG_VERSION" ] && [ -f "$out/build.zig" ] || fail "prints the tree (got '$out')"
echo patched > "$out/build.zig"
out="$(sh "$ROOT/build/fetch-zig-src.sh")" || fail "second fetch must succeed"
[ "$(cat "$out/build.zig")" != patched ] || fail "the tree must be fresh, not reused"

printf 'tampered' >> "$t/dl/$ZIG_VERSION/zig-$ZIG_VERSION.tar.xz"
rm -rf "$t/w"
! sh "$ROOT/build/fetch-zig-src.sh" >"$t/o" 2>&1 || fail "a tampered tarball must fail closed"
[ ! -d "$t/w/work-src/zig-$ZIG_VERSION" ] || fail "no tree from a tampered tarball"

printf '{"0.1.0":{"src":{"shasum":"%s"}}}\n' "$sum" > "$t/dl/index.json"
! sh "$ROOT/build/fetch-zig-src.sh" >"$t/o" 2>&1 || fail "a version absent from the index must fail"
grep -q "$ZIG_VERSION" "$t/o" || fail "the failure must name $ZIG_VERSION"

sh -n "$ROOT/build/fetch-zig-src.sh" && sh -n "$ROOT/build/lib-zig.sh" || fail "sh -n"
echo "OK fetch-zig-src-test"
