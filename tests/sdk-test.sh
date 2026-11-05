#!/bin/sh
# platform: macOS-only -- runs the staged host zig and reads its Mach-O output's load commands
#   usage: sdk-test.sh     tests which SDK the zig build-host-zig.sh staged for this machine uses for a Mac OS X
#          10.9 target (ZIG names an installed zig instead, and the missing-SDK case then SKIPs); SKIP (77) when
#          nothing is staged. OTOOL defaults to clang22's llvm-otool on 10.9.
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$HERE/.." && pwd)"
. "$ROOT/build/versions.sh"
. "$HERE/lib/staged-zig.sh"
staged_zig_init sdk-test
. "$ROOT/build/msc.sh"
ZIG="$(staged_zig_prefix "$T/with-sdk")"
cp "$HERE/fixtures/sdk-version.c" "$HERE/fixtures/cf.c" "$HERE/fixtures/hello.zig" "$T/"
SDK109="$T/with-sdk/sdk109/SDKs/MacOSX10.9.sdk"
[ -z "$ZIG_GIVEN" ] || SDK109=/usr/local/mavergreen/sdk109/SDKs/MacOSX10.9.sdk
MISSING="error: the Mac OS X 10.9 SDK is not installed; run: sudo longboat sdk install 10.9"

sdk_pinned() {
  (cd "$T" && "$ZIG" cc -target x86_64-macos -o sdkv sdk-version.c) \
    || { echo "FAIL sdk_pinned: zig cc -target x86_64-macos must compile sdk-version.c against the 10.9 SDK's headers"; return 1; }
  s="$(sdk "$T/sdkv")"
  [ "$s" = 10.9 ] || { echo "FAIL sdk_pinned: a Mac OS X 10.9 target must record sdk 10.9 (the pinned SDK), got '$s'"; return 1; }
  (cd "$T" && "$ZIG" build-exe -target x86_64-macos -femit-bin=hello hello.zig) \
    || { echo "FAIL sdk_pinned: zig build-exe -target x86_64-macos failed"; return 1; }
  s="$(sdk "$T/hello")"
  [ "$s" = 10.9 ] || { echo "FAIL sdk_pinned: zig build-exe for a Mac OS X 10.9 target must record sdk 10.9, got '$s'"; return 1; }
}

