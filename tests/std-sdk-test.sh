#!/bin/sh
# platform: macOS-only -- runs the staged host zig's std, which asks this Mac for an SDK
#   usage: std-sdk-test.sh     tests that the std of the zig build-host-zig.sh staged for this machine (ZIG names
#          an installed zig instead) gives a Mac OS X 10.9 target the pinned 10.9 SDK, as the compiler does (0008):
#          std.zig.system.darwin.getSdk and std.zig.LibCInstallation.findNative return SDKROOT when it is set and
#          Longboat's /usr/local/mavergreen/sdk109 otherwise, never xcrun's SDK, while an x86_64-macos.13.0 target
#          stays upstream's. Drives zig test tests/fixtures/std_sdk_test.zig twice, without and with SDKROOT; the
#          run without SKIPs when Longboat's sdk109 is not installed. SKIP (77) when nothing is staged.
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$HERE/.." && pwd)"
. "$ROOT/build/versions.sh"
. "$HERE/lib/staged-zig.sh"
staged_zig_init std-sdk-test
ZIG="$(staged_zig_prefix "$T/mavergreen")"
PINNED=/usr/local/mavergreen/sdk109/SDKs/MacOSX10.9.sdk
TESTS="get_sdk_mavericks find_native_mavericks get_sdk_newer_is_upstreams"

run() { # NAME SDKROOT EXPECT
  d="$T/$1"; mkdir -p "$d"
  cp "$HERE/fixtures/std_sdk_test.zig" "$d/"
  printf '%s\n' "$2" > "$d/sdkroot.txt"; printf '%s\n' "$3" > "$d/expect.txt"
  rc=0
  if [ -n "$2" ]; then (cd "$d" && SDKROOT="$2" "$ZIG" test std_sdk_test.zig) >"$d/out" 2>&1 || rc=$?
  else (cd "$d" && "$ZIG" test std_sdk_test.zig) >"$d/out" 2>&1 || rc=$?; fi
  if [ "$rc" -ne 0 ] || ! grep -q "^All $(echo $TESTS | wc -w | tr -d ' ') tests passed\.$" "$d/out"; then
    cat "$d/out"; echo "FAIL $1: zig test tests/fixtures/std_sdk_test.zig must pass all of: $TESTS"; return 1
  fi
  for t in $TESTS; do echo "ok $1 $t"; done
}

failed=0
if [ -d "$PINNED" ]; then run pinned "" "$PINNED" || failed=1
else echo "SKIP pinned: Longboat's sdk109 is not installed at $PINNED"; fi
# SDKROOT must name an SDK the compiler can build this host's test runner with, so it is the pinned one by another path.
other="$T/other/MacOSX10.9.sdk"; mkdir -p "$T/other"; ln -s "$(staged_sdk109)" "$other"
run sdkroot "$other" "$other" || failed=1
[ "$failed" -eq 0 ] || exit 1
echo "OK std-sdk-test"
