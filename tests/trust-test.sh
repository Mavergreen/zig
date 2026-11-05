#!/bin/sh
# platform: macOS-only -- runs the staged host zig's std against this Mac's keychain roots
#   usage: trust-test.sh     tests that the std of the zig build-host-zig.sh staged for this machine (ZIG names an
#          installed zig instead) unions the ca-certs bundle with the macOS keychain roots: a bundle's certs are
#          added, an absent bundle changes nothing, and a bad one is skipped with one warning, keychain roots kept.
#          Drives zig test tests/fixtures/trust_test.zig, which never reads the real ca-certs path. SKIP (77) when
#          nothing is staged.
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$HERE/.." && pwd)"
. "$ROOT/build/versions.sh"
. "$HERE/lib/staged-zig.sh"
staged_zig_init trust-test
ZIG="$(staged_zig_prefix "$T/mavergreen")"
cp "$HERE/fixtures/trust_test.zig" "$HERE/fixtures/trust-test-ca.pem" "$T/"

TESTS="keychain_roots bundle_adds_certs bundle_absent bundle_unreadable bundle_malformed_after_valid"
rc=0; (cd "$T" && "$ZIG" test trust_test.zig) >"$T/out" 2>&1 || rc=$?
if [ "$rc" -ne 0 ] || ! grep -q "^All $(echo $TESTS | wc -w | tr -d ' ') tests passed\.$" "$T/out"; then
  cat "$T/out"; echo "FAIL trust-test: zig test tests/fixtures/trust_test.zig must pass all of: $TESTS"; exit 1
fi
for t in $TESTS; do echo "ok $t"; done
n="$(grep -c '(warn): skipping the ca-certs bundle ' "$T/out" || true)"
[ "$n" -eq 2 ] || { cat "$T/out"; echo "FAIL bad_bundle_warns_once: the two bad bundles must give one warning each, got $n"; exit 1; }
echo "ok bad_bundle_warns_once"
echo "OK trust-test"
