#!/bin/sh
# platform: macOS-only -- runs the installed arm64 zig-cross on Apple Silicon
#   usage: smoke-cross.sh VERSION [CASE...]     smokes the zig-cross installed at ZIG_PREFIX (default
#          /usr/local/mavergreen/zig-cross, with sdk109 beside it) on Apple Silicon: its manifest says VERSION,
#          zig version is UPSTREAM_VERSION, a host (arm64) hello.zig runs, tests/compat-matrix.sh passes with
#          it, and zig build of tests/fixtures/build-runner runs its build runner and generator as arm64 host
#          programs while the artifact it installs is a 10.9 x86_64 one. Every case runs unless CASEs are
#          named. Needs SHIPYARD_SCRIPTS or a shipyard install, for the compat guard. SKIP (77) on any host
#          but arm64, without VERSION, or when no case ran. The manifest case SKIPs only when ZIG_PREFIX is
#          given and its tree has no manifest (a stage). SMOKE_NO_SKIP=1 fails a case that would SKIP.
set -eu
[ "$(sysctl -n hw.optional.arm64 2>/dev/null || true)" = 1 ] \
  || { echo "SKIP smoke-cross: zig-cross runs only on Apple Silicon"; exit 77; }
HERE="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$HERE/.." && pwd)"
[ $# -ge 1 ] && [ -n "$1" ] || { echo "SKIP smoke-cross: usage: smoke-cross.sh VERSION [CASE...]"; exit 77; }
WANT="$1"; shift
P="${ZIG_PREFIX:-/usr/local/mavergreen/zig-cross}"
ZIG="$P/bin/zig"
[ -x "$ZIG" ] || { echo "FAIL smoke-cross: no zig at $ZIG"; exit 1; }
. "$ROOT/build/msc.sh"
T="$(mktemp -d "${TMPDIR:-/tmp}/smoke-cross.XXXXXX")"; trap 'rm -rf "$T"' EXIT
ZIG_GLOBAL_CACHE_DIR="$T/gcache"; ZIG_LOCAL_CACHE_DIR="$T/lcache"; export ZIG_GLOBAL_CACHE_DIR ZIG_LOCAL_CACHE_DIR
unset SDKROOT
cp "$HERE/fixtures/hello.zig" "$T/"
cp -R "$HERE/fixtures/build-runner" "$T/build-runner"

arch_of() { otool -hv "$1" | awk '$1 == "MH_MAGIC_64" { print $2; exit }'; }
minos_of() {
  otool -l "$1" | awk '
    $1 == "cmd" { lc = $2 }
    lc == "LC_BUILD_VERSION" && $1 == "minos" { print $2; exit }
    lc == "LC_VERSION_MIN_MACOSX" && $1 == "version" { print $2; exit }'
}

manifest_version() {
  m="$P/mavergreen.plist"
  if [ ! -f "$m" ]; then
    [ -n "${ZIG_PREFIX:-}" ] && { echo "SKIP manifest_version: $P has no mavergreen.plist (a stage, not an install)"; return 77; }
    echo "FAIL manifest_version: the installed zig-cross has no manifest at $m"; return 1
  fi
  got="$(awk '/<key>version<\/key>/ { getline; sub(/^[ \t]*<string>/, ""); sub(/<\/string>.*$/, ""); print; exit }' "$m")"
  [ "$got" = "$WANT" ] || { echo "FAIL manifest_version: $m says version '$got', this run installed '$WANT'"; return 1; }
}

zig_version() {
  want="$(tr -d ' \t\n' < "$ROOT/UPSTREAM_VERSION")"
  got="$("$ZIG" version)" || { echo "FAIL zig_version: $ZIG version failed"; return 1; }
  [ "$got" = "$want" ] || { echo "FAIL zig_version: zig version says '$got', UPSTREAM_VERSION is '$want'"; return 1; }
}

host_hello() {
  (cd "$T" && "$ZIG" build-exe -femit-bin=hello hello.zig) || { echo "FAIL host_hello: zig build-exe hello.zig for the host failed"; return 1; }
  [ "$(arch_of "$T/hello")" = ARM64 ] || { echo "FAIL host_hello: a host build must be arm64, got '$(arch_of "$T/hello")'"; return 1; }
  got="$("$T/hello")" || { echo "FAIL host_hello: the host hello exited non-zero"; return 1; }
  [ "$got" = hello ] || { echo "FAIL host_hello: the host hello printed '$got'"; return 1; }
}

compat_matrix() {
  sh "$HERE/compat-matrix.sh" "$ZIG" "$T/matrix" || { echo "FAIL compat_matrix: tests/compat-matrix.sh failed with $ZIG"; return 1; }
}

build_runner_on_arm64() {
  (cd "$T/build-runner" && "$ZIG" build -Dtarget=x86_64-macos --prefix "$T/build-runner/out") \
    || { echo "FAIL build_runner_on_arm64: zig build of tests/fixtures/build-runner (which runs gen.zig at build time) failed"; return 1; }
  g="$T/build-runner/out/bin/greeter"
  [ "$(arch_of "$g")" = X86_64 ] || { echo "FAIL build_runner_on_arm64: -Dtarget=x86_64-macos must install an x86_64 greeter, got '$(arch_of "$g")'"; return 1; }
  [ "$(minos_of "$g")" = 10.9 ] || { echo "FAIL build_runner_on_arm64: -Dtarget=x86_64-macos must give minos 10.9, got '$(minos_of "$g")'"; return 1; }
  MAVERICKS_ALLOW_ARCHS=x86_64 MAVERICKS_DEVIATIONS_ROOT="$ROOT" sh "$SHIPYARD_SCRIPTS/assert_binary_compatible.sh" "$g" \
    || { echo "FAIL build_runner_on_arm64: the installed greeter must pass the Mac OS X 10.9 compat guard"; return 1; }
  n=0
  for m in "$ZIG_LOCAL_CACHE_DIR"/o/*/gen "$ZIG_GLOBAL_CACHE_DIR"/o/*/maker; do
    [ -f "$m" ] || continue
    n=$((n + 1))
    [ "$(arch_of "$m")" = ARM64 ] || { echo "FAIL build_runner_on_arm64: $m must be an arm64 host program, got '$(arch_of "$m")'"; return 1; }
  done
  [ "$n" -ge 2 ] || { echo "FAIL build_runner_on_arm64: expected the build runner and gen in the caches, found $n of them"; return 1; }
}

[ $# -gt 0 ] || set -- manifest_version zig_version host_hello compat_matrix build_runner_on_arm64
failed=0; ran=0
for tcase in "$@"; do
  case "$tcase" in
    manifest_version|zig_version|host_hello|compat_matrix|build_runner_on_arm64) ;;
    *) echo "FAIL smoke-cross: no case '$tcase'"; failed=$((failed + 1)); continue ;;
  esac
  rc=0; "$tcase" || rc=$?
  case "$rc" in
    0) echo "ok $tcase"; ran=$((ran + 1)) ;;
    77) [ "${SMOKE_NO_SKIP:-}" = 1 ] && { echo "FAIL $tcase: skipped, and SMOKE_NO_SKIP=1"; failed=$((failed + 1)); } ;;
    *) failed=$((failed + 1)) ;;
  esac
done
[ "$failed" -eq 0 ] || exit 1
[ "$ran" -gt 0 ] || exit 77
echo "OK smoke-cross"
