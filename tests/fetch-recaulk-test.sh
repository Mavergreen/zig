#!/bin/sh
# platform: macOS-only -- fetch_recaulk runs lipo on a real x86_64 archive
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$HERE/.." && pwd)"
t="$(mktemp -d "${TMPDIR:-/tmp}/fetch-recaulk.XXXXXX")"; trap 'rm -rf "$t"' EXIT
fail() { echo "FAIL $1"; exit 1; }
. "$ROOT/build/versions.sh"; . "$ROOT/build/lib-zig.sh"
WORK="$t/work"; SHIPYARD_SCRIPTS="$t/sy"; export WORK SHIPYARD_SCRIPTS
mkdir -p "$SHIPYARD_SCRIPTS"
cat > "$SHIPYARD_SCRIPTS/fetch_product_pkg.sh" <<'FAKE'
echo "$*" > "$FAKE_ARGS"
mkdir -p "$3/lib" "$3/include/recaulk"
[ -n "${FAKE_NO_LIB:-}" ] || cp "$FAKE_LIB" "$3/lib/librecaulk.a"
echo "$3"
FAKE
export FAKE_ARGS="$t/args" FAKE_LIB="$t/librecaulk.a"
printf 'int recaulk_x;\n' > "$t/r.c"
cc -arch x86_64 -c "$t/r.c" -o "$t/r.o" 2>/dev/null || { echo "SKIP no x86_64 cc"; exit 77; }
ar rcs "$FAKE_LIB" "$t/r.o"

a="$(fetch_recaulk)" || fail "fetch_recaulk must succeed"
[ "$a" = "$WORK/recaulk/lib/librecaulk.a" ] || fail "prints the archive (got '$a')"
[ -d "$WORK/recaulk/include/recaulk" ] || fail "include/recaulk/ present"
[ "$(cat "$t/args")" = "recaulk $RECAULK_VERSION $WORK/recaulk" ] || fail "args (got '$(cat "$t/args")')"
rm -rf "$WORK"
! FAKE_NO_LIB=1 fetch_recaulk 2>/dev/null || fail "a pkg without librecaulk.a must fail"
echo "OK fetch-recaulk-test"
