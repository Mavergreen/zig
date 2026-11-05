#!/bin/sh
# platform: macOS-only -- lays out a staged Zig for Mac OS X beside a Mac OS X 10.9 SDK, and reads Mach-O
#   usage: . tests/lib/staged-zig.sh     needs ROOT (the repo) and build/versions.sh already sourced.
#          staged_zig_init NAME     sets ZIG_GIVEN (the caller's ZIG), HOST (arm64 or x86_64), OSV, OTOOL, NM, LIPO, STRINGS (clang22's llvm-*
#            on 10.9, whose own are Command Line Tools stubs) and T (a fresh temporary directory, removed on
#            exit, with Zig's caches inside); unsets SDKROOT. SKIPs (exit 77) when nothing is staged and ZIG is unset.
#          staged_zig_prefix DIR [nosdk|json]     prints a zig laid out as installed: DIR/<short>/ hard-linked from the
#            staged prefix, its SDKs -> ../sdk109/SDKs, and DIR/sdk109/SDKs/MacOSX10.9.sdk laid out as Longboat's
#            sdk109 installs it: shipyard's fetched pin as Apple shipped it, SDKSettings.plist and no SDKSettings.json.
#            With json, that SDK is fetch_sdk.sh's sibling with SDKSettings.json; with nosdk, DIR has no sdk109.
#            With ZIG set, prints $ZIG (an installed zig, which has its own sdk109).
#          staged_sdk109 [json]     prints that pinned 10.9 SDK (json: the sibling with SDKSettings.json).
#          floor FILE / sdk FILE     the minos / sdk a Mach-O records (LC_BUILD_VERSION or LC_VERSION_MIN_MACOSX).

staged_zig_init() {
  if [ "$(sysctl -n hw.optional.arm64 2>/dev/null || true)" = 1 ]; then
    HOST=arm64; STAGED_PREFIX="$CROSS_STAGE_ROOT$CROSS_PREFIX"
  else
    HOST=x86_64; STAGED_PREFIX="$NATIVE_STAGE_ROOT$NATIVE_PREFIX"
  fi
  ZIG_GIVEN="${ZIG:-}"
  if [ -z "$ZIG_GIVEN" ] && [ ! -x "$STAGED_PREFIX/bin/zig" ]; then
    echo "SKIP $1: no staged zig at $STAGED_PREFIX/bin/zig (run build/build-host-zig.sh)"; exit 77
  fi
  OSV="$(sw_vers -productVersion)"
  case "$OSV" in
    10.9|10.9.*)
      _llvm=/usr/local/mavergreen/clang22/bin
      : "${OTOOL:=$_llvm/llvm-otool}" "${NM:=$_llvm/llvm-nm}" "${LIPO:=$_llvm/llvm-lipo}" "${STRINGS:=$_llvm/llvm-strings}" ;;
    *) : "${OTOOL:=otool}" "${NM:=nm}" "${LIPO:=lipo}" "${STRINGS:=strings}" ;;
  esac
  export OTOOL NM LIPO STRINGS
  unset SDKROOT
  T="$(mktemp -d "${TMPDIR:-/tmp}/$1.XXXXXX")"; trap 'rm -rf "$T"' EXIT
  ZIG_GLOBAL_CACHE_DIR="$T/gcache"; ZIG_LOCAL_CACHE_DIR="$T/lcache"; export ZIG_GLOBAL_CACHE_DIR ZIG_LOCAL_CACHE_DIR
}

staged_sdk109() {
  . "$ROOT/build/msc.sh"
  if [ "${1:-}" = json ]; then
    MAVERICKS_SDK_SETTINGS_JSON=1 sh "$SHIPYARD_SCRIPTS/fetch_sdk.sh" --arch x86_64
  else
    sh "$SHIPYARD_SCRIPTS/fetch_sdk.sh" --arch x86_64
  fi
}

staged_zig_prefix() {
  if [ -n "$ZIG_GIVEN" ]; then echo "$ZIG_GIVEN"; return; fi
  _short="$(basename "$STAGED_PREFIX")"
  mkdir -p "$1/$_short"
  # platform: pax -rwl hard-links a tree instead of copying it, where both sides share a volume
  (cd "$STAGED_PREFIX" && pax -rwl bin lib "$1/$_short") 2>/dev/null \
    || (cd "$STAGED_PREFIX" && cp -R bin lib "$1/$_short/")
  ln -s ../sdk109/SDKs "$1/$_short/SDKs"
  if [ "${2:-}" != nosdk ]; then
    _sdk="$(staged_sdk109 "${2:-}")" || { echo "FATAL: no pinned Mac OS X 10.9 SDK" >&2; return 1; }
    mkdir -p "$1/sdk109/SDKs"
    ln -s "$_sdk" "$1/sdk109/SDKs/MacOSX10.9.sdk"
  fi
  echo "$1/$_short/bin/zig"
}

floor() {
  "$OTOOL" -l "$1" | awk '
    $1 == "cmd" { lc = $2 }
    lc == "LC_BUILD_VERSION" && $1 == "minos" { print $2; exit }
    lc == "LC_VERSION_MIN_MACOSX" && $1 == "version" { print $2; exit }'
}

sdk() {
  "$OTOOL" -l "$1" | awk '
    $1 == "cmd" { lc = $2 }
    (lc == "LC_BUILD_VERSION" || lc == "LC_VERSION_MIN_MACOSX") && $1 == "sdk" { print $2; exit }'
}
