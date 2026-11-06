# Zig for Mavericks: carried changes

Every change this repo carries to upstream Zig is a file in `patches/`, applied in name order by
shipyard's `apply_patches.sh` (from `build/build-host-zig.sh`), and explained here: what it does, why,
the invariant it keeps, and when to reconsider it.

## Baseline: unpatched Zig 0.17.0

Built 2026-11-04 with `sh build/build-host-zig.sh` and an empty `patches/`, on Mac OS X 10.9.5 x86_64
(Xeon E5-1650 v2, 12 threads), clang22 22.1.8-mavericks.12, against clang-22 22.1.8-mavericks.13's
x86_64 `llvm22-dev` (`targets=X86`).

It stops at configure, 16 s in, before compiling anything:

```
CMake Error at cmake/Findllvm.cmake:30 (message):
  LLVM (according to .../llvm22-dev-x86_64/llvm22-dev/bin/llvm-config)
  is missing target AArch64.  Zig requires LLVM to be built with all default
  targets enabled.
```

Upstream Zig requires an LLVM with every default target (`ZIG_LLVM_REQUIRED_TARGETS` in
`cmake/Findllvm.cmake`), and its LLVM backend calls each target's `LLVMInitialize*` functions, so it
cannot be built against clang-22's LLVM (X86 on x86_64, X86 and AArch64 on arm64) at all. The arm64
host fails the same check (no AMDGPU, ARM, ...).

Past that check (a scratch copy with the required list narrowed to X86), zig1 builds and generates
`zig2.c` (11 minutes in all), and the zig2 link fails on 96 undefined symbols: 92 `LLVMInitialize*`
functions of the 19 backends this LLVM lacks, and four libc functions Mac OS X 10.9 does not have and
Recaulk 20261025.5 does not back-fill: `preadv`, `pwritev`, `posix_spawn_file_actions_addchdir_np`,
`posix_spawn_file_actions_addfchdir_np`. Zig's std calls all four unconditionally on macOS.

With those 96 resolved by a scratch stub (an emulation of `preadv`/`pwritev`, the rest failing), the
unpatched zig2 runs on 10.9: `-target x86_64-macos` gets `LC_BUILD_VERSION` minos 15.0 (and sdk
27.0); an explicit `x86_64-macos.10.9` is accepted and gets `LC_VERSION_MIN_MACOSX` 10.9; an
explicit `x86_64-macos.13.0` gets minos 13.0.

With 0001 and 0004 applied, `build-host-zig.sh` on the same box gets through configure, zig1 and
zig2.c and stops at the zig2 link after 12 minutes, on exactly those four libc functions. They are
Recaulk's to back-fill; nothing here works around them. Recaulk 20261104.1, the pin since, back-fills
all four.

## 0001-macos-x86_64-floor-10.9.patch

**What.** Two hunks, both for x86_64 macOS only.
- In `std.Target.Os.VersionRange.default`, an x86_64 macOS target with no version gets minimum 10.9
  instead of upstream's 15.0. The maximum (27.0), every other arch (aarch64 keeps 15.0), and every
  explicit version are untouched.
- In `std.zig.system.resolveTargetQuery`, when an x86_64 host below macOS 11 resolves an x86_64
  `native` target, the detected minimum (this Mac's release, such as 10.9.5) becomes 10.9.0. The
  detected maximum stays this Mac's release. Detection on macOS 11 and later, and on an arm64 host,
  is upstream's. CPU detection is upstream's: `native` still tunes for this Mac's CPU.

**Why.** The product's whole point is that `zig build-exe -target x86_64-macos` (and `zig cc` for the
same target) produces a program that runs on Mac OS X 10.9: minos 10.9, written as
`LC_VERSION_MIN_MACOSX` by Zig's linker, as Apple's ld64 does below 10.14. Upstream already accepts
an explicit `x86_64-macos.10.9` (above), so the default is the only change needed for the floor.
On 10.9 the `native` target is x86_64-macos.10.9 as well. Upstream would record this Mac's point
release (10.9.5), which the family's compat guard (`assert_binary_compatible.sh`) refuses, since
the family's pinned minimum is 10.9. A Mac from 10.10 to 10.15 gets the same 10.9 floor, because
0002 treats every x86_64 floor below 11.0 as a Mac OS X 10.9 target.

