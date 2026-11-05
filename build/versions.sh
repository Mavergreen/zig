# platform: host-agnostic
: "${REPO_ROOT:=$(cd "$(dirname "$0")/.." && pwd)}"
export REPO_ROOT
MAVERICKS_ROOT="$REPO_ROOT"; export MAVERICKS_ROOT
. "$REPO_ROOT/build/lib.sh"

export MAVERICKS_UPSTREAM_FILE="$REPO_ROOT/UPSTREAM_VERSION"
[ -f "$MAVERICKS_UPSTREAM_FILE" ] || { echo "versions.sh: no UPSTREAM_VERSION at repo root" >&2; exit 1; }
export ZIG_VERSION="$(upstream_version)"

if [ -f "$REPO_ROOT/VERSION" ]; then
  export PKG_VERSION="$(cat "$REPO_ROOT/VERSION")"
else
  export PKG_VERSION="$(sh "$REPO_ROOT/build/version.sh" auto | sed -n 's/^FULL=//p')"
fi

export CLANG_PIN_FILE="$REPO_ROOT/components/clang/version"
CLANG_VERSION="$(tr -d ' \t\n' < "$CLANG_PIN_FILE")"; export CLANG_VERSION
[ -n "$CLANG_VERSION" ] || { echo "versions.sh: empty $CLANG_PIN_FILE" >&2; exit 1; }
export RECAULK_PIN_FILE="$REPO_ROOT/components/recaulk/version"
RECAULK_VERSION="$(tr -d ' \t\n' < "$RECAULK_PIN_FILE")"; export RECAULK_VERSION
[ -n "$RECAULK_VERSION" ] || { echo "versions.sh: empty $RECAULK_PIN_FILE" >&2; exit 1; }

export NATIVE_SHORT="zig"
export CROSS_SHORT="zig-cross"
export NATIVE_PREFIX="/usr/local/mavergreen/$NATIVE_SHORT"
export CROSS_PREFIX="/usr/local/mavergreen/$CROSS_SHORT"

export WORK_ROOT="${MAVERICKS_WORK:-$HOME/.cache/mavergreen-zig}"
export CROSS_STAGE_ROOT="$WORK_ROOT/work-cross/stage"
export NATIVE_STAGE_ROOT="$WORK_ROOT/work-native/stage"
case "${ZIG_VARIANT:-}" in
  cross|native) export WORK="$WORK_ROOT/work-$ZIG_VARIANT" ;;
  "") unset WORK ;;
  *) echo "versions.sh: ZIG_VARIANT must be cross or native (got '$ZIG_VARIANT')" >&2; exit 1 ;;
esac
