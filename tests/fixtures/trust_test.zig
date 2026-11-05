const std = @import("std");
const testing = std.testing;
const Bundle = std.crypto.Certificate.Bundle;

const fixture_pem = @embedFile("trust-test-ca.pem");

fn bundleAt(buf: []u8, tmp: *const testing.TmpDir, name: []const u8, data: []const u8) ![]const u8 {
    try tmp.dir.writeFile(testing.io, .{ .sub_path = name, .data = data });
    return std.fmt.bufPrint(buf, ".zig-cache/tmp/{s}/{s}", .{ &tmp.sub_path, name });
}

fn keychainRoots(gpa: std.mem.Allocator) !Bundle {
    var cb: Bundle = .empty;
    errdefer cb.deinit(gpa);
    try cb.rescan(gpa, testing.io, std.Io.Clock.real.now(testing.io));
    return cb;
}

test "keychain_roots" {
    const gpa = testing.allocator;
    var cb = try keychainRoots(gpa);
    defer cb.deinit(gpa);
    try testing.expect(cb.map.count() > 0);
}

test "bundle_adds_certs" {
    const gpa = testing.allocator;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var buf: [256]u8 = undefined;
    const path = try bundleAt(&buf, &tmp, "ca-certificates.crt", fixture_pem);

    var cb = try keychainRoots(gpa);
    defer cb.deinit(gpa);
    const before = cb.map.count();
    cb.addMavergreenBundle(gpa, testing.io, std.Io.Clock.real.now(testing.io), path);
    try testing.expectEqual(before + 1, cb.map.count());
}

test "bundle_absent" {
    const gpa = testing.allocator;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var buf: [256]u8 = undefined;
    const path = try std.fmt.bufPrint(&buf, ".zig-cache/tmp/{s}/no-such-bundle.crt", .{&tmp.sub_path});

    var cb = try keychainRoots(gpa);
    defer cb.deinit(gpa);
    const before = cb.map.count();
    cb.addMavergreenBundle(gpa, testing.io, std.Io.Clock.real.now(testing.io), path);
    try testing.expectEqual(before, cb.map.count());
}

test "bundle_unreadable" {
    const gpa = testing.allocator;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var buf: [256]u8 = undefined;
    const path = try bundleAt(&buf, &tmp, "ca-certificates.crt",
        "-----BEGIN CERTIFICATE-----\n%%% not base64 %%%\n-----END CERTIFICATE-----\n");

    var cb = try keychainRoots(gpa);
    defer cb.deinit(gpa);
    const before = cb.map.count();
    cb.addMavergreenBundle(gpa, testing.io, std.Io.Clock.real.now(testing.io), path);
    try testing.expectEqual(before, cb.map.count());
}

test "bundle_malformed_after_valid" {
    const gpa = testing.allocator;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var buf: [256]u8 = undefined;
    const path = try bundleAt(&buf, &tmp, "ca-certificates.crt", fixture_pem ++ "-----BEGIN CERTIFICATE-----\nMIIB\n");

    var cb = try keychainRoots(gpa);
    defer cb.deinit(gpa);
    const before = cb.map.count();
    const bytes_before = cb.bytes.items.len;
    cb.addMavergreenBundle(gpa, testing.io, std.Io.Clock.real.now(testing.io), path);
    try testing.expectEqual(before, cb.map.count());
    try testing.expectEqual(bytes_before, cb.bytes.items.len);
}