**Invariant.** `-target x86_64-macos` means 10.9. `-target x86_64-macos.N` with N >= 11 is exactly
upstream: minos N, never a clamp to 10.9. `native` on Apple Silicon and `aarch64-macos` are exactly
upstream. `tests/target-floor-test.sh` holds all three. On 10.9, `native` records minos 10.9 and
passes the compat guard: `tests/sdk-test.sh`'s `native_on_109` and `tests/smoke-native.sh`'s
`hello_zig` hold that.

**Reconsider** when the family stops targeting 10.9, or if upstream grows a configurable default
deployment target (then set it at build time instead of patching).

## 0002-macos-x86_64-pinned-sdk.patch

**What.** A Mac OS X 10.9 target (x86_64 macOS with a floor below 11.0, `src/mavergreen.zig`'s
`isMavericksTarget`) compiles and links against one SDK: `--sysroot` when given, else `SDKROOT` when
set, else the installed `<prefix>/SDKs/MacOSX10.9.sdk` (`<zig lib dir>/../../SDKs`, which the pkg
links to `../sdk109/SDKs`).
- `Compilation.create` makes that SDK the libc installation: its `usr/include` for headers, its
  `System/Library/Frameworks` for `-iframework`, its `usr/lib` for libSystem, its `SDKSettings.json`
  (or, when it has none, its `SDKSettings.plist`) for the SDK version the linker records, and the SDK
  itself as the linker's syslibroot.
- `main.zig`'s `createModule` searches the SDK's `usr/lib` and `System/Library/Frameworks` after the
  user's `-L` and `-F`, as ld64 searches `-syslibroot`'s, so `-framework CoreFoundation` and `-lz`
  resolve there, and skips the native-path detection that asks xcrun.
- Longboat's `sdk109` is Apple's 10.9 SDK as shipped: `SDKSettings.plist` and no `SDKSettings.json`.
  A 10.9 target's SDK with no `SDKSettings.json` (the installed one, `--sysroot`'s or `SDKROOT`'s)
  gives the linker the `Version` of its `SDKSettings.plist`, read by `src/mavergreen.zig`'s
  `plistSdkVersion`. That is a strict text scan, not a plist parser: it takes the `<string>` after the
  one `<key>Version</key>` of the top-level dictionary when it is numbers such as `10.9` or `10.9.5`,
  and refuses anything else (a binary plist, an unclosed comment, CDATA, unbalanced dictionaries, no
  top-level `Version` or two, another value type, any other value). An `SDKSettings.json`, when the SDK
  has one, wins, as upstream.
- When the installed SDK is missing, or names no version that way (no `SDKSettings.json`, and no
  `SDKSettings.plist` that `plistSdkVersion` accepts), every compile or link for a 10.9 target fails
  with exactly `error: the Mac OS X 10.9 SDK is not installed; run: sudo longboat sdk install 10.9`.
  A `--sysroot` or `SDKROOT` SDK that names no version fails the link instead, naming its plist.
