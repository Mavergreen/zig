#!/bin/sh
# platform: macOS-only -- runs the staged host zig's translate-c against the pinned 10.9 SDK and Recaulk
#   usage: translate-c-test.sh     tests the translate-c of the zig build-host-zig.sh staged for this machine (ZIG
#          names an installed zig instead) on #include_next (0007): a header found through one search directory's
#          subdirectory continues the search after that directory, as clang does, and a Mac OS X 10.9 target
#          translates <stdlib.h>, <dirent.h> and <netdb.h>, whose Recaulk wrappers reach the SDK's that way.
#          SKIP (77) when nothing is staged.
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$HERE/.." && pwd)"
. "$ROOT/build/versions.sh"
. "$HERE/lib/staged-zig.sh"
staged_zig_init translate-c-test
ZIG="$(staged_zig_prefix "$T/mavergreen")"

include_next_from_subdir() {
  d="$T/next"; mkdir -p "$d/first/sub" "$d/second"
  printf '#include <sub/w.h>\n' > "$d/first/w.h"
  printf '#include_next <w.h>\n' > "$d/first/sub/w.h"
  printf '#define FROM_SECOND 42\n' > "$d/second/w.h"
  printf '#include <w.h>\nint f(void) { return FROM_SECOND; }\n' > "$d/t.h"
  (cd "$d" && "$ZIG" translate-c -I first -I second t.h) >"$d/out.zig" 2>"$d/err" \
    || { cat "$d/err"; echo "FAIL include_next_from_subdir: first/sub/w.h's #include_next <w.h> must find second/w.h"; return 1; }
  grep -q 'FROM_SECOND = @as(c_int, 42)' "$d/out.zig" \
    || { echo "FAIL include_next_from_subdir: second/w.h's FROM_SECOND is missing from the translation"; return 1; }
}

mavericks_libc_headers() {
  d="$T/libc"; mkdir -p "$d"
  for h in stdlib dirent netdb; do
    printf '#include <%s.h>\n' "$h" > "$d/$h.h"
    (cd "$d" && "$ZIG" translate-c -lc -target x86_64-macos.10.9 "$h.h") >"$d/$h.zig" 2>"$d/$h.err" \
      || { cat "$d/$h.err"; echo "FAIL mavericks_libc_headers: zig translate-c -lc -target x86_64-macos.10.9 of <$h.h> failed"; return 1; }
  done
  grep -q 'pub extern fn getenv' "$d/stdlib.zig" || { echo "FAIL mavericks_libc_headers: <stdlib.h> gave no getenv"; return 1; }
  grep -q 'pub extern fn opendir' "$d/dirent.zig" || { echo "FAIL mavericks_libc_headers: <dirent.h> gave no opendir"; return 1; }
  grep -q 'pub extern fn getaddrinfo' "$d/netdb.zig" || { echo "FAIL mavericks_libc_headers: <netdb.h> gave no getaddrinfo"; return 1; }
}

failed=0
for t in include_next_from_subdir mavericks_libc_headers; do
  if "$t"; then echo "ok $t"; else failed=1; fi
done
[ "$failed" -eq 0 ] || exit 1
echo "OK translate-c-test"
