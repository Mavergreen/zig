#!/bin/sh
# platform: host-agnostic
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$HERE/.." && pwd)"
U="$(tr -d ' \t\n' < "$ROOT/UPSTREAM_VERSION")"

out="$(MAVERICKS_TAGS="" sh "$ROOT/build/version.sh" auto)"
echo "$out" | grep -qx "FULL=$U-mavericks.1" || { echo "FAIL auto/no-tags FULL: $out"; exit 1; }
echo "$out" | grep -qx "TAG=$U-mavericks.1"  || { echo "FAIL auto/no-tags TAG: $out"; exit 1; }
echo "$out" | grep -qx 'RELEASE=yes'         || { echo "FAIL auto/no-tags RELEASE: $out"; exit 1; }

out="$(MAVERICKS_TAGS="$U-mavericks.1
$U-mavericks.3" sh "$ROOT/build/version.sh" auto)"
echo "$out" | grep -qx "FULL=$U-mavericks.3" || { echo "FAIL auto/tags FULL: $out"; exit 1; }
echo "$out" | grep -qx 'RELEASE=no'          || { echo "FAIL auto/tags RELEASE: $out"; exit 1; }

out="$(MAVERICKS_TAGS="$U-mavericks.3" sh "$ROOT/build/version.sh" local)"
echo "$out" | grep -qx "FULL=$U-mavericks.4" || { echo "FAIL local FULL: $out"; exit 1; }

( . "$ROOT/build/versions.sh"
  [ "$ZIG_VERSION" = "$U" ] || { echo "FAIL ZIG_VERSION=$ZIG_VERSION"; exit 1; }
  [ "$CLANG_VERSION" = "$(tr -d ' \t\n' < "$ROOT/components/clang/version")" ] || { echo "FAIL CLANG_VERSION=$CLANG_VERSION"; exit 1; }
  [ "$RECAULK_VERSION" = "$(tr -d ' \t\n' < "$ROOT/components/recaulk/version")" ] || { echo "FAIL RECAULK_VERSION=$RECAULK_VERSION"; exit 1; }
  [ "$NATIVE_PREFIX" = /usr/local/mavergreen/zig ] || { echo "FAIL NATIVE_PREFIX=$NATIVE_PREFIX"; exit 1; }
  [ "$CROSS_PREFIX" = /usr/local/mavergreen/zig-cross ] || { echo "FAIL CROSS_PREFIX=$CROSS_PREFIX"; exit 1; }
  case "$NATIVE_STAGE_ROOT" in */work-native/stage) : ;; *) echo "FAIL NATIVE_STAGE_ROOT=$NATIVE_STAGE_ROOT"; exit 1 ;; esac
  case "$CROSS_STAGE_ROOT" in */work-cross/stage) : ;; *) echo "FAIL CROSS_STAGE_ROOT=$CROSS_STAGE_ROOT"; exit 1 ;; esac
  [ -z "${WORK:-}" ] || { echo "FAIL WORK must be unset without ZIG_VARIANT"; exit 1; }
) || exit 1
( ZIG_VARIANT=native; . "$ROOT/build/versions.sh"
  case "$WORK" in */work-native) : ;; *) echo "FAIL WORK=$WORK for ZIG_VARIANT=native"; exit 1 ;; esac
) || exit 1

echo "OK version-test"
