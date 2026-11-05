#!/bin/sh
# platform: macOS-only -- runs the staged host zig and clang22, and reads their Mach-O output
#   usage: link-test.sh     tests what the zig build-host-zig.sh staged for this machine (ZIG names an installed
#          zig instead) links into a Mac OS X 10.9 program: Recaulk at the tail, clang-22's libc++ on the system's
#          libc++abi, only libSystem for a trivial program whether the SDK's stubs are binary or .tbd (the pinned SDK
#          stubified by clang22's llvm-readtapi into the test's own directory, never into its source, and
#          skipped when that SDK's libSystem is no binary stub), a Zig static library that clang22 links, and a zig build whose build runner and generator are
#          host programs. SKIP (77) when nothing is staged. CLANG22 is the clang22 toolchain that links a Zig static
#          library: the installed /usr/local/mavergreen/clang22 on 10.9; on Apple Silicon, clang22-cross at
#          components/clang/version. Running the outputs is the 10.9 VM's job, not this test's.
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$HERE/.." && pwd)"
. "$ROOT/build/versions.sh"
. "$HERE/lib/staged-zig.sh"
staged_zig_init link-test
. "$ROOT/build/msc.sh"
ZIG="$(staged_zig_prefix "$T/mavergreen")"
cp "$HERE/fixtures/threads.zig" "$HERE/fixtures/hello.zig" "$HERE/fixtures/cxx_throw.cpp" "$HERE/fixtures/cxx_cout_ctor.cpp" \
  "$HERE/fixtures/lib.zig" "$HERE/fixtures/uselib.c" "$HERE/fixtures/hello.c" "$T/"
cp -R "$HERE/fixtures/build-runner" "$T/build-runner"

guard() {
  MAVERICKS_ALLOW_ARCHS=x86_64 MAVERICKS_DEVIATIONS_ROOT="$ROOT" sh "$SHIPYARD_SCRIPTS/assert_binary_compatible.sh" "$@"
}
defines() { "$NM" -U "$1" | awk '{ print $NF }' | grep -qx "$2"; }
imports() { "$NM" -u "$1" | awk '{ print $NF }' | grep -qx "$2"; }

recaulk_tail() {
  (cd "$T" && "$ZIG" build-exe -target x86_64-macos -femit-bin=threads threads.zig) \
    || { echo "FAIL recaulk_tail: zig build-exe -target x86_64-macos threads.zig failed"; return 1; }
  guard "$T/threads" || { echo "FAIL recaulk_tail: a Mac OS X 10.9 program must pass the compat guard"; return 1; }
  defines "$T/threads" ___ulock_wait \
    || { echo "FAIL recaulk_tail: std's futex below 11.0 (___ulock_wait; ___ulock_wait2 is 11.0's, std/Io/Threaded.zig) must come from librecaulk.a, linked at the tail"; return 1; }
  if imports "$T/threads" ___ulock_wait; then
    echo "FAIL recaulk_tail: ___ulock_wait must not be imported from libSystem, which 10.9's lacks"; return 1
  fi
}

clang22_for_host() {
  if [ "$HOST" = x86_64 ]; then echo "${CLANG22:-/usr/local/mavergreen/clang22}"; return; fi
  if [ -n "${CLANG22:-}" ]; then echo "$CLANG22"; return; fi
  # spec: github.com/Mavergreen/clang-22 releases -- the pkgs are mavericks-clang-22-{native,cross}-<version>.pkg
  sh "$SHIPYARD_SCRIPTS/fetch_product_pkg.sh" --asset "mavericks-clang-22-cross-$CLANG_VERSION.pkg" \
    clang22-cross "$CLANG_VERSION" "$T/mavergreen/clang22-cross"
}

dylibs() { "$OTOOL" -L "$1" | awk 'NR > 1 { print $1 }'; }