- Zig's Mach-O linker reads the SDK as Apple shipped it, stub libraries (`MH_DYLIB_STUB`, not
  `.tbd`), as ld64 does. Upstream had never linked against binary umbrella libraries, and three
  of its bugs surfaced: it refused the stub file type; a re-exported library with a different
  name in its source (`_memchr`, which 10.9's libsystem_c re-exports from libsystem_platform's
  `_platform_memchr`) was recorded under the source's name, so `_memchr` was undefined; and an
  umbrella's exports grew after its symbols were made (CoreServices re-exports CarbonCore and the
  rest), which crashed the linker. For a 10.9 target, a library with `LC_SUB_FRAMEWORK`
  (libSystem's `/usr/lib/system/*`) is reached through its umbrella, so a program records
  `/usr/lib/libSystem.B.dylib` and not its parts; a missing re-exported library is an error
  rather than a crash.
- For a 10.9 target, an SDK whose stubs are `.tbd` (a user's `--sysroot`, `SDKROOT`, or an `sdk109`
  laid out that way) links the same: a `.tbd` whose `parent-umbrella` names the umbrella that
  re-exports it (ld64's name for it, the install name's leaf without `lib` and its suffix: `System`
  for `/usr/lib/libSystem.B.dylib`) is reached through that umbrella, as `LC_SUB_FRAMEWORK` is.
  Upstream read `parent-umbrella` and never used it, so libdyld and libsystem_c were each recorded
  beside libSystem, unlike clang22's output. Both rules are gated by `isMavericksTarget` in
  `parseDependentDylibs`: every other target (`aarch64-macos`, Apple Silicon's `native`, an
  explicit `x86_64-macos.11.0` or later) records sub-libraries exactly as upstream does.
- `std.zig.system.darwin.getSdk` treats an empty `xcrun --show-sdk-path` as no SDK.

**Why.** The compat guard reads the SDK a binary records, and the family pins 10.9's: a 10.9 program
built against Zig's bundled headers (or the runner's SDK) records sdk 27.0 and can compile against a
post-10.9 declaration that fails only on the target. Upstream uses an SDK only when xcrun names one
for a native target; on 10.9 with the Command Line Tools, xcrun exits 0 with an empty path, and Zig
then used `""` as the SDK ("failed to find library 'System'", `/SDKSettings.json`), and with Xcode
it names the 10.10 SDK. The plist, because the SDK users have is Longboat's, which like Apple's has no
`SDKSettings.json`: an earlier 0002 required one, and the shipped Zig refused every 10.9 compile ("not
installed") for everyone, while the tests passed on shipyard's JSON-carrying sibling. Reading the
plist's own `Version`, rather than hard-coding 10.9, keeps the SDK as Apple shipped it and records the
version of whatever plist-only SDK a user's `--sysroot` names; failing closed on anything unexpected
keeps a version the linker could misrecord out of every binary. The SDK is never copied into the
Zig tree: like clang-22's, it is the `sdk109` product's, so one `sudo longboat sdk install 10.9`
serves every toolchain. Stubs because the family keeps the SDK as Apple shipped it; `.tbd` too,
because the SDK a user names with `--sysroot` or `SDKROOT` can have either.

**Invariant.** A 10.9 target records sdk 10.9, compiles against 10.9's headers and links 10.9's
libSystem and frameworks, whether or not the Command Line Tools or Xcode are installed. A
user's `--sysroot` or `SDKROOT` wins over the installed SDK. A missing SDK is one line naming the
fix, never a cascade of missing headers. An explicit `x86_64-macos.11.0` or later, `aarch64-macos`
and Apple Silicon's `native` are upstream's: no 10.9 SDK, and no error without one.
An `sdk109` laid out as Longboat installs it (plist, no JSON) serves a 10.9 target and records sdk
10.9, and one with `SDKSettings.json` still does. `tests/sdk-test.sh` holds these: the tests' staged
`sdk109` is the plain pinned SDK (`longboat_sdk109`), `sdk_with_json` keeps the JSON case, and
`bad_plist` the refusals. A trivial 10.9 program records only `/usr/lib/libSystem.B.dylib`, against
the pinned SDK's binary stubs and against a `.tbd` SDK made from them by clang22's `llvm-readtapi
-stubify`: `tests/link-test.sh`'s `trivial_load_commands` and `tbd_sdk_load_commands`.

**Reconsider** when Zig grows a configurable default SDK or deployment target per toolchain build,
or when the family stops pinning 10.9's SDK. Offer the three stub-library fixes upstream.
Exit for the plist reading: once Longboat's `sdk109` installs an `SDKSettings.json` (a shipyard
change), and every supported Longboat installs one, drop `plistSdkVersion` and require the JSON again.

## 0003-macos-x86_64-recaulk-libcxx.patch

**What.** A Mac OS X 10.9 executable or dylib links like clang22's do.
- Zig's Mach-O linker loads, after every other input (and after compiler_rt): for C++, clang-22's
  `<zig lib dir>/../mavergreen/x86_64-macos/libc++.a`; then Recaulk's `librecaulk.a` beside it; then
  the SDK's `libc++abi` (named by the link for C++), and CoreFoundation, Security, CoreServices,
  IOKit and libobjc, which Recaulk's back-fills call into and which a program records only when
  something it links references them. Both archives load hidden (`-load_hidden`), so a dylib
  exports neither libc++ nor Recaulk's back-fills. Their members load only to resolve a symbol:
  Zig's linker otherwise behaves as with `-ObjC` and force-loads every archive member that has
  Objective-C, which put Recaulk's Objective-C back-fills, and libobjc, into every 10.9 program.
  And the linker's own reference to `_objc_msgSend` (for the `_objc_msgSend$` stubs it makes) is
  an import only when it made such stubs, so a libobjc nothing uses is not recorded. clang22
  links without `-ObjC`, so an empty `main` from either loads only libSystem.
