# Zig for Mavericks

Zig toolchain for Mac OS X 10.9 Mavericks.

## Compiling

Install [Longboat](https://github.com/Mavergreen/longboat),
then fetch the 10.9 SDK:

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

To avoid optimizations specific to your CPU that prevent code running on older CPUs, pass `-target x86_64-macos`.

### From Apple Silicon

```sh
sudo installer -pkg zig-cross-<version>.pkg -target /
```

In a new Terminal:

```sh
zig build-exe -target x86_64-macos hello.zig
scp hello your-mavericks-system:
```

### C and C++

```sh
zig cc -target x86_64-macos -o hello hello.c
zig c++ -target x86_64-macos -o hello hello.cpp
```

### Static libraries for another linker

```sh
zig build-lib -static -fcompiler-rt -target x86_64-macos lib.zig
```