trivial_load_commands() {
  printf 'int main(void) { return 0; }\n' > "$T/empty.c"
  (cd "$T" && "$ZIG" cc -target x86_64-macos -o empty empty.c) \
    || { echo "FAIL trivial_load_commands: zig cc -target x86_64-macos of an empty main failed"; return 1; }
  (cd "$T" && "$ZIG" build-exe -target x86_64-macos -femit-bin=hello hello.zig) \
    || { echo "FAIL trivial_load_commands: zig build-exe -target x86_64-macos hello.zig failed"; return 1; }
  for p in empty hello; do
    got="$(dylibs "$T/$p" | tr '\n' ' ')"
    [ "$got" = "/usr/lib/libSystem.B.dylib " ] \
      || { echo "FAIL trivial_load_commands: a trivial 10.9 program ($p) must load only libSystem, as clang22's does; it loads: $got"; return 1; }
  done
  c22="$(clang22_for_host)" || { echo "FAIL trivial_load_commands: no clang22 toolchain"; return 1; }
  (cd "$T" && "$c22/bin/clang" -target x86_64-apple-macos10.9 -o empty-clang22 empty.c) \
    || { echo "FAIL trivial_load_commands: clang22 could not link an empty main"; return 1; }
  [ "$(dylibs "$T/empty")" = "$(dylibs "$T/empty-clang22")" ] \
    || { echo "FAIL trivial_load_commands: zig cc and clang22 must give an empty main the same libraries; clang22's: $(dylibs "$T/empty-clang22" | tr '\n' ' ')"; return 1; }
}

