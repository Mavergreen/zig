# Zig for Mavericks

**This README has not been read or edited by a human yet.** Until it has, this project cannot cut
its first release.

Zig 0.17.0 toolchain for Mac OS X 10.9 Mavericks, unofficial and not affiliated with the Zig project.
It also gives you `zig cc` and `zig c++` for 10.9.

Two packages:

| Package | Installs to | Runs on | Builds for |
|---|---|---|---|
| `zig` | `/usr/local/mavergreen/zig` | Mac OS X 10.9 (x86_64) | 10.9 |
| `zig-cross` | `/usr/local/mavergreen/zig-cross` | Apple Silicon, macOS 11.0 or later (arm64) | 10.9 |

Both have a Sparkle updater.

## Compiling

Both packages need the Mac OS X 10.9 SDK from [Longboat](https://github.com/Mavergreen/longboat),
and refuse to install without it:

```sh
sudo longboat sdk install 10.9
```

### Directly on Mavericks

```sh
sudo installer -pkg zig-<version>.pkg -target /
```

In a new Terminal:

```sh
zig build-exe hello.zig
./hello
```

### From Apple Silicon

```sh
sudo installer -pkg zig-cross-<version>.pkg -target /
```

In a new Terminal:

```sh
zig build-exe -target x86_64-macos hello.zig
scp hello your-mavericks-system:
```

If both packages are installed on one Mac, the first one installed gets `zig` on your `PATH`. Run the
other as `/usr/local/mavergreen/zig-cross/bin/zig` (or `/usr/local/mavergreen/zig/bin/zig`), or move
`zig` to it:

```sh
sudo mavergreen select zig zig-cross
```

(`sudo mavergreen select zig zig` moves it back.)

### C and C++

```sh
zig cc -target x86_64-macos -o hello hello.c
zig c++ -target x86_64-macos -o hello hello.cpp
```

C++ links [Clang 22 for Mavericks](https://github.com/Mavergreen/clang-22)'s libc++, so a program
built with `zig c++` and one built with clang-22 agree on the C++ ABI. Zig builds no libc++ of its own
for 10.9.

### `native` on 10.9

With no `-target`, on 10.9, Zig builds for `native`: Mac OS X 10.9 (minos 10.9, the 10.9 SDK,
Recaulk), like `-target x86_64-macos`. But `native` also tunes the code for this Mac's CPU, so the
program may not run on a Mac with an older CPU. For a program meant to run on other Macs, give
`-target x86_64-macos`.

### Static libraries for another linker

A Zig static library that something other than Zig links (clang-22, say) must carry Zig's
compiler-rt, or the link can fail on symbols only Zig's compiler-rt has (`__zig_probe_stack` in a
Debug build):

```sh
zig build-lib -static -fcompiler-rt -target x86_64-macos lib.zig
```

## Targets

- `-target x86_64-macos`, with no version, means Mac OS X 10.9: minos 10.9, the 10.9 SDK, and
  [Recaulk](https://github.com/Mavergreen/recaulk)'s back-fills of the libSystem functions 10.9
  lacks (Zig's standard library calls several of them). Upstream's default is 15.0.
- An explicit version from 10.9 to 10.15 (`-target x86_64-macos.10.12`) is a Mac OS X 10.9-class
  target too: that minos, the 10.9 SDK, clang-22's libc++ and Recaulk.
- An explicit version of 11.0 or later (`-target x86_64-macos.13.0`) is exactly upstream's: that
  minos, Zig's own libc++, no Recaulk, no 10.9 SDK.
- `native` on Apple Silicon is upstream's, and so is `aarch64-macos`.
- A 10.9 target uses the SDK `longboat` installed, unless you give `--sysroot` or set `SDKROOT`;
  either of those is honoured instead.
- If the 10.9 SDK is missing, you get `error: the Mac OS X 10.9 SDK is not installed; run: sudo longboat
  sdk install 10.9`.

## HTTPS (`zig fetch`)

Zig's TLS trusts the macOS keychain's roots. 10.9's keychain stops at Apple's last update for 10.9
and lacks newer roots, such as Let's Encrypt's ISRG Root X1 and the USERTrust ECC root GitHub uses, so
`zig fetch` and `zig build` fetching a dependency can fail there.

[CA Certificates for Mavericks](https://github.com/Mavergreen/ca-certs) fixes that. This Zig adds
`/usr/local/mavergreen/ca-certs/etc/openssl/certs/ca-certificates.crt` to the keychain's roots when
the file is there. It is optional: neither package requires it, and without it Zig trusts the keychain
alone. A bundle that cannot be read or parsed is skipped with one warning.

This applies on any Mac these packages run on, not only 10.9.

## What is not supported

- **Non-macOS targets.** The LLVM here is Clang 22 for Mavericks's, built with only X86 (and AArch64
  for `zig-cross`'s host). Asking for any target LLVM lacks (`riscv64-linux`, say) fails with `this
  Zig for Mavericks was built with LLVM targets <list>; <arch> is not one of them`. Self-hosted
  backends need no LLVM target and are unaffected.
- **`aarch64-macos` at 10.9.** There is no such system. `aarch64-macos` is upstream's.
- **Keychain distrust.** Zig reads the keychain's certificates and ignores their trust settings, as
  upstream does. A root an administrator has marked distrusted is still trusted, and so is a
  distrusted root that is in the ca-certs bundle. This is a known gap, not handled.

## Building from source

Both the packages and their changes to upstream Zig are explained in [PORT.md](PORT.md); the pinned
ingredients are in [INGREDIENTS.md](INGREDIENTS.md).

You need [shipyard](https://github.com/Mavergreen/shipyard) (install its cmake product, then its
pkg; open a new terminal after the first install). The scripts fetch the rest: the pinned SDKs (10.9,
and 11.3 for arm64), clang-22's LLVM and libc++, Recaulk, Zig's source and, for the updaters, the
pinned Clang 22.

On a modern Mac you also need Apple's `/usr/bin/clang` (the Command Line Tools, `xcode-select
--install`), which `build/build-host-zig.sh` uses to build the arm64 `zig-cross` and stage it.
`build/build-native.sh` then uses that one to build the 10.9 `zig`:

```sh
sh build/build-host-zig.sh
sh build/build-native.sh
sh build/package-cross-pkg.sh
sh build/package-native-pkg.sh
```

Natively on 10.9, `build/build-host-zig.sh` builds an x86_64 Zig instead, with an installed Clang 22
for Mavericks (`/usr/local/mavergreen/clang22`, or `CLANG22`) and `ninja`, and
`build/build-native.sh` then rebuilds the 10.9 `zig` with that one. Only the `zig` package is built
there:

```sh
sh build/build-host-zig.sh
sh build/build-native.sh
sh build/package-native-pkg.sh
```

Tests are in `tests/`; `sh "$SHIPYARD_SCRIPTS/run-repo-tests.sh"` runs them.
