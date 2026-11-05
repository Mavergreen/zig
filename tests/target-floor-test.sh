#!/bin/sh
# platform: macOS-only -- runs the staged host zig and reads its Mach-O output's load commands
#   usage: target-floor-test.sh     tests the zig build-host-zig.sh staged for this machine, laid out beside a 10.9
#          SDK by tests/lib/staged-zig.sh (ZIG names an installed zig instead); SKIP (77) when nothing is staged.
#          OTOOL and NM default to clang22's llvm-otool and llvm-nm on 10.9, to the system's elsewhere.
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$HERE/.." && pwd)"
. "$ROOT/build/versions.sh"
. "$HERE/lib/staged-zig.sh"
staged_zig_init target-floor-test
ZIG="$(staged_zig_prefix "$T/mavergreen")"
t="$T"
cp "$HERE/fixtures/hello.zig" "$HERE/fixtures/hello.c" "$t/"

cpu() { "$OTOOL" -hv "$1" | awk '$1 == "MH_MAGIC_64" { print $2; exit }'; }

default_floor() {
  (cd "$t" && "$ZIG" build-exe -target x86_64-macos -femit-bin=default hello.zig) || { echo "FAIL default_floor: zig build-exe -target x86_64-macos failed"; return 1; }
  f="$(floor "$t/default")"
  [ "$f" = 10.9 ] || { echo "FAIL default_floor: an x86_64-macos target with no version must get minos 10.9, got '$f'"; return 1; }
  (cd "$t" && "$ZIG" cc -target x86_64-macos -o default-cc hello.c) || { echo "FAIL default_floor: zig cc -target x86_64-macos failed"; return 1; }
  f="$(floor "$t/default-cc")"
  [ "$f" = 10.9 ] || { echo "FAIL default_floor: zig cc for x86_64-macos with no version must get minos 10.9, got '$f'"; return 1; }
}

explicit_newer_target() {
  (cd "$t" && "$ZIG" build-exe -target x86_64-macos.13.0 -femit-bin=newer hello.zig) || { echo "FAIL explicit_newer_target: zig build-exe -target x86_64-macos.13.0 failed"; return 1; }
  f="$(floor "$t/newer")"
  [ "$f" = 13.0 ] || { echo "FAIL explicit_newer_target: an explicit x86_64-macos.13.0 must keep minos 13.0, never a clamp to 10.9; got '$f'"; return 1; }
  if "$NM" -U "$t/newer" | awk '{ print $NF }' | grep -qx '___ulock_wait2'; then
    echo "FAIL explicit_newer_target: a 13.0 target must take ___ulock_wait2 from libSystem, not define a Recaulk copy"; return 1
  fi
  if "$NM" "$t/newer" | grep -q '___recaulk_'; then
    echo "FAIL explicit_newer_target: a 13.0 target is upstream's and must not link Recaulk"; return 1
  fi
  s="$(sdk "$t/newer")"
  [ "$s" != 10.9 ] || { echo "FAIL explicit_newer_target: a 13.0 target is upstream's and must not record the pinned 10.9 SDK"; return 1; }
}

host_untouched() {
  [ "$HOST" = arm64 ] || { echo "SKIP host_untouched: the native target is arm64 macOS only on Apple Silicon (this host is $HOST)"; return 77; }
  (cd "$t" && "$ZIG" build-exe -femit-bin=native hello.zig) || { echo "FAIL host_untouched: zig build-exe for the native target failed"; return 1; }
  arch="$(cpu "$t/native")"
  [ "$arch" = ARM64 ] || { echo "FAIL host_untouched: the native target on Apple Silicon must stay arm64, got '$arch'"; return 1; }
  f="$(floor "$t/native")"
  [ "${f%%.*}" = "${OSV%%.*}" ] || { echo "FAIL host_untouched: the native target must keep upstream's floor (this macOS, $OSV), got '$f'"; return 1; }
  if "$NM" "$t/native" | grep -q '___recaulk_'; then
    echo "FAIL host_untouched: the native target on Apple Silicon is upstream's and must not link Recaulk"; return 1
  fi
}

host_zig_pinned() {
  [ "$HOST" = arm64 ] || { echo "SKIP host_zig_pinned: zig-cross's arm64 bin/zig is built only on Apple Silicon (this host is $HOST)"; return 77; }
  f="$(floor "$ZIG")"; s="$(sdk "$ZIG")"
  [ "$f" = 11.0 ] && [ "$s" = 11.3 ] \
    || { echo "FAIL host_zig_pinned: zig-cross's arm64 bin/zig must record minos 11.0 and the pinned sdk 11.3, got minos '$f' sdk '$s'"; return 1; }
}

failed=0; ran=0
for tcase in default_floor explicit_newer_target host_untouched host_zig_pinned; do
  rc=0; "$tcase" || rc=$?
  case "$rc" in
    0) echo "ok $tcase"; ran=$((ran + 1)) ;;
    77) : ;;
    *) failed=$((failed + 1)) ;;
  esac
done
[ "$failed" -eq 0 ] || exit 1
[ "$ran" -gt 0 ] || exit 77
echo "OK target-floor-test"
