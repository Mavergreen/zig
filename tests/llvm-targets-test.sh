#!/bin/sh
# platform: macOS-only -- runs the staged host zig, built for macOS
#   usage: llvm-targets-test.sh     tests the zig build-host-zig.sh staged for this machine, laid out beside a 10.9
#          SDK by tests/lib/staged-zig.sh (ZIG names an installed zig instead); SKIP (77) when nothing is staged
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$HERE/.." && pwd)"
. "$ROOT/build/versions.sh"
. "$HERE/lib/staged-zig.sh"
staged_zig_init llvm-targets-test
ZIG="$(staged_zig_prefix "$T/mavergreen")"
t="$T"
cp "$HERE/fixtures/hello.zig" "$t/"
fail() { echo "FAIL $1"; exit 1; }

if (cd "$t" && "$ZIG" build-obj -target riscv64-linux -femit-bin=riscv.o hello.zig) > "$t/out" 2>&1; then
  fail "llvm_only_target_message: riscv64-linux must be refused by a zig whose LLVM has no RISCV backend"
fi
msg="$(grep 'built with LLVM targets' "$t/out" || true)"
case "$msg" in
  *"this Zig for Mavericks was built with LLVM targets "*"; riscv64 is not one of them"*) : ;;
  *) fail "llvm_only_target_message: the refusal must name the built targets and riscv64, got: $(cat "$t/out")" ;;
esac
list="${msg#*built with LLVM targets }"; list="${list%%;*}"
case " $list " in *" X86 "*) : ;; *) fail "llvm_only_target_message: the built targets must include X86, got '$list'" ;; esac
case " $list " in *" RISCV "*) fail "llvm_only_target_message: RISCV cannot be both built and refused ('$list')" ;; esac

(cd "$t" && "$ZIG" build-obj -target x86_64-macos -OReleaseSmall -femit-bin=x86.o hello.zig) \
  || fail "llvm_built_target: an x86_64 target must build through LLVM"
[ -s "$t/x86.o" ] || fail "llvm_built_target: no object for x86_64-macos"
echo "OK llvm-targets-test"
