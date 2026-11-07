const std = @import("std");
const testing = std.testing;
const darwin = std.zig.system.darwin;

// Written by tests/std-sdk-test.sh: the SDKROOT this run sets ("" for none) and the SDK a Mac OS X 10.9
// target must get from std.
const sdkroot = std.mem.trimEnd(u8, @embedFile("sdkroot.txt"), "\n");
const expect_sdk = std.mem.trimEnd(u8, @embedFile("expect.txt"), "\n");
const pinned = "/usr/local/mavergreen/sdk109/SDKs/MacOSX10.9.sdk";

fn target(arch_os_abi: []const u8) !std.Target {
    return std.zig.system.resolveTargetQuery(testing.io, try std.Target.Query.parse(.{ .arch_os_abi = arch_os_abi }));
}

test "get_sdk_mavericks" {
    const t = try target("x86_64-macos.10.9");
    const got = darwin.getSdk(testing.allocator, testing.io, &t) orelse return error.NoSdk;
    defer testing.allocator.free(got);
    try testing.expectEqualStrings(expect_sdk, got);
}

test "find_native_mavericks" {
    const t = try target("x86_64-macos.10.9");
    var env: std.process.Environ.Map = .init(testing.allocator);
    defer env.deinit();
    if (sdkroot.len != 0) try env.put("SDKROOT", sdkroot);
    var lci = try std.zig.LibCInstallation.findNative(testing.allocator, testing.io, .{ .target = &t, .environ_map = &env });
    defer lci.deinit(testing.allocator);
    try testing.expectEqualStrings(expect_sdk, lci.darwin_sdk_dir.?);
    const include = try std.fs.path.join(testing.allocator, &.{ expect_sdk, "usr/include" });
    defer testing.allocator.free(include);
    try testing.expectEqualStrings(include, lci.include_dir.?);
    try testing.expectEqualStrings(include, lci.sys_include_dir.?);
}

test "get_sdk_newer_is_upstreams" {
    const t = try target("x86_64-macos.13.0");
    const got = darwin.getSdk(testing.allocator, testing.io, &t) orelse return;
    defer testing.allocator.free(got);
    try testing.expect(!std.mem.eql(u8, got, pinned));
    if (sdkroot.len != 0) try testing.expect(!std.mem.eql(u8, got, sdkroot));
}
