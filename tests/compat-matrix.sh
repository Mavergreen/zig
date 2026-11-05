#!/bin/sh
# platform: macOS-only -- runs a zig for x86_64-macos and shipyard's Mach-O compat guard on what it builds
#   usage: compat-matrix.sh [ZIG OUTDIR]     builds every tests/fixtures/matrix fixture for x86_64-macos with ZIG
#          (.zig with build-exe, .c with zig cc, .cpp with zig c++) into OUTDIR, one program per fixture named
#          for it, and runs assert_binary_compatible.sh on each. Exits 0 only if every fixture builds and passes.
#          Each program exits 0 when its feature works on the Mac it runs on; net and http need the internet,
#          and http on 10.9 needs Mavergreen's ca-certs, whose roots the 10.9 keychain lacks. OUTDIR is what
#          the 10.9 VM runs. With no arguments (as run-repo-tests.sh runs it), builds with the zig
#          build-host-zig.sh staged for this machine (ZIG names an installed zig instead) into a temporary
#          OUTDIR; SKIP (77) when nothing is staged.
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$HERE/.." && pwd)"
case "$#" in
  2)
    case "$1" in /*) ZIG="$1" ;; *) ZIG="$(pwd)/$1" ;; esac
    mkdir -p "$2"; OUT="$(cd "$2" && pwd)"
    T="$(mktemp -d "${TMPDIR:-/tmp}/compat-matrix.XXXXXX")"; trap 'rm -rf "$T"' EXIT
    ZIG_GLOBAL_CACHE_DIR="$T/gcache"; ZIG_LOCAL_CACHE_DIR="$T/lcache"; export ZIG_GLOBAL_CACHE_DIR ZIG_LOCAL_CACHE_DIR
    unset SDKROOT ;;
  0)
    . "$ROOT/build/versions.sh"
    . "$HERE/lib/staged-zig.sh"
    staged_zig_init compat-matrix
    ZIG="$(staged_zig_prefix "$T/mavergreen")"
    OUT="$T/out"; mkdir -p "$OUT" ;;
  *) echo "usage: compat-matrix.sh [ZIG OUTDIR]" >&2; exit 2 ;;
esac
[ -x "$ZIG" ] || { echo "FAIL compat-matrix: no zig at $ZIG"; exit 1; }
. "$ROOT/build/msc.sh"
FIX="$HERE/fixtures/matrix"

build() {
  case "$1" in
    *.zig) (cd "$T" && "$ZIG" build-exe -target x86_64-macos -femit-bin="$OUT/$2" "$FIX/$1") ;;
    *.c) "$ZIG" cc -target x86_64-macos -o "$OUT/$2" "$FIX/$1" ;;
    *.cpp) "$ZIG" c++ -target x86_64-macos -o "$OUT/$2" "$FIX/$1" ;;
  esac
}

failed=0; ran=0
for f in "$FIX"/*.zig "$FIX"/*.c "$FIX"/*.cpp; do
  src="$(basename "$f")"; name="${src%.*}"
  ran=$((ran + 1))
  if ! build "$src" "$name"; then
    echo "FAIL $name: zig could not build tests/fixtures/matrix/$src for x86_64-macos"; failed=$((failed + 1)); continue
  fi
  if MAVERICKS_ALLOW_ARCHS=x86_64 MAVERICKS_DEVIATIONS_ROOT="$ROOT" sh "$SHIPYARD_SCRIPTS/assert_binary_compatible.sh" "$OUT/$name"; then
    echo "ok $name"
  else
    echo "FAIL $name: $OUT/$name must pass the Mac OS X 10.9 compat guard"; failed=$((failed + 1))
  fi
done
[ "$ran" -gt 0 ] || { echo "FAIL compat-matrix: no fixtures in $FIX"; exit 1; }
[ "$failed" -eq 0 ] || exit 1
echo "OK compat-matrix"
