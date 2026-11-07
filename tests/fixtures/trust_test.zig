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

fn putU32(list: *std.ArrayList(u8), gpa: std.mem.Allocator, v: u32) !void {
    var b: [4]u8 = undefined;
    std.mem.writeInt(u32, &b, v, .big);
    try list.appendSlice(gpa, &b);
}

/// A keychain file whose one certificate table lists three record slots but holds one record: an empty
/// slot, a deleted one (unaligned offset), then the fixture certificate. record_count (1) counts records,
/// not slots, as a keychain that has had certificates deleted does.
fn sparseKeychain(gpa: std.mem.Allocator, der: []const u8) ![]u8 {
    var k: std.ArrayList(u8) = .empty;
    errdefer k.deinit(gpa);
    try k.appendSlice(gpa, "kych");
    for ([_]u32{ 0x00010000, 20, 20, 0 }) |v| try putU32(&k, gpa, v); // version, header_size, schema_offset, auth_offset
    for ([_]u32{ 0, 1, 12 }) |v| try putU32(&k, gpa, v); // schema_size, table_count, table offset
    // table header: table_size, X509_CERTIFICATE, record_count 1, records, indexes, free list, 3 slots
    for ([_]u32{ 0, 0x80001000, 1, 0, 0, 0, 3 }) |v| try putU32(&k, gpa, v);
    for ([_]u32{ 0, 1, 28 + 12 }) |v| try putU32(&k, gpa, v);
    try putU32(&k, gpa, @intCast(60 + der.len)); // record_size
    for (0..3) |_| try putU32(&k, gpa, 0);
    try putU32(&k, gpa, @intCast(der.len)); // cert_size
    for (0..10) |_| try putU32(&k, gpa, 0);
    try k.appendSlice(gpa, der);
    return k.toOwnedSlice(gpa);
}

test "keychain_sparse_records" {
    const gpa = testing.allocator;
    const begin = "-----BEGIN CERTIFICATE-----";
    const b = std.mem.indexOf(u8, fixture_pem, begin).? + begin.len;
    const e = std.mem.indexOf(u8, fixture_pem, "-----END CERTIFICATE-----").?;
    var b64: std.ArrayList(u8) = .empty;
    defer b64.deinit(gpa);
    for (fixture_pem[b..e]) |c| if (!std.ascii.isWhitespace(c)) try b64.append(gpa, c);
    const der = try gpa.alloc(u8, try std.base64.standard.Decoder.calcSizeForSlice(b64.items));
    defer gpa.free(der);
    try std.base64.standard.Decoder.decode(der, b64.items);

    const keychain = try sparseKeychain(gpa, der);
    defer gpa.free(keychain);
    var cb: Bundle = .empty;
    defer cb.deinit(gpa);
    try cb.addKeychain(gpa, keychain, std.Io.Clock.real.now(testing.io).toSeconds());
    try testing.expectEqual(1, cb.map.count());
}
