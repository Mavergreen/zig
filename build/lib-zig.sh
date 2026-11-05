#!/bin/sh
# platform: macOS-only -- fetch_recaulk runs lipo to check the x86_64 slice
#   usage: . build/lib-zig.sh     zig_src_shasum VERSION < index.json   prints the sha256 of that version's src;
#          sums_lookup NAME < SHA256SUMS     prints NAME's sha256; both print nothing and return 1 on a miss.
#          fetch_recaulk     needs SHIPYARD_SCRIPTS, WORK and RECAULK_VERSION; prints librecaulk.a's path
#            (RECAULK_LIB's instead, when set, which must be a lib/librecaulk.a beside include/recaulk)
#          lay_out_mavergreen DIR     copies the in-tree layout into DIR (a source tree's mavergreen/ or a stage's
#            lib/mavergreen/): x86_64-macos/librecaulk.a and libc++.a, include/c++/v1 and include/recaulk, from
#            RECAULK_A, RECAULK_INCLUDE and LIBCXX_FROM (an llvm22-dev with lib/x86_64-apple-darwin/libc++.a)
#          build_info native|cross     prints the lib/mavergreen/BUILD-INFO line of the stage that build-native.sh
#            (native) or build-host-zig.sh on arm64 (cross) builds from this checkout: ZIG_VERSION, the target,
#            inputs= (inputs_digest) and recaulk= (RECAULK_VERSION, or "unreleased" when RECAULK_LIB is set)
#          inputs_digest     prints the first 16 hex digits of a SHA-256 over patches/*.patch and components/*/version
#          darwin_libc_file SDK     prints a zig --libc file making the macOS SDK at SDK the libc installation

# spec: ziglang.org/download/index.json -- {"<version>": {"src": {"tarball", "shasum", "size"}, "<target>": {...}}};
#       read by object path so another target's shasum, or a pretty-printed or minified layout, cannot be mistaken for it
zig_src_shasum() {
  awk -v want="$1" '
    function tok(c) {
      if (c == ":") { if (have) key[depth] = last }
      else if (have && depth == 3 && key[1] == want && key[2] == "src" && key[3] == "shasum") { print last; found = 1; exit }
      have = 0
      if (c == "{") { depth++; delete key[depth] } else if (c == "}") depth--
    }
    { n = length($0)
      for (i = 1; i <= n; i++) {
        c = substr($0, i, 1)
        if (instr) { if (esc) { esc = 0; buf = buf c } else if (c == "\\") { esc = 1; buf = buf c } else if (c == "\"") { instr = 0; last = buf; have = 1 } else buf = buf c; continue }
        if (c == " " || c == "\t" || c == "\r") continue
        if (c == "\"") { instr = 1; buf = ""; continue }
        tok(c)
      } }
    END { exit found ? 0 : 1 }'
}

sums_lookup() {
  _s="$(awk -v f="$1" '$2 == f || $2 == "*" f { print $1 }' | head -n 2)"
  [ "$(printf '%s\n' "$_s" | grep -c .)" = 1 ] || return 1
  case "$_s" in *[!0-9a-f]*) return 1 ;; esac
  [ "${#_s}" -eq 64 ] || return 1
  printf '%s\n' "$_s"
}

fetch_recaulk() {
  if [ -n "${RECAULK_LIB:-}" ]; then
    echo "WARNING: RECAULK_LIB=$RECAULK_LIB replaces Recaulk $RECAULK_VERSION; this build is not releasable" >&2
    _rc="$(cd "$(dirname "$RECAULK_LIB")/.." && pwd)" || return 1
  else
    _rc="$(sh "$SHIPYARD_SCRIPTS/fetch_product_pkg.sh" recaulk "$RECAULK_VERSION" "$WORK/recaulk")" || return 1
  fi
  _a="$_rc/lib/librecaulk.a"
  [ -f "$_a" ] || { echo "FATAL: Recaulk $RECAULK_VERSION has no lib/librecaulk.a" >&2; return 1; }
  [ -d "$_rc/include/recaulk" ] || { echo "FATAL: Recaulk $RECAULK_VERSION has no include/recaulk/" >&2; return 1; }
  "${LIPO:-lipo}" -info "$_a" 2>/dev/null | sed -n 's/.*: //p' | grep -qw x86_64 \
    || { echo "FATAL: $_a has no x86_64 slice" >&2; return 1; }
  printf '%s\n' "$_a"
}

lay_out_mavergreen() {
  mkdir -p "$1/x86_64-macos" "$1/include/c++"
  cp "$RECAULK_A" "$1/x86_64-macos/librecaulk.a"
  cp "$LIBCXX_FROM/lib/x86_64-apple-darwin/libc++.a" "$1/x86_64-macos/libc++.a"
  cp -R "$LIBCXX_FROM/include/c++/v1" "$1/include/c++/v1"
  cp -R "$RECAULK_INCLUDE" "$1/include/recaulk"
}

inputs_digest() {
  # spec: shipyard scripts/apply_patches.sh -- the same per-file shasum -a 256 listing it records in .mavergreen-patches
  _l="$(cd "$REPO_ROOT" && shasum -a 256 patches/*.patch components/*/version)" || return 1
  printf '%s\n' "$_l" | shasum -a 256 | cut -c1-16
}

build_info() {
  case "$1" in
    native) _t="target=x86_64-macos.10.9 cpu=x86_64" ;;
    cross) _t="target=aarch64-macos.11.0 cpu=baseline" ;;
    *) echo "build_info: native|cross (got '$1')" >&2; return 2 ;;
  esac
  _d="$(inputs_digest)" && [ -n "$_d" ] || { echo "build_info: cannot digest $REPO_ROOT's patches and components" >&2; return 1; }
  echo "zig=$ZIG_VERSION $_t optimize=ReleaseFast inputs=$_d recaulk=$([ -n "${RECAULK_LIB:-}" ] && echo unreleased || echo "$RECAULK_VERSION")"
}

darwin_libc_file() {
  printf '%s\n' "include_dir=$1/usr/include" "sys_include_dir=$1/usr/include" "cc_dir=" "crt_dir=$1/usr/lib" \
    "msvc_lib_dir=" "kernel32_lib_dir=" "darwin_sdk_dir=$1"
}
