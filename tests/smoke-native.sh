#!/bin/sh
# platform: macOS-only -- runs in the 10.9 guest: the installed x86_64 zig, its programs, and clang22
#   usage: smoke-native.sh VERSION [CASE...]     smokes the zig installed at ZIG_PREFIX (default
#          /usr/local/mavergreen/zig, with sdk109 beside it): its manifest says VERSION, zig version is
#          UPSTREAM_VERSION, it builds and runs hello.zig, hello.c, cxx_throw.cpp, cxx_cout_ctor.cpp and
#          threads.zig (the native hello.zig, below macOS 11, passing the 10.9 compat guard), zig build of tests/fixtures/fetch-project fetches its dependency over HTTPS, and
#          clang22 (CLANG22, default /usr/local/mavergreen/clang22) links a Zig static library. Every case
#          runs unless CASEs are named. SKIP (77) without VERSION, or when no case ran.
#          fetch_project passes with the ca-certs bundle when it is installed; without it, success or a TLS
#          error is a pass and a crash is not. ZIG_SMOKE_CA_CERTS=absent|present asserts which it is.
#          The manifest case SKIPs only when ZIG_PREFIX is given and its tree has no manifest (a stage).
#          SMOKE_NO_SKIP=1 fails a case that would SKIP.
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$HERE/.." && pwd)"
[ $# -ge 1 ] && [ -n "$1" ] || { echo "SKIP smoke-native: usage: smoke-native.sh VERSION [CASE...]"; exit 77; }
WANT="$1"; shift
P="${ZIG_PREFIX:-/usr/local/mavergreen/zig}"
ZIG="$P/bin/zig"
CLANG22="${CLANG22:-/usr/local/mavergreen/clang22}"
CA_BUNDLE=/usr/local/mavergreen/ca-certs/etc/openssl/certs/ca-certificates.crt
[ -x "$ZIG" ] || { echo "FAIL smoke-native: no zig at $ZIG"; exit 1; }
T="$(mktemp -d "${TMPDIR:-/tmp}/smoke-native.XXXXXX")"; trap 'rm -rf "$T"' EXIT
ZIG_GLOBAL_CACHE_DIR="$T/gcache"; ZIG_LOCAL_CACHE_DIR="$T/lcache"; export ZIG_GLOBAL_CACHE_DIR ZIG_LOCAL_CACHE_DIR
unset SDKROOT
. "$ROOT/build/msc.sh"
OSV="$(sw_vers -productVersion)"
case "$OSV" in
  # platform: 10.9's otool, lipo, nm and strings are Command Line Tools stubs; clang22's llvm-* read the same
  10.9|10.9.*) : "${OTOOL:=$CLANG22/bin/llvm-otool}" "${NM:=$CLANG22/bin/llvm-nm}" "${LIPO:=$CLANG22/bin/llvm-lipo}" "${STRINGS:=$CLANG22/bin/llvm-strings}" ;;
  *) : "${OTOOL:=otool}" "${NM:=nm}" "${LIPO:=lipo}" "${STRINGS:=strings}" ;;
esac
export OTOOL NM LIPO STRINGS
cp "$HERE/fixtures/hello.zig" "$HERE/fixtures/hello.c" "$HERE/fixtures/cxx_throw.cpp" "$HERE/fixtures/cxx_cout_ctor.cpp" \
  "$HERE/fixtures/threads.zig" "$HERE/fixtures/lib.zig" "$HERE/fixtures/uselib.c" "$T/"
mkdir "$T/fetch-project"
cp "$HERE/fixtures/fetch-project/build.zig" "$HERE/fixtures/fetch-project/build.zig.zon" "$T/fetch-project/"

manifest_version() {
  m="$P/mavergreen.plist"
  if [ ! -f "$m" ]; then
    [ -n "${ZIG_PREFIX:-}" ] && { echo "SKIP manifest_version: $P has no mavergreen.plist (a stage, not an install)"; return 77; }
    echo "FAIL manifest_version: the installed zig has no manifest at $m"; return 1
  fi
  got="$(awk '/<key>version<\/key>/ { getline; sub(/^[ \t]*<string>/, ""); sub(/<\/string>.*$/, ""); print; exit }' "$m")"
  [ "$got" = "$WANT" ] || { echo "FAIL manifest_version: $m says version '$got', this run installed '$WANT'"; return 1; }
}

zig_version() {
  want="$(tr -d ' \t\n' < "$ROOT/UPSTREAM_VERSION")"
  got="$("$ZIG" version)" || { echo "FAIL zig_version: $ZIG version failed"; return 1; }
  [ "$got" = "$want" ] || { echo "FAIL zig_version: zig version says '$got', UPSTREAM_VERSION is '$want'"; return 1; }
}

runs() {
  _r_case="$1"; _r_prog="$2"; _r_want="$3"
  _r_got="$(cd "$T" && "./$_r_prog")" || { echo "FAIL $_r_case: $_r_prog exited non-zero"; return 1; }
  [ "$_r_got" = "$_r_want" ] || { echo "FAIL $_r_case: $_r_prog printed '$_r_got', wanted '$_r_want'"; return 1; }
}

