#!/bin/sh
# platform: host-agnostic -- package_variant runs against a fake stage and fake shipyard scripts
#   usage: package-stage-test.sh     package_variant packages a stage only when its lib/mavergreen/BUILD-INFO is
#          the one its builder writes from this checkout (build-native.sh for native, build-host-zig.sh on arm64
#          for cross): same zig, target, patches and component pins, and the pinned Recaulk, never RECAULK_LIB's.
#          So a stale, foreign or unreleasable work-*/stage is never packaged.
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$HERE/.." && pwd)"
t="$(mktemp -d "${TMPDIR:-/tmp}/package-stage-test.XXXXXX")"; trap 'rm -rf "$t"' EXIT
fail() { echo "FAIL $1"; exit 1; }
. "$ROOT/build/msc.sh"
mkdir -p "$t/sy"
for f in "$SHIPYARD_SCRIPTS"/*; do ln -s "$f" "$t/sy/"; done
rm -f "$t/sy/product-name.sh" "$t/sy/release-mode.sh" "$t/sy/resolve-version.sh"
printf '%s\n' 'echo dev.mavergreen.zig.test' > "$t/sy/product-name.sh"
printf '%s\n' 'echo "STAGE-ACCEPTED" >&2; exit 3' > "$t/sy/release-mode.sh"
cp "$t/sy/release-mode.sh" "$t/sy/resolve-version.sh"
unset RECAULK_LIB
REPO_ROOT="$ROOT"; export REPO_ROOT
. "$ROOT/build/versions.sh"; . "$ROOT/build/lib-zig.sh"
digest="$(inputs_digest)"
case "$digest" in *[!0-9a-f]*|"") fail "inputs_digest must print hex digits, got '$digest'" ;; esac
[ "${#digest}" -eq 16 ] || fail "inputs_digest must print 16 hex digits, got '$digest'"

package() {
  REPO_ROOT="$ROOT" SHIPYARD_SCRIPTS="$t/sy" MAVERICKS_WORK="$t/work" RECAULK_LIB="${pkg_recaulk_lib:-}" \
    sh -c 'set -eu; . "$REPO_ROOT/build/package-lib.sh"; package_variant "$1"' package "$1" > "$t/out" 2>&1 || true
  if [ -e "$ROOT/dist/build-info-$1.txt" ] && [ "$ROOT/dist/build-info-$1.txt" -nt "$t/sy" ]; then
    fail "$1: package_variant went past the fake resolve-version.sh and wrote dist/build-info-$1.txt"
  fi
}
stage() {
  case "$1" in native) st="$t/work/work-native/stage/usr/local/mavergreen/zig" ;; cross) st="$t/work/work-cross/stage/usr/local/mavergreen/zig-cross" ;; esac
  rm -rf "$t/work"; mkdir -p "$st/bin" "$st/lib/zig/std" "$st/lib/mavergreen"
  printf '#!/bin/sh\n' > "$st/bin/zig"; chmod +x "$st/bin/zig"
  [ -z "$2" ] || printf '%s\n' "$2" > "$st/lib/mavergreen/BUILD-INFO"
}

native_line="zig=$ZIG_VERSION target=x86_64-macos.10.9 cpu=x86_64 optimize=ReleaseFast inputs=$digest recaulk=$RECAULK_VERSION"
cross_line="zig=$ZIG_VERSION target=aarch64-macos.11.0 cpu=baseline optimize=ReleaseFast inputs=$digest recaulk=$RECAULK_VERSION"
[ "$(build_info native)" = "$native_line" ] || fail "build_info native must be '$native_line', got '$(build_info native)'"
[ "$(build_info cross)" = "$cross_line" ] || fail "build_info cross must be '$cross_line', got '$(build_info cross)'"
[ "$(RECAULK_LIB=/x/lib/librecaulk.a build_info native)" = "${native_line% recaulk=*} recaulk=unreleased" ] \
  || fail "build_info under RECAULK_LIB must say recaulk=unreleased, got '$(RECAULK_LIB=/x/lib/librecaulk.a build_info native)'"
other_digest="$(printf '%s\n' "$digest" | tr '0-9a-f' '1-9a-f0')"
for v in native cross; do
  [ "$v" = native ] && good="$native_line" other="$cross_line" builder=build-native.sh \
    || { good="$cross_line"; other="$native_line"; builder=build-host-zig.sh; }
  pre50a0="${good% inputs=*}"
  for bad in "" "$other" "zig=0.0.0 ${good#zig=$ZIG_VERSION }" "$pre50a0" \
    "${good% inputs=*} inputs=$other_digest recaulk=$RECAULK_VERSION" "${good% recaulk=*} recaulk=unreleased" \
    "$(printf '%s\n' "$good" | sed 's/\./x/g')"; do
    stage "$v" "$bad"
    package "$v"
    grep -q "FATAL: .*lib/mavergreen/BUILD-INFO.*rebuild with build/$builder" "$t/out" \
      || fail "$v: a stage whose BUILD-INFO is '${bad:-missing}' must be refused, naming build/$builder; got: $(cat "$t/out")"
    if grep -q STAGE-ACCEPTED "$t/out"; then fail "$v: a stage whose BUILD-INFO is '${bad:-missing}' went on to packaging"; fi
  done
  stage "$v" "$good"
  package "$v"
  grep -q STAGE-ACCEPTED "$t/out" || fail "$v: a stage whose BUILD-INFO is '$good' must be accepted; got: $(cat "$t/out")"
  pkg_recaulk_lib=/x/lib/librecaulk.a; package "$v"; pkg_recaulk_lib=""
  grep -q "FATAL: RECAULK_LIB is set.*rebuild with build/$builder" "$t/out" \
    || fail "$v: packaging with RECAULK_LIB set must be refused, naming build/$builder; got: $(cat "$t/out")"
  if grep -q STAGE-ACCEPTED "$t/out"; then fail "$v: packaging with RECAULK_LIB set went on to packaging"; fi
done
grep -q 'BUILD_INFO="$(build_info cross)"' "$ROOT/build/build-host-zig.sh" \
  && grep -q 'echo "$BUILD_INFO" > "$STAGE/lib/mavergreen/BUILD-INFO"' "$ROOT/build/build-host-zig.sh" \
  || fail "build-host-zig.sh must record build_info cross in the arm64 stage"
grep -q 'BUILD_INFO="$(build_info native)"' "$ROOT/build/build-native.sh" \
  && grep -q 'echo "$BUILD_INFO" > "$STAGE/lib/mavergreen/BUILD-INFO"' "$ROOT/build/build-native.sh" \
  || fail "build-native.sh must record build_info native in its stage"
echo "OK package-stage-test"