- Every C-family compile for a 10.9 target searches `<zig lib dir>/../mavergreen/include/recaulk`
  first, as clang22's config does: Recaulk's headers declare its back-fills and repair the 10.9
  SDK's (libc++'s `<__mbstate_t.h>` needs Recaulk's `sys/_types/_mbstate_t.h`).
- C++ for a 10.9 target compiles against `<zig lib dir>/../mavergreen/include/c++/v1` (clang-22's
  libc++ headers, configured by their own `__config_site`) with `--mavergreen-own-libcxx` (clang-22's
  patch 0007: aligned allocation and sized deallocation are available, since that libc++ defines
  them), and Zig builds none of its own libc++, libc++abi or libunwind.
- Zig's compiler_rt defines `__isPlatformVersionAtLeast` (what `__builtin_available` and
  `@available` call) for x86_64 macOS below 10.15 too: upstream defines it only from 10.15, where
  libSystem has `_availability_version_check`, and Recaulk back-fills that for 10.9. LLVM's own
  `sys::fs::copy_file` calls it, so stage3 does not link without it.
- `--verbose-link` prints those inputs.
- Static libraries and objects get none of it: their consumer links Recaulk, as clang22 does.

**Why.** Zig's std calls libSystem functions 10.9 lacks (`openat` and the other `*at` calls,
`clock_gettime`, `__ulock_wait`, `preadv`, `posix_spawn_file_actions_addchdir_np`, ...) whatever
the floor; Recaulk back-fills them for every family product, and the family rule is that back-fills
live in Recaulk, not inside Zig. On 10.9 the build runner and stage3 are themselves 10.9 programs
linked by Zig's linker: without Recaulk the runner died at launch on 21 imports 10.9 lacks. Archive
order matters: Recaulk's forwarding members define compiler-rt's half-float conversions
(`__extendhfsf2`, `__truncsfhf2`), so the archive must come after compiler_rt, which then wins. The
C++ runtime is clang-22's, for one C++ ABI across the family: libc++ statically, on the system's
`/usr/lib/libc++abi.dylib` with Recaulk's libc++abi back-fills, so a Zig-built C++ program or
static library and a clang22 link agree, and a Cocoa process never holds two libc++abi copies.
Recaulk precedes `libc++abi`, so its catch-rule vtables win over 10.9's, as in clang22's links.

**Invariant.** A trivial 10.9 C or Zig program loads only `/usr/lib/libSystem.B.dylib`, the same
libraries clang22 gives it. Every 10.9 executable or dylib Zig links passes the compat guard with no Recaulk
symbol exported, defines no `___cxa_*` of its own, and imports `/usr/lib/libc++abi.dylib` for C++.
An explicit 11.0 or later, other arches and Apple Silicon's `native` link exactly as upstream:
no Recaulk, Zig's own libc++. `tests/link-test.sh` holds these, including a `zig build` whose
runner and generator are host programs (arm64 on Apple Silicon, 10.9 programs on 10.9).

**Reconsider** when the family stops targeting 10.9, when Recaulk's dependency list changes (it
mirrors Recaulk's README), or if Zig gains a linker-script-style hook for toolchain-provided inputs.

## 0004-llvm-targets-x86-aarch64.patch

**What.** Zig builds against an LLVM that has only some of LLVM's targets, and uses only those.
- `cmake/Findllvm.cmake` requires X86 instead of all 20 default targets.
- `CMakeLists.txt` passes the targets `llvm-config --targets-built` reports to `zig build` as the new
  `-Dllvm-targets` option, and `stage1/config.zig.in` hands the same list to zig2.
- `initializeLLVMTarget` (`src/codegen/llvm.zig`) references a backend's `LLVMInitialize*`
  functions only when that target was built (a comptime check, so absent backends are never linked).
- When the LLVM backend would be used for an arch whose LLVM target was not built,
  `Compilation.Config.resolve` refuses with `error: this Zig for Mavericks was built with LLVM
  targets <list>; <arch> is not one of them`.
- `build.zig`'s `-Dstatic-llvm` path (no CMake: `build/build-native.sh`, as zig-bootstrap's last
  step) links a target's `LLVM<Target>*` libraries only when `-Dllvm-targets` names that target,
  and links `z` and `zstd` only with `-Dllvm-has-zlib` and `-Dllvm-has-zstd` (both default true, as
  upstream): clang-22's LLVM is built without either, and `build-native.sh` reads all three from
  `llvm22-dev`'s `LLVMConfig.cmake`.
