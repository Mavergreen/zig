#!/bin/sh
# platform: host-agnostic
#   usage: fetch-llvm-dev-test.sh     offline: serves a file:// tree, never the network
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$HERE/.." && pwd)"
t="$(mktemp -d "${TMPDIR:-/tmp}/fetch-llvm.XXXXXX")"; trap 'rm -rf "$t"' EXIT
fail() { echo "FAIL $1"; exit 1; }
. "$ROOT/build/versions.sh"; . "$ROOT/build/lib-zig.sh"
SUMS="$HERE/fixtures/SHA256SUMS"

a="$(sums_lookup llvm22-dev-22.1.8-mavericks.12-darwin-x86_64.tar.gz < "$SUMS")"
[ "$a" = 1111111111111111111111111111111111111111111111111111111111111111 ] || fail "x86_64 sum (got '$a')"
! sums_lookup llvm22-dev-22.1.8-mavericks.12-darwin-ppc.tar.gz < "$SUMS" >/dev/null || fail "an unlisted asset must fail"
! sums_lookup llvm22-dev-22.1.8-mavericks.12-darwin-dup.tar.gz < "$SUMS" >/dev/null || fail "a twice-listed asset must fail"
! sums_lookup llvm22-dev-22.1.8-mavericks.12-darwin-short.tar.gz < "$SUMS" >/dev/null || fail "a malformed sum must fail"

rel="$t/rel/Mavergreen/clang-22/releases/download/$CLANG_VERSION"
mkdir -p "$rel" "$t/pk/llvm22-dev/lib"
echo lib > "$t/pk/llvm22-dev/lib/libLLVM.a"
asset="llvm22-dev-$CLANG_VERSION-darwin-x86_64.tar.gz"
tar -czf "$rel/$asset" -C "$t/pk" llvm22-dev
sum="$(shasum -a 256 "$rel/$asset" | awk '{print $1}')"
printf '%s  %s\n' "$sum" "$asset" > "$rel/SHA256SUMS"
export MAVERICKS_WORK="$t/w" MAVERGREEN_RELEASES="file://$t/rel"
run() { sh "$ROOT/build/fetch-llvm-dev.sh" "$@"; }

out="$(run x86_64)" || fail "fetch must succeed"
[ "$out" = "$t/w/work-src/llvm22-dev-x86_64/llvm22-dev" ] && [ -f "$out/lib/libLLVM.a" ] || fail "prints llvm22-dev (got '$out')"

! run arm64 >"$t/o" 2>&1 || fail "an asset missing from SHA256SUMS must fail"
grep -q 'not listed' "$t/o" || fail "the failure must say not listed ($(cat "$t/o"))"
: > "$rel/SHA256SUMS"
! run x86_64 >"$t/o" 2>&1 || fail "an empty SHA256SUMS must fail"
grep -q 'not listed' "$t/o" || fail "empty SHA256SUMS must say not listed"
printf '%s  %s\n' "$sum" "$asset" > "$rel/SHA256SUMS"

printf 'tampered' >> "$rel/$asset"
rm -rf "$t/w"
! run x86_64 >"$t/o" 2>&1 || fail "a tampered tarball must fail closed"
[ ! -d "$t/w/work-src/llvm22-dev-x86_64" ] || fail "no tree from a tampered tarball"
! run ppc >"$t/o" 2>&1 || fail "an unknown ARCH must fail"
! run >"$t/o" 2>&1 || fail "no ARCH must fail"

sh -n "$ROOT/build/fetch-llvm-dev.sh" || fail "sh -n"
echo "OK fetch-llvm-dev-test"
