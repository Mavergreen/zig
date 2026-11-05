#!/bin/sh
# platform: host-agnostic
#   usage: package-requires-test.sh     both pkgs require sdk109 (their SDKs link resolves into it) and never
#          ca-certs (optional at its contract path), and package_variant hands each required product to stage_product.
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$HERE/.." && pwd)"
fail() { echo "FAIL $1"; exit 1; }
[ -f "$ROOT/build/package-lib.sh" ] || fail "build/package-lib.sh is missing"
. "$ROOT/build/package-lib.sh"
command -v variant_requires >/dev/null 2>&1 || fail "package-lib.sh must define variant_requires"
for v in native cross; do
  [ "$(variant_requires "$v")" = sdk109 ] \
    || fail "the $v pkg requires exactly sdk109 (<prefix>/SDKs links to ../sdk109/SDKs): got '$(variant_requires "$v")'"
done
grep -q 'ca-certs' "$ROOT/build/package-lib.sh" && fail "ca-certs is optional at its contract path: package-lib.sh must never name it"
body="$(sed -n '/^package_variant() {/,/^}/p' "$ROOT/build/package-lib.sh")"
case "$body" in *'variant_requires "$v"'*'--requires'*) : ;; *) fail "package_variant passes each of variant_requires' products to stage_product as --requires" ;; esac
echo "OK package-requires-test"
