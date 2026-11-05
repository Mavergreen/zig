#!/bin/sh
# platform: macOS-only -- reads the Mach-O files of the zig build-native.sh staged
#   usage: native-stage-test.sh [PREFIX]     tests the 10.9-hosted zig build-native.sh staged at PREFIX (default
#          $NATIVE_STAGE_ROOT$NATIVE_PREFIX): bin/zig is x86_64 only, every Mach-O under PREFIX passes the compat guard
#          (MAVERICKS_ALLOW_ARCHS=x86_64), the in-tree layout is there, SDKs links to ../sdk109/SDKs, and
#          lib/mavergreen/BUILD-INFO says build-native.sh built it. On x86_64 build-host-zig.sh stages its host zig at
#          the same prefix, without that BUILD-INFO, and this test fails it. SKIP (77) when nothing is staged.
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$HERE/.." && pwd)"
. "$ROOT/build/versions.sh"
. "$ROOT/build/msc.sh"; . "$ROOT/build/lib-zig.sh"
[ $# -le 1 ] || { echo "usage: native-stage-test.sh [PREFIX]" >&2; exit 2; }
P="${1:-$NATIVE_STAGE_ROOT$NATIVE_PREFIX}"
[ -e "$P/bin/zig" ] || { echo "SKIP native-stage-test: no staged zig at $P/bin/zig (run build/build-native.sh)"; exit 77; }
case "$(sw_vers -productVersion)" in
  10.9|10.9.*)
    _llvm=/usr/local/mavergreen/clang22/bin
    : "${OTOOL:=$_llvm/llvm-otool}" "${NM:=$_llvm/llvm-nm}" "${LIPO:=$_llvm/llvm-lipo}" "${STRINGS:=$_llvm/llvm-strings}" ;;
  *) : "${OTOOL:=otool}" "${NM:=nm}" "${LIPO:=lipo}" "${STRINGS:=strings}" ;;
esac
export OTOOL NM LIPO STRINGS

guard() {
  MAVERICKS_ALLOW_ARCHS=x86_64 MAVERICKS_DEVIATIONS_ROOT="$ROOT" sh "$SHIPYARD_SCRIPTS/assert_binary_compatible.sh" "$@"
}
is_macho() {
  case "$(od -An -tx1 -N4 "$1" 2>/dev/null | tr -d ' \n')" in
    cffaedfe|cefaedfe|cafebabe|feedfacf|feedface) return 0 ;;
    *) return 1 ;;
  esac
}

built_by_build_native() {
  bi="$P/lib/mavergreen/BUILD-INFO"
  [ -f "$bi" ] || { echo "FAIL built_by_build_native: $P holds a zig build-native.sh did not build (no lib/mavergreen/BUILD-INFO); run build/build-native.sh"; return 1; }
  grep -qxF "$(build_info native)" "$bi" \
    || { echo "FAIL built_by_build_native: $bi must say $(build_info native); it says: $(cat "$bi")"; return 1; }
}

zig_x86_64_only() {
  a="$("$LIPO" -archs "$P/bin/zig" 2>/dev/null)" || { echo "FAIL zig_x86_64_only: $LIPO cannot read $P/bin/zig"; return 1; }
  # shellcheck disable=SC2086
  a="$(echo $a)"
  [ "$a" = x86_64 ] || { echo "FAIL zig_x86_64_only: bin/zig must be x86_64 only, it is: $a"; return 1; }
}

guard_every_macho() {
  n=0; bad=0; list="$(mktemp "${TMPDIR:-/tmp}/native-stage-test.XXXXXX")"
  find "$P" -type f > "$list"
  while IFS= read -r f; do
    is_macho "$f" || continue
    n=$((n + 1))
    guard "$f" || { echo "FAIL guard_every_macho: $f does not pass the compat guard"; bad=1; }
  done < "$list"
  rm -f "$list"
  [ "$n" -gt 0 ] || { echo "FAIL guard_every_macho: no Mach-O under $P"; return 1; }
  [ "$bad" -eq 0 ]
}

layout() {
  for p in bin/zig lib/zig/std lib/mavergreen/x86_64-macos/librecaulk.a lib/mavergreen/x86_64-macos/libc++.a \
    lib/mavergreen/include/c++/v1 lib/mavergreen/include/recaulk; do
    [ -e "$P/$p" ] || { echo "FAIL layout: $P/$p is missing"; return 1; }
  done
}

sdks_link() {
  [ -L "$P/SDKs" ] || { echo "FAIL sdks_link: $P/SDKs must be a symbolic link"; return 1; }
  l="$(readlink "$P/SDKs")"
  [ "$l" = ../sdk109/SDKs ] || { echo "FAIL sdks_link: $P/SDKs must link to ../sdk109/SDKs, not '$l'"; return 1; }
}

failed=0
for tcase in built_by_build_native zig_x86_64_only guard_every_macho layout sdks_link; do
  if "$tcase"; then echo "ok $tcase"; else failed=$((failed + 1)); fi
done
[ "$failed" -eq 0 ] || exit 1
echo "OK native-stage-test"
