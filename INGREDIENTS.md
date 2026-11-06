# Build ingredients

Everything baked into the shipped `zig` and `zig-cross` `.pkg`s, where it is pinned, and how a
change reaches a release. The *own upstream* is Zig; an ingredient is anything else the artifacts are
built with.

| Ingredient | Pinned in | Renovate | On a bump |
|---|---|---|---|
| Zig source (own upstream) | `UPSTREAM_VERSION` | ✅ `gitea-tags` on `ziglang/zig` at codeberg.org | cuts `<ver>-mavericks.1` |
| clang-22 (builds Zig's LLVM-based compiler, and clang22 builds the Sparkle updaters) | `components/clang/version` | ✅ `github-releases` on `Mavergreen/clang-22`, `-mavericks.N` versioning | repackage → `-mavericks.(N+1)` |
| Recaulk (prebuilt `librecaulk.a`, the 10.9 back-fills) | `components/recaulk/version` | ✅ shipyard preset manager → `github-releases` on `Mavergreen/recaulk` | repackage |
| MacOSX10.9 SDK (x86_64) | shipyard `fetch_sdk.sh` (pinned by hash) | ✅ moves with shipyard `@v1` | moving tag |
| MacOSX11.3 SDK (arm64; `zig-cross`'s `bin/zig` and updater slice are built against it) | shipyard `fetch_sdk.sh --arch arm64` (pinned by hash) | ✅ moves with shipyard `@v1` | moving tag |
| clang-22's `libc++.a` (x86_64) and libc++ headers, shipped in both pkgs' `lib/mavergreen/` for 10.9 C++ links | `components/clang/version` (the `llvm22-dev` asset of that clang-22 release) | ✅ as clang-22 above | repackage → `-mavericks.(N+1)` |
| Sparkle 1.27.3 framework (inside both pkgs' updaters) | shipyard `fetch_sparkle_framework.sh` (pinned by hash) | ✅ moves with shipyard `@v1` | moving tag |

## Check-only pins

Pinned so the release check is reproducible, but nothing shipped is built with them, so a bump
neither repackages nor appears in the declared state.

| Tool | Pinned in | Renovate | Used by |
|---|---|---|---|
| Longboat (installs the 10.9 SDK that clang22 needs) | `components/longboat/version` | ✅ `github-releases` on `Mavergreen/longboat` | CI only |
| ca-certs (the roots Zig's TLS adds on 10.9, whose keychain lacks GitHub's and Let's Encrypt's) | `components/ca-certs/version` | ✅ `github-releases` on `Mavergreen/ca-certs`, `-mavericks.N` versioning | CI only: on-mavericks installs it between smoke-native's two HTTPS passes |
| clang-22's native pkg (links a Zig static library in the 10.9 guest) | `components/clang/version`, the pin above | as above | CI only: on-mavericks installs it for smoke-native's uselib_clang22 |

## Declared state

- upstream: UPSTREAM_VERSION
- clang: components/clang/version
- recaulk: components/recaulk/version

## Conformance deviations

- floor:zig-cross-*.pkg: the cross toolchain runs on macOS 11 and later (arm64) and only targets 10.9, so its archive's install floor is 11.0, not 10.9.5.
- arm64:usr/local/mavergreen/zig-cross/*: zig-cross is the Zig for Apple Silicon hosts that build Mac OS X 10.9 programs, so its bin/zig is arm64 (minos 11.0, sdk 11.3); its x86_64 10.9 link inputs (lib/mavergreen/x86_64-macos/) are unchanged.
- cxxabi:usr/local/mavergreen/zig-cross/bin/zig: zig-cross's bin/zig is the arm64 compiler that runs on macOS 11 and later and only builds 10.9 programs; it is never loaded into a 10.9 program. Built for aarch64-macos.11.0 exactly as upstream (PORT.md, patch 0003 leaves non-10.9 targets alone), it statically links Zig's own bundled libc++ and libc++abi, all hidden, and loads no libc++abi dylib directly (otool -L names only libSystem and libz). The _Unwind_* and ___cxa_atexit names the check also reports are Zig's linker's arm64 branch thunks to libSystem's own functions, not definitions. Every 10.9 program Zig links still takes the system's libc++abi with clang-22's libc++; exit: link the aarch64-macos host compiler like a 10.9 target, clang-22's libc++ on the system's /usr/lib/libc++abi.dylib instead of Zig's bundled runtime, once clang-22 ships an arm64 libc++ (its llvm22-dev and libcxx22 are x86_64 only today).
- macos-runner:release.yml:build-cross: Zig's CMake bootstrap builds zig-cross with Apple clang for arm64 macOS (minos 11.0, the pinned 11.3 SDK), and the compat matrix and the staged-zig tests run that zig, which runs only on macOS. Exit: bootstrap zig-cross on Linux, cross-compiling for aarch64-macos against the pinned SDK, and move the tests that run it to modern-smoke.
- macos-runner:release.yml:build-native: build-native.sh builds the 10.9 zig with build-cross's host zig, an arm64 macOS executable. Exit: a Linux host zig, since Zig cross-builds x86_64-macos.10.9 from any host with the fetched SDK and LLVM libraries, once build-cross leaves macOS.
- macos-runner:release.yml:collect: packaging copies each stage and its clang22-built Sparkle updater with ditto (build/package-lib.sh and build/build-updater.sh), and pkg-payload-test reads the pkgs with pkgutil. Exit: the stage and updater copies need no macOS tool (clang22 already builds the updater on Linux), so packaging runs on Linux.
- macos-runner:release.yml:modern-smoke: it installs zig-cross and runs its arm64 slice, which runs only on Apple Silicon macOS. Exit: none while zig-cross ships an arm64 slice (check 37 puts this job on a macos-* runner).