sysroot_override() {
  other="$T/other/MacOSX10.9.sdk"
  mkdir -p "$other/usr/include"
  for e in "$SDK109"/usr/include/*; do ln -s "$e" "$other/usr/include/"; done
  rm "$other/usr/include/AvailabilityMacros.h"
  printf '#define MAC_OS_X_VERSION_MAX_ALLOWED 101000\n' > "$other/usr/include/AvailabilityMacros.h"
  if (cd "$T" && SDKROOT="$other" "$ZIG" cc -target x86_64-macos -c -o sdkroot.o sdk-version.c) 2>"$T/sdkroot.err"; then
    echo "FAIL sysroot_override: with SDKROOT set, zig cc must use that SDK's headers, not the pinned SDK's"; return 1
  fi
  grep -q "other than Mac OS X 10.9" "$T/sdkroot.err" \
    || { echo "FAIL sysroot_override: SDKROOT's SDK should fail sdk-version.c's static assert; stderr was:"; cat "$T/sdkroot.err"; return 1; }
  if (cd "$T" && "$ZIG" cc -target x86_64-macos --sysroot "$other" -c -o sysroot.o sdk-version.c) 2>"$T/sysroot.err"; then
    echo "FAIL sysroot_override: with --sysroot given, zig cc must use that SDK's headers, not the pinned SDK's"; return 1
  fi
  grep -q "other than Mac OS X 10.9" "$T/sysroot.err" \
    || { echo "FAIL sysroot_override: --sysroot's SDK should fail sdk-version.c's static assert; stderr was:"; cat "$T/sysroot.err"; return 1; }
}

missing_sdk_message() {
  [ -z "$ZIG_GIVEN" ] || { echo "SKIP missing_sdk_message: ZIG names an installed zig, whose SDK this test may not remove"; return 77; }
  nosdk="$(staged_zig_prefix "$T/no-sdk" nosdk)"
  for how in "cc -target x86_64-macos -c -o missing.o sdk-version.c" "build-exe -target x86_64-macos -femit-bin=missing hello.zig"; do
    zrc=0
    # shellcheck disable=SC2086
    (cd "$T" && "$nosdk" $how) >"$T/missing.out" 2>"$T/missing.err" || zrc=$?
    [ "$zrc" -ne 0 ] || { echo "FAIL missing_sdk_message: zig $how must fail when the 10.9 SDK is not installed"; return 1; }
    [ "$(cat "$T/missing.err")" = "$MISSING" ] \
      || { echo "FAIL missing_sdk_message: zig $how without the 10.9 SDK must print exactly '$MISSING'; stderr was:"; cat "$T/missing.err"; return 1; }
  done
  (cd "$T" && "$nosdk" build-exe -target x86_64-macos.13.0 -femit-bin=newer hello.zig) \
    || { echo "FAIL missing_sdk_message: an explicit x86_64-macos.13.0 target is upstream's and must not need the 10.9 SDK"; return 1; }
  s="$(sdk "$T/newer")"
  [ "$s" != 10.9 ] || { echo "FAIL missing_sdk_message: an explicit x86_64-macos.13.0 target must not record the 10.9 SDK"; return 1; }
}

longboat_sdk109() {
  [ -z "$ZIG_GIVEN" ] || { echo "SKIP longboat_sdk109: ZIG names an installed zig, whose sdk109 this test does not lay out"; return 77; }
  [ ! -e "$SDK109/SDKSettings.json" ] && [ -f "$SDK109/SDKSettings.plist" ] \
    || { echo "FAIL longboat_sdk109: the staged sdk109 must be laid out as Longboat installs it, SDKSettings.plist and no SDKSettings.json"; return 1; }
  lb="$(staged_zig_prefix "$T/longboat" nosdk)"
  sdk="$T/longboat/sdk109/SDKs/MacOSX10.9.sdk"
  mkdir -p "$sdk"
  cp "$SDK109/SDKSettings.plist" "$sdk/"
  ln -s "$SDK109/usr" "$sdk/usr"; ln -s "$SDK109/System" "$sdk/System"
  (cd "$T" && "$lb" cc -target x86_64-macos -o lb-cc sdk-version.c) 2>"$T/lb.err" \
    || { echo "FAIL longboat_sdk109: zig cc must find an sdk109 laid out as Longboat's (no SDKSettings.json); stderr was:"; cat "$T/lb.err"; return 1; }
  (cd "$T" && "$lb" build-exe -target x86_64-macos -femit-bin=lb-zig hello.zig) 2>"$T/lb.err" \
    || { echo "FAIL longboat_sdk109: zig build-exe must find an sdk109 laid out as Longboat's (no SDKSettings.json); stderr was:"; cat "$T/lb.err"; return 1; }
  for p in lb-cc lb-zig; do
    s="$(sdk "$T/$p")"
    [ "$s" = 10.9 ] || { echo "FAIL longboat_sdk109: $p must record SDKSettings.plist's Version, sdk 10.9, got '$s'"; return 1; }
  done
  (cd "$T" && "$ZIG" build-exe -target x86_64-macos --sysroot "$SDK109" -femit-bin=lb-sysroot hello.zig) 2>"$T/lb.err" \
    || { echo "FAIL longboat_sdk109: --sysroot naming a 10.9 SDK with no SDKSettings.json must link; stderr was:"; cat "$T/lb.err"; return 1; }
  s="$(sdk "$T/lb-sysroot")"
  [ "$s" = 10.9 ] || { echo "FAIL longboat_sdk109: --sysroot's plist-only SDK must record sdk 10.9, got '$s'"; return 1; }
}

sdk_with_json() {
  [ -z "$ZIG_GIVEN" ] || { echo "SKIP sdk_with_json: ZIG names an installed zig, whose sdk109 this test does not lay out"; return 77; }
  js="$(staged_zig_prefix "$T/json" json)"
  [ -f "$T/json/sdk109/SDKs/MacOSX10.9.sdk/SDKSettings.json" ] \
    || { echo "FAIL sdk_with_json: fetch_sdk.sh's sibling must carry SDKSettings.json"; return 1; }
  (cd "$T" && "$js" build-exe -target x86_64-macos -femit-bin=json-zig hello.zig) \
    || { echo "FAIL sdk_with_json: an sdk109 with SDKSettings.json must still serve a 10.9 target"; return 1; }
  s="$(sdk "$T/json-zig")"
  [ "$s" = 10.9 ] || { echo "FAIL sdk_with_json: an sdk109 with SDKSettings.json must record sdk 10.9, got '$s'"; return 1; }
}

bad_plist() {
  [ -z "$ZIG_GIVEN" ] || { echo "SKIP bad_plist: ZIG names an installed zig, whose sdk109 this test does not lay out"; return 77; }
  bp="$(staged_zig_prefix "$T/bad" nosdk)"
  sdk="$T/bad/sdk109/SDKs/MacOSX10.9.sdk"
  mkdir -p "$sdk"
  ln -s "$SDK109/usr" "$sdk/usr"; ln -s "$SDK109/System" "$sdk/System"
  plist="$SDK109/SDKSettings.plist"
  for how in no-version nested-only not-a-string two-versions bad-number binary no-plist; do
    rm -f "$sdk/SDKSettings.plist"
    case "$how" in
      no-version) awk '/<key>Version<\/key>/ { getline; next } { print }' "$plist" > "$sdk/SDKSettings.plist" ;;
      nested-only) awk '/<key>Version<\/key>/ { getline; next } { print } /<key>DefaultProperties<\/key>/ { getline; print; print "<key>Version</key><string>10.9</string>" }' "$plist" > "$sdk/SDKSettings.plist" ;;
      not-a-string) awk 'v { print "\t<real>10.9</real>"; v = 0; next } { print } /<key>Version<\/key>/ { v = 1 }' "$plist" > "$sdk/SDKSettings.plist" ;;
      two-versions) awk '{ print } /<key>Version<\/key>/ { getline; print; print "\t<key>Version</key>"; print "\t<string>10.10</string>" }' "$plist" > "$sdk/SDKSettings.plist" ;;
      bad-number) awk 'v { print "\t<string>10.9x</string>"; v = 0; next } { print } /<key>Version<\/key>/ { v = 1 }' "$plist" > "$sdk/SDKSettings.plist" ;;
      binary) printf 'bplist00\321\001\002WVersionT10.9' > "$sdk/SDKSettings.plist" ;;
      no-plist) : ;;
    esac
    if [ "$how" != no-plist ] && cmp -s "$plist" "$sdk/SDKSettings.plist"; then echo "FAIL bad_plist: the $how plist must differ from the SDK's"; return 1; fi
    zrc=0
    (cd "$T" && "$bp" build-exe -target x86_64-macos -femit-bin=bad hello.zig) >/dev/null 2>"$T/bad.err" || zrc=$?
    [ "$zrc" -ne 0 ] && [ "$(cat "$T/bad.err")" = "$MISSING" ] \
      || { echo "FAIL bad_plist: an sdk109 with no SDKSettings.json and a $how SDKSettings.plist must fail closed with exactly '$MISSING'; exit $zrc, stderr was:"; cat "$T/bad.err"; return 1; }
  done
}

three_part() { awk -F. 'NF { printf "%s.%s.%s\n", $1, ($2 == "" ? 0 : $2), ($3 == "" ? 0 : $3) }'; }
dylib_version() { "$OTOOL" -L "$1" | awk -v n="$2" '$1 == n { v = $NF; sub(/\)$/, "", v); print v; exit }' | three_part; }
stub_version() {
  if [ -f "$1" ]; then dylib_version "$1" "$2"; return; fi
  [ -f "$1.tbd" ] || return 0
  awk -v n="$2" '
    /^---/ { name = ""; ver = "" }
    /^install-name:/ { name = $2; gsub(/^["\047]|["\047]$/, "", name) }
    /^current-version:/ { ver = $2 }
    name == n && ver != "" { print ver; exit }' "$1.tbd" | three_part
}

tbd_version() {
  mkdir -p "$T/tbd"
  printf '%s\n' '--- !tapi-tbd' 'tbd-version: 4' "install-name: '/usr/lib/libobjc.A.dylib'" 'current-version: 228' '...' \
    '--- !tapi-tbd' 'tbd-version: 4' "install-name:    '/System/Library/Frameworks/X.framework/Versions/A/X'" \
    'current-version: 1775.118' 'compatibility-version: 150' '...' > "$T/tbd/X.tbd"
  v="$(stub_version "$T/tbd/X" /System/Library/Frameworks/X.framework/Versions/A/X)"
  [ "$v" = 1775.118.0 ] || { echo "FAIL tbd_version: a .tbd stub's current-version must be read from its own install-name's document, got '$v'"; return 1; }
  v="$(stub_version "$T/tbd/none" /System/Library/Frameworks/X.framework/Versions/A/X)"
  [ -z "$v" ] || { echo "FAIL tbd_version: no stub must give no version, got '$v'"; return 1; }
}

framework_link() {
  (cd "$T" && "$ZIG" cc -target x86_64-macos -framework CoreFoundation -o cf cf.c) \
    || { echo "FAIL framework_link: zig cc -framework CoreFoundation must link against the 10.9 SDK's CoreFoundation"; return 1; }
  cf=/System/Library/Frameworks/CoreFoundation.framework/Versions/A/CoreFoundation
  want="$(stub_version "$SDK109/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation" "$cf")"
  [ -n "$want" ] || { echo "FAIL framework_link: neither a binary stub nor a .tbd in $SDK109's CoreFoundation.framework names $cf's current version"; return 1; }
  got="$(dylib_version "$T/cf" "$cf")"
  [ "$got" = "$want" ] \
    || { echo "FAIL framework_link: CoreFoundation must be linked from the 10.9 SDK's stub (current version $want), got '$got'"; return 1; }
  s="$(sdk "$T/cf")"
  [ "$s" = 10.9 ] || { echo "FAIL framework_link: the CoreFoundation program must record sdk 10.9, got '$s'"; return 1; }
}

native_on_109() {
  case "$OSV" in 10.9|10.9.*) ;; *) echo "SKIP native_on_109: the native target is a 10.9 target only on Mac OS X 10.9 (this is $OSV)"; return 77 ;; esac
  (cd "$T" && "$ZIG" build-exe -femit-bin=native hello.zig) || { echo "FAIL native_on_109: zig build-exe for the native target failed"; return 1; }
  s="$(sdk "$T/native")"
  [ "$s" = 10.9 ] || { echo "FAIL native_on_109: the native target on 10.9 is a 10.9 target and must record sdk 10.9, got '$s'"; return 1; }
  f="$(floor "$T/native")"
  [ "$f" = 10.9 ] \
    || { echo "FAIL native_on_109: the native target on 10.9 is x86_64-macos.10.9 and must record minos 10.9, not this Mac's point release; got '$f'"; return 1; }
  MAVERICKS_ALLOW_ARCHS=x86_64 MAVERICKS_DEVIATIONS_ROOT="$ROOT" sh "$SHIPYARD_SCRIPTS/assert_binary_compatible.sh" "$T/native" \
    || { echo "FAIL native_on_109: a native build on 10.9 must pass the Mac OS X 10.9 compat guard"; return 1; }
}

failed=0; ran=0
for tcase in sdk_pinned longboat_sdk109 sdk_with_json bad_plist sysroot_override missing_sdk_message tbd_version framework_link native_on_109; do
  rc=0; "$tcase" || rc=$?
  case "$rc" in
    0) echo "ok $tcase"; ran=$((ran + 1)) ;;
    77) : ;;
    *) failed=$((failed + 1)) ;;
  esac
done
[ "$failed" -eq 0 ] || exit 1
[ "$ran" -gt 0 ] || exit 77
echo "OK sdk-test"
