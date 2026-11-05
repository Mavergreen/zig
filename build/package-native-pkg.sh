#!/bin/sh
# platform: macOS-only -- see build/package-lib.sh
#   usage: package-native-pkg.sh     builds dist/zig-<FULL>.pkg from the native stage (build/package-lib.sh)
set -eu
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"; export REPO_ROOT
. "$REPO_ROOT/build/package-lib.sh"; package_variant native
