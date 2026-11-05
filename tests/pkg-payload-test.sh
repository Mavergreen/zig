#!/bin/sh
# platform: macOS-only -- pkgutil, lsbom and PlistBuddy read the package
#   usage: pkg-payload-test.sh [zig|zig-cross]...     checks each named product's dist/<short>-<FULL>.pkg (default:
#          both; PKG_DIR overrides dist/): the product component's payload is only usr/local/mavergreen/<short>/,
#          the registry's updater app and its LaunchAgent; the manifest names the product and group zig; the
#          preinstall refuses a target volume without sdk109 and accepts one with it; dev.mavergreen.base is the
#          archive's first component. A product with no pkg is a SKIP line; SKIP (77) when no product was checked.
set -eu
# platform: Mac OS X 10.9's pkgutil has --expand but no --expand-full
case "$(sw_vers -productVersion)" in
  10.9|10.9.*) echo "SKIP pkg-payload-test: Mac OS X 10.9's pkgutil cannot --expand-full a payload"; exit 77 ;;
esac
HERE="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$HERE/.." && pwd)"
. "$ROOT/build/msc.sh"
D="${PKG_DIR:-$ROOT/dist}"
[ $# -gt 0 ] || set -- zig zig-cross
t="$(mktemp -d "${TMPDIR:-/tmp}/pkgpayload.XXXXXX")"; trap 'rm -rf "$t"' EXIT
name() { sh "$SHIPYARD_SCRIPTS/product-name.sh" "$1" "$2"; }
failed=0; n=0
fail() { echo "FAIL $short: $1"; failed=$((failed + 1)); }
allowed() {
  case "$1" in
    .|usr|usr/local|usr/local/mavergreen|Library|"Library/Application Support"|"Library/Application Support/Mavergreen"|Library/LaunchAgents) return 0 ;;
    "usr/local/mavergreen/$short"|"usr/local/mavergreen/$short/"*|"$app"|"$app/"*|"Library/LaunchAgents/$label.plist") return 0 ;;
  esac
  return 1
}

check_pkg() {
  pkg="$1"
  id="$(name identifier "$short")"; app="$(name updater-app "$short")"; label="$(name agent-label "$short")"
  rm -rf "$t/x" "$t/f" "$t/vol"
  pkgutil --expand "$pkg" "$t/x"
  first="$(sed -n '/<choices-outline>/,/<\/choices-outline>/s/.*<line choice="\([^"]*\)"\/>.*/\1/p' "$t/x/Distribution" | head -n 1)"
  [ "$first" = dev.mavergreen.base ] || fail "dev.mavergreen.base must be the first component, not '$first'"
  comp=""
  for c in "$t/x"/*.pkg; do
    grep -q "identifier=\"$id\"" "$c/PackageInfo" 2>/dev/null && comp="$(basename "$c")"
  done
  [ -n "$comp" ] || { fail "no component with identifier $id in $(basename "$pkg")"; return; }
  lsbom -s "$t/x/$comp/Bom" | sed 's#^\./##' > "$t/list"
  while IFS= read -r p; do allowed "$p" || printf '%s\n' "$p"; done < "$t/list" > "$t/stray"
  stray="$(cat "$t/stray")"
  [ -z "$stray" ] || fail "the payload must hold only usr/local/mavergreen/$short/, $app and its LaunchAgent; it also has: $(printf '%s\n' "$stray" | head -n 5 | tr '\n' ' ')"
  for p in "usr/local/mavergreen/$short/mavergreen.plist" "usr/local/mavergreen/$short/bin/zig" "usr/local/mavergreen/$short/lib/zig/std" \
    "usr/local/mavergreen/$short/lib/mavergreen/x86_64-macos/librecaulk.a" "usr/local/mavergreen/$short/lib/mavergreen/x86_64-macos/libc++.a" \
    "usr/local/mavergreen/$short/lib/mavergreen/include/c++/v1" "usr/local/mavergreen/$short/lib/mavergreen/include/recaulk" \
    "usr/local/mavergreen/$short/SDKs" "$app/Contents/Info.plist" "Library/LaunchAgents/$label.plist"; do
    grep -qxF "$p" "$t/list" || fail "the payload has no $p"
  done
  pkgutil --expand-full "$pkg" "$t/f" >/dev/null
  pl="$t/f/$comp/Payload"
  l="$(readlink "$pl/usr/local/mavergreen/$short/SDKs" 2>/dev/null || true)"
  [ "$l" = ../sdk109/SDKs ] || fail "usr/local/mavergreen/$short/SDKs must link to ../sdk109/SDKs, not '$l'"
  mf="$pl/usr/local/mavergreen/$short/mavergreen.plist"
  if [ -f "$mf" ]; then
    for kv in "product=$short" "group=zig" "identifier=$id" "name=Zig for Mavericks"; do
      got="$(/usr/libexec/PlistBuddy -c "Print :${kv%%=*}" "$mf" 2>/dev/null || true)"
      [ "$got" = "${kv#*=}" ] || fail "the manifest's ${kv%%=*} must be '${kv#*=}', not '$got'"
    done
  fi
  pre="$t/f/$comp/Scripts/preinstall"
  [ -f "$pre" ] || { fail "no preinstall in $comp"; return; }
  mkdir -p "$t/vol/usr/local/mavergreen"
  if sh "$pre" "$pkg" "$t/vol/" "$t/vol/" > "$t/pre.out" 2>&1; then
    fail "the preinstall must refuse a volume without sdk109"
  else
    grep -q 'needs sdk109 installed first' "$t/pre.out" || fail "the preinstall's refusal must name sdk109: $(cat "$t/pre.out")"
  fi
  mkdir -p "$t/vol/usr/local/mavergreen/sdk109"; : > "$t/vol/usr/local/mavergreen/sdk109/mavergreen.plist"
  sh "$pre" "$pkg" "$t/vol/" "$t/vol/" > "$t/pre.out" 2>&1 || fail "the preinstall must accept a volume with sdk109: $(cat "$t/pre.out")"
}

for short in "$@"; do
  case "$short" in zig|zig-cross) ;; *) echo "usage: pkg-payload-test.sh [zig|zig-cross]..." >&2; exit 2 ;; esac
  pkg=""
  for p in "$D/$short"-[0-9]*.pkg; do [ -f "$p" ] && pkg="$p"; done
  [ -n "$pkg" ] || { echo "SKIP $short: no $D/$short-<version>.pkg (build/package-$( [ "$short" = zig ] && echo native || echo cross )-pkg.sh)"; continue; }
  n=$((n + 1)); before="$failed"
  check_pkg "$pkg"
  [ "$failed" -eq "$before" ] && echo "ok $short $(basename "$pkg")"
done
[ "$failed" -eq 0 ] || exit 1
[ "$n" -gt 0 ] || { echo "SKIP pkg-payload-test: no pkg built"; exit 77; }
echo "OK pkg-payload-test ($n)"