hello_zig() {
  (cd "$T" && "$ZIG" build-exe -femit-bin=hello-zig hello.zig) || { echo "FAIL hello_zig: zig build-exe hello.zig failed"; return 1; }
  runs hello_zig hello-zig hello || return 1
  case "$OSV" in 10.*) ;; *) echo "hello_zig: the native target is a Mac OS X 10.9 target only below macOS 11 (this is $OSV); not guarded"; return 0 ;; esac
  MAVERICKS_ALLOW_ARCHS=x86_64 MAVERICKS_DEVIATIONS_ROOT="$ROOT" sh "$SHIPYARD_SCRIPTS/assert_binary_compatible.sh" "$T/hello-zig" \
    || { echo "FAIL hello_zig: a native build below macOS 11 is x86_64-macos.10.9 and must pass the Mac OS X 10.9 compat guard"; return 1; }
}

hello_c() {
  (cd "$T" && "$ZIG" cc -o hello-c hello.c) || { echo "FAIL hello_c: zig cc hello.c failed"; return 1; }
  runs hello_c hello-c hello
}

cxx_throw() {
  (cd "$T" && "$ZIG" c++ -o cxx-throw cxx_throw.cpp) || { echo "FAIL cxx_throw: zig c++ cxx_throw.cpp failed"; return 1; }
  runs cxx_throw cxx-throw "caught thrown"
}

cxx_cout_ctor() {
  (cd "$T" && "$ZIG" c++ -o cxx-cout-ctor cxx_cout_ctor.cpp) || { echo "FAIL cxx_cout_ctor: zig c++ cxx_cout_ctor.cpp failed"; return 1; }
  runs cxx_cout_ctor cxx-cout-ctor "constructed
main"
}

threads() {
  (cd "$T" && "$ZIG" build-exe -femit-bin=threads threads.zig) || { echo "FAIL threads: zig build-exe threads.zig failed"; return 1; }
  runs threads threads threads
}

fetch_project() {
  if [ -f "$CA_BUNDLE" ]; then have=present; else have=absent; fi
  case "${ZIG_SMOKE_CA_CERTS:-$have}" in
    "$have") ;;
    absent|present) echo "FAIL fetch_project: ZIG_SMOKE_CA_CERTS=$ZIG_SMOKE_CA_CERTS, but the ca-certs bundle is $have at $CA_BUNDLE"; return 1 ;;
    *) echo "FAIL fetch_project: ZIG_SMOKE_CA_CERTS must be absent or present (got '$ZIG_SMOKE_CA_CERTS')"; return 1 ;;
  esac
  rm -rf "$ZIG_GLOBAL_CACHE_DIR/p" "$T/fetch-project/out"
  s=0; (cd "$T/fetch-project" && "$ZIG" build --prefix "$T/fetch-project/out") > "$T/fetch.log" 2>&1 || s=$?
  if [ "$s" -eq 0 ]; then
    grep -q 'jsmn_parse' "$T/fetch-project/out/include/jsmn.h" 2>/dev/null \
      || { echo "FAIL fetch_project: zig build succeeded but installed no jsmn.h from the fetched dependency"; return 1; }
    echo "fetch_project: fetched over HTTPS with the ca-certs bundle $have"
    return 0
  fi
  if [ "$s" -gt 128 ] || grep -Eqi 'panic|segmentation fault|illegal instruction|bus error|abort trap' "$T/fetch.log"; then
    echo "FAIL fetch_project: zig build crashed (exit $s):"; sed 's/^/  /' "$T/fetch.log"; return 1
  fi
  if [ "$have" = present ]; then
    echo "FAIL fetch_project: with the ca-certs bundle installed, zig build must fetch its dependency (exit $s):"; sed 's/^/  /' "$T/fetch.log"; return 1
  fi
  tls_error='error: .*(Tls|Certificate)'
  grep -Eq "$tls_error" "$T/fetch.log" \
    || { echo "FAIL fetch_project: without the ca-certs bundle, zig build may fail only with a TLS or certificate error, such as 'error: server connection failed: TlsInitializationFailed' (exit $s):"; sed 's/^/  /' "$T/fetch.log"; return 1; }
  echo "fetch_project: without the ca-certs bundle, zig build failed cleanly on TLS: $(grep -E "$tls_error" "$T/fetch.log" | head -n 1)"
}

uselib_clang22() {
  [ -x "$CLANG22/bin/clang" ] || { echo "SKIP uselib_clang22: no clang22 at $CLANG22/bin/clang"; return 77; }
  (cd "$T" && "$ZIG" build-lib -static -target x86_64-macos -OReleaseSmall -fcompiler-rt -femit-bin=liblib.a lib.zig) \
    || { echo "FAIL uselib_clang22: zig build-lib -static lib.zig failed"; return 1; }
  (cd "$T" && "$CLANG22/bin/clang" -target x86_64-apple-macos10.9 -o uselib uselib.c liblib.a) \
    || { echo "FAIL uselib_clang22: clang22 could not link the Zig static library"; return 1; }
  runs uselib_clang22 uselib "5 1"
}

[ $# -gt 0 ] || set -- manifest_version zig_version hello_zig hello_c cxx_throw cxx_cout_ctor threads fetch_project uselib_clang22
failed=0; ran=0
for tcase in "$@"; do
  case "$tcase" in
    manifest_version|zig_version|hello_zig|hello_c|cxx_throw|cxx_cout_ctor|threads|fetch_project|uselib_clang22) ;;
    *) echo "FAIL smoke-native: no case '$tcase'"; failed=$((failed + 1)); continue ;;
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
echo "OK smoke-native"
