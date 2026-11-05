#!/bin/sh
# platform: host-agnostic
#   usage: upstream-notes-url-test.sh     runs build/upstream-release-notes-url.sh; never the network
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$HERE/.." && pwd)"
H="$ROOT/build/upstream-release-notes-url.sh"
fail() { echo "FAIL $1"; exit 1; }
[ -f "$H" ] || fail "build/upstream-release-notes-url.sh missing (check 11: a new upstream links upstream's notes)"
U="$(tr -d ' \t\n' < "$ROOT/UPSTREAM_VERSION")"
for v in 0.17.0 "$U"; do
  out="$(sh "$H" "$v")"
  [ "$out" = "https://ziglang.org/download/$v/release-notes.html" ] || fail "want Zig's release notes for $v, got: $out"
  [ "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" = 1 ] || fail "upstream-notes.sh requires exactly one line"
done
s=0; sh "$H" >/dev/null 2>&1 || s=$?
[ "$s" = 2 ] || fail "no argument must be a usage error (exit 2), got $s"
s=0; sh "$H" 0.17.0 0.16.0 >/dev/null 2>&1 || s=$?
[ "$s" = 2 ] || fail "two arguments must be a usage error (exit 2), got $s"
echo "OK upstream-notes-url-test"