- With `-Dllvm-targets` unset (an upstream-style build) the list is empty and every target counts
  as built, which is upstream's behaviour.
- Not a hunk: `build/build-host-zig.sh` and `build/build-native.sh` pass `-Dno-langref`. Generating
  the language reference builds its examples, some for wasm32 (`doc/langref/wasi_args.zig` is
  `wasm32-wasi`), a target this LLVM lacks, so the packages ship no `doc/langref.html`.

**Why.** The family has one LLVM 22 build, clang-22's, and its `llvm22-dev` ingredient is built with
`LLVM_TARGETS_TO_BUILD` X86 (x86_64 libraries) and X86;AArch64 (arm64 libraries). A Zig-only LLVM
build with every target would be a second, divergent LLVM. Upstream refuses this LLVM at configure,
and past that check its zig2 link fails on 92 `LLVMInitialize*` symbols for the 19 missing backends.

**Invariant.** Zig links only the LLVM backends its LLVM has. Asking for any other target through
LLVM fails with the message above, naming the built list, and never with a missing symbol or a crash;
the self-hosted backends (which need no LLVM target) are unaffected. `tests/llvm-targets-test.sh`
holds both halves: `riscv64-linux` is refused with the message, and an x86_64 target builds.

**Reconsider** when clang-22 (or its successor) widens the family's LLVM target set: the list follows
`llvm-config` automatically, so only the X86 requirement in `Findllvm.cmake` would need a look. Drop
the patch if upstream Zig learns to build against a partial LLVM.

## 0005-macos-trust-ca-certs-bundle.patch

**What.** On macOS, `std.crypto.Certificate.Bundle.rescanMac` (what `rescan` calls, and so what
`std.http.Client` and `zig fetch` trust) reads the keychains as upstream does, then adds the ca-certs
bundle at `/usr/local/mavergreen/ca-certs/etc/openssl/certs/ca-certificates.crt` when it is there,
through the new `pub fn addMavergreenBundle(cb, gpa, io, now, path) void` (also reachable as
`Bundle.addMavergreenBundle`).
- The bundle is read whole into a scratch `Bundle` first and merged only when every PEM block in it
  parsed, so `cb` gains all of the bundle's certificates or none of them.
- An absent file adds nothing and says nothing.
- Any other failure (unreadable, bad base64, a missing `END CERTIFICATE`, an unparseable
  certificate, or no usable certificate at all) is one `std.log.warn` ("skipping the ca-certs bundle
  <path>: <error>"); the keychain roots are kept and the scan succeeds.
- It applies on every macOS host and target, not only 10.9: it is a runtime addition to the trust
  store, not a 10.9 target behaviour, so `src/mavergreen.zig`'s `isMavericksTarget` does not gate it.

**Why.** 10.9's keychain roots stopped at Apple's last update for 10.9: newer roots (ISRG Root X1
among them) are missing, so HTTPS from `zig fetch` can fail where a current Mozilla set succeeds. The family's ca-certs product installs that
set at one contract path, and golang's macOS root store takes the union of the keychain and the same
bundle; Zig's does the same here, so the two agree on what is trusted. ca-certs stays optional: the
zig pkg never `--requires` it.

**Invariant.** Without ca-certs, the trust store is exactly upstream's keychain roots. With it, the
store is the union, never just the bundle. A bad file at the contract path never fails or crashes a
fetch: it is skipped with one warning. `tests/trust-test.sh` holds these (`keychain_roots`,
`bundle_adds_certs`, `bundle_absent`, `bundle_unreadable`, `bundle_malformed_after_valid`, and
exactly one warning per bad bundle), with temporary bundles, never the real contract path.

**Gap: keychain distrust.** Upstream reads the keychain files' certificates and ignores their trust
settings, so a root an administrator has marked distrusted is still trusted, and the union adds a
second way in: a bundle root the keychain distrusts is trusted too. Neither is handled here. Exit:
align with golang's trust invariants in a trust-policy brainstorm.

**Reconsider** at that brainstorm, when the family stops targeting 10.9 (a current macOS's keychain
roots stay updated), or if upstream Zig grows a way to add a CA bundle to the system scan (an
environment variable or option), which would replace the fixed path.
