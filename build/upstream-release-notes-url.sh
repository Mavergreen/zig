#!/bin/sh
# platform: host-agnostic
#   usage: upstream-release-notes-url.sh <upstream-version>     prints Zig's release notes URL for it
set -eu
[ "$#" -eq 1 ] && [ -n "$1" ] || { echo "usage: upstream-release-notes-url.sh <upstream-version>" >&2; exit 2; }
printf 'https://ziglang.org/download/%s/release-notes.html\n' "$1"