tbd_sdk() {
  _ts_rt="$1"; _ts_sdk="$2"; _ts_out="$3"
  "$OTOOL" -hv "$_ts_sdk/usr/lib/libSystem.B.dylib" 2>/dev/null | grep -q DYLIB_STUB \
    || { echo "$_ts_sdk/usr/lib/libSystem.B.dylib is not a binary stub, so no .tbd SDK is made from that SDK"; return 77; }
  rm -rf "$_ts_out"
  mkdir -p "$_ts_out/usr/lib/system"
  for _ts_e in "$_ts_sdk"/*; do [ "${_ts_e##*/}" = usr ] || ln -s "$_ts_e" "$_ts_out/"; done
  for _ts_e in "$_ts_sdk"/usr/*; do [ "${_ts_e##*/}" = lib ] || ln -s "$_ts_e" "$_ts_out/usr/"; done
  for _ts_e in "$_ts_sdk"/usr/lib/*; do
    case "${_ts_e##*/}" in system|libSystem*) ;; *) ln -s "$_ts_e" "$_ts_out/usr/lib/" ;; esac
  done
  tbd_stubify "$_ts_rt" "$_ts_sdk/usr/lib/libSystem.B.dylib" "$_ts_out/usr/lib/libSystem.B.tbd" || return 1
  ln -s libSystem.B.tbd "$_ts_out/usr/lib/libSystem.tbd"
  for _ts_e in "$_ts_sdk"/usr/lib/system/*; do
    case "$_ts_e" in
      *.tbd) ;;
      *.dylib) [ -L "$_ts_e" ] || tbd_stubify "$_ts_rt" "$_ts_e" "$_ts_out/usr/lib/system/$(basename "$_ts_e" .dylib).tbd" || return 1 ;;
      *) ln -s "$_ts_e" "$_ts_out/usr/lib/system/" ;;
    esac
  done
}

tbd_stubify() {
  if [ -e "$3" ] || [ -L "$3" ]; then echo "tbd_sdk: $3 already exists; it is written only fresh"; return 1; fi
  "$1" -stubify --filetype=tbd-v4 "$2" -o "$3"
}

tbd_sdk_load_commands() {
  c22="$(clang22_for_host)" || { echo "FAIL tbd_sdk_load_commands: no clang22 toolchain"; return 1; }
  [ -x "$c22/bin/llvm-readtapi" ] || { echo "FAIL tbd_sdk_load_commands: no llvm-readtapi at $c22/bin"; return 1; }
  pin="$(staged_sdk109)" || { echo "FAIL tbd_sdk_load_commands: no pinned Mac OS X 10.9 SDK"; return 1; }
  made=0; why="$(tbd_sdk "$c22/bin/llvm-readtapi" "$pin" "$T/tbd-sdk" 2>&1)" || made=$?
  case "$made" in
    0) ;;
    77) echo "SKIP tbd_sdk_load_commands: $why"; return 77 ;;
    *) echo "FAIL tbd_sdk_load_commands: could not make a .tbd 10.9 SDK from the pinned one with llvm-readtapi -stubify: $why"; return 1 ;;
  esac
  why="$(tbd_sdk "$c22/bin/llvm-readtapi" "$pin" "$T/tbd-sdk" 2>&1)" \
    || { echo "FAIL tbd_sdk_load_commands: making the .tbd SDK again in the same place must start afresh: $why"; return 1; }
  [ ! -e "$T/tbd-sdk/usr/lib/system/libdyld.dylib" ] && grep -q '^parent-umbrella:' "$T/tbd-sdk/usr/lib/system/libdyld.tbd" \
    || { echo "FAIL tbd_sdk_load_commands: the .tbd SDK's libdyld must be a .tbd naming its parent umbrella, and no binary stub"; return 1; }
  printf 'int main(void) { return 0; }\n' > "$T/tbd-empty.c"
  (cd "$T" && SDKROOT="$T/tbd-sdk" "$ZIG" cc -target x86_64-macos -o tbd-empty tbd-empty.c) \
    || { echo "FAIL tbd_sdk_load_commands: zig cc of an empty main against the .tbd SDK failed"; return 1; }
  (cd "$T" && SDKROOT="$T/tbd-sdk" "$ZIG" cc -target x86_64-macos -o tbd-hello-c hello.c) \
    || { echo "FAIL tbd_sdk_load_commands: zig cc hello.c against the .tbd SDK failed"; return 1; }
  (cd "$T" && SDKROOT="$T/tbd-sdk" "$ZIG" build-exe -target x86_64-macos -femit-bin=tbd-hello hello.zig) \
    || { echo "FAIL tbd_sdk_load_commands: zig build-exe hello.zig against the .tbd SDK failed"; return 1; }
  for p in tbd-empty tbd-hello-c tbd-hello; do
    got="$(dylibs "$T/$p" | tr '\n' ' ')"
    [ "$got" = "/usr/lib/libSystem.B.dylib " ] \
      || { echo "FAIL tbd_sdk_load_commands: a trivial 10.9 program ($p) linked against a .tbd SDK must load only libSystem, its sub-libraries' parent umbrella; it loads: $got"; return 1; }
  done
}

tbd_sdk_source_untouched() {
  c22="$(clang22_for_host)" || { echo "FAIL tbd_sdk_source_untouched: no clang22 toolchain"; return 1; }
  rt="$c22/bin/llvm-readtapi"
  pin="$(staged_sdk109)" || { echo "FAIL tbd_sdk_source_untouched: no pinned Mac OS X 10.9 SDK"; return 1; }
  src="$T/tbd-form-sdk"; rm -rf "$src"; mkdir -p "$src/usr/lib/system"
  cp "$pin/SDKSettings.plist" "$src/" \
    && "$rt" -stubify --filetype=tbd-v4 "$pin/usr/lib/libSystem.B.dylib" -o "$src/usr/lib/libSystem.B.tbd" \
    && "$rt" -stubify --filetype=tbd-v4 "$pin/usr/lib/system/libdyld.dylib" -o "$src/usr/lib/system/libdyld.tbd" \
    && ln -s libSystem.B.tbd "$src/usr/lib/libSystem.tbd" \
    || { echo "FAIL tbd_sdk_source_untouched: could not make a .tbd-form SDK in $src"; return 1; }
  before="$(cd "$src" && find . -type f -exec shasum -a 256 {} + | sort)"
  made=0; tbd_sdk "$rt" "$src" "$T/tbd-from-tbd" > "$T/tbd-from-tbd.out" 2>&1 || made=$?
  after="$(cd "$src" && find . -type f -exec shasum -a 256 {} + | sort)"
  [ "$before" = "$after" ] \
    || { echo "FAIL tbd_sdk_source_untouched: making a .tbd SDK from $src wrote into it; before: $before; after: $after"; return 1; }
  [ "$made" -eq 77 ] \
    || { echo "FAIL tbd_sdk_source_untouched: a source SDK whose libSystem.B.dylib is no binary stub must be skipped (77), got $made: $(cat "$T/tbd-from-tbd.out")"; return 1; }
}

cxx_system_abi() {
  (cd "$T" && "$ZIG" c++ -target x86_64-macos -o cxx_throw cxx_throw.cpp) \
    || { echo "FAIL cxx_system_abi: zig c++ -target x86_64-macos cxx_throw.cpp failed"; return 1; }
  "$OTOOL" -L "$T/cxx_throw" | awk '{ print $1 }' | grep -qx /usr/lib/libc++abi.dylib \
    || { echo "FAIL cxx_system_abi: a 10.9 C++ program must link the system's /usr/lib/libc++abi.dylib"; return 1; }
  imports "$T/cxx_throw" ___cxa_throw \
    || { echo "FAIL cxx_system_abi: ___cxa_throw must come from the system's libc++abi, undefined in the program"; return 1; }
  if defines "$T/cxx_throw" ___cxa_throw; then
    echo "FAIL cxx_system_abi: the program defines ___cxa_throw, so it carries a libc++abi of its own"; return 1
  fi
  if "$OTOOL" -L "$T/cxx_throw" | awk '{ print $1 }' | grep -q 'libc++\.1\.dylib'; then
    echo "FAIL cxx_system_abi: libc++ must be clang-22's, linked statically, not the system's libc++.1.dylib"; return 1
  fi
  guard "$T/cxx_throw" || { echo "FAIL cxx_system_abi: the C++ program must pass the compat guard"; return 1; }
}

cxx_global_ctor() {
  (cd "$T" && "$ZIG" c++ -target x86_64-macos -o cxx_cout_ctor cxx_cout_ctor.cpp) \
    || { echo "FAIL cxx_global_ctor: a global constructor that writes to std::cout must build"; return 1; }
  guard "$T/cxx_cout_ctor" || { echo "FAIL cxx_global_ctor: the program must pass the compat guard"; return 1; }
}


static_lib_into_clang22() {
  (cd "$T" && "$ZIG" build-lib -static -target x86_64-macos -OReleaseSmall -fcompiler-rt -femit-bin=liblib.a lib.zig) \
    || { echo "FAIL static_lib_into_clang22: zig build-lib -static -target x86_64-macos failed"; return 1; }
  if defines "$T/liblib.a" ___ulock_wait || defines "$T/liblib.a" _clock_gettime; then
    echo "FAIL static_lib_into_clang22: a static library must not carry Recaulk; its consumer links it"; return 1
  fi
  c22="$(clang22_for_host)" || { echo "FAIL static_lib_into_clang22: no clang22 toolchain"; return 1; }
  [ -x "$c22/bin/clang" ] || { echo "FAIL static_lib_into_clang22: no clang at $c22/bin/clang"; return 1; }
  (cd "$T" && "$c22/bin/clang" -target x86_64-apple-macos10.9 -o uselib uselib.c liblib.a) \
    || { echo "FAIL static_lib_into_clang22: clang22 could not link the Zig static library"; return 1; }
  guard "$T/uselib" || { echo "FAIL static_lib_into_clang22: clang22's link of the Zig library must pass the compat guard"; return 1; }
}

zig_build_fixture() {
  (cd "$T/build-runner" && "$ZIG" build -Dtarget=x86_64-macos --prefix "$T/build-runner/out") \
    || { echo "FAIL $1: zig build of tests/fixtures/build-runner (which runs gen.zig at build time) failed"; return 1; }
  guard "$T/build-runner/out/bin/greeter" || { echo "FAIL $1: the installed x86_64-macos artifact must pass the compat guard"; return 1; }
  f="$(floor "$T/build-runner/out/bin/greeter")"
  [ "$f" = 10.9 ] || { echo "FAIL $1: -Dtarget=x86_64-macos must give minos 10.9, got '$f'"; return 1; }
}

build_runner_on_arm64() {
  [ "$HOST" = arm64 ] || { echo "SKIP build_runner_on_arm64: the build runner is an arm64 host program only on Apple Silicon (this host is $HOST)"; return 77; }
  zig_build_fixture build_runner_on_arm64 || return 1
  n=0
  for m in "$ZIG_LOCAL_CACHE_DIR"/o/*/gen "$ZIG_GLOBAL_CACHE_DIR"/o/*/maker; do
    [ -f "$m" ] || continue
    n=$((n + 1))
    arch="$("$OTOOL" -hv "$m" | awk '$1 == "MH_MAGIC_64" { print $2; exit }')"
    [ "$arch" = ARM64 ] || { echo "FAIL build_runner_on_arm64: $m must be an arm64 host program, as upstream builds it; got '$arch'"; return 1; }
    if defines "$m" ___ulock_wait || defines "$m" ___ulock_wait2; then
      echo "FAIL build_runner_on_arm64: $m is upstream's host program and must not link Recaulk"; return 1
    fi
  done
  [ "$n" -ge 2 ] || { echo "FAIL build_runner_on_arm64: expected the build runner and gen in the caches, found $n of them"; return 1; }
}

build_runner_on_109() {
  case "$OSV" in 10.9|10.9.*) ;; *) echo "SKIP build_runner_on_109: the build runner is a 10.9 program only on Mac OS X 10.9 (this is $OSV)"; return 77 ;; esac
  zig_build_fixture build_runner_on_109 || return 1
  n=0
  for m in "$ZIG_LOCAL_CACHE_DIR"/o/*/gen "$ZIG_GLOBAL_CACHE_DIR"/o/*/maker; do
    [ -f "$m" ] || continue
    n=$((n + 1))
    f="$(floor "$m")"; s="$(sdk "$m")"
    case "$f" in 10.9|10.9.*) ;; *) echo "FAIL build_runner_on_109: $m is a host program for this 10.9 ($OSV) and must record its floor, got '$f'"; return 1 ;; esac
    [ "$s" = 10.9 ] || { echo "FAIL build_runner_on_109: $m must be linked against the pinned 10.9 SDK, got sdk '$s'"; return 1; }
    "$NM" "$m" | grep -q '___recaulk_' || { echo "FAIL build_runner_on_109: $m ran on 10.9 only because Recaulk is linked into it, and it is not"; return 1; }
  done
  [ "$n" -ge 2 ] || { echo "FAIL build_runner_on_109: expected the build runner and gen in the caches, found $n of them"; return 1; }
}

failed=0; ran=0
for tcase in recaulk_tail trivial_load_commands tbd_sdk_load_commands tbd_sdk_source_untouched cxx_system_abi cxx_global_ctor static_lib_into_clang22 build_runner_on_arm64 build_runner_on_109; do
  rc=0; "$tcase" || rc=$?
  case "$rc" in
    0) echo "ok $tcase"; ran=$((ran + 1)) ;;
    77) : ;;
    *) failed=$((failed + 1)) ;;
  esac
done
[ "$failed" -eq 0 ] || exit 1
[ "$ran" -gt 0 ] || exit 77
echo "OK link-test"
