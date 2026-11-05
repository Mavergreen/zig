const std = @import("std");
const Dir = std.Io.Dir;

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    var r: [8]u8 = undefined;
    io.random(&r);
    var path_buf: [64]u8 = undefined;
    const root = try std.fmt.bufPrint(&path_buf, "/tmp/zig-matrix-fs-{x}", .{&r});
    try Dir.createDirAbsolute(io, root, .default_dir);
    defer Dir.cwd().deleteTree(io, root) catch {};
    var dir = try Dir.openDirAbsolute(io, root, .{});
    defer dir.close(io);

    try dir.createDirPath(io, "a/b");
    try dir.writeFile(io, .{ .sub_path = "a/b/f", .data = "contents" });
    try dir.symLink(io, "a/b/f", "link", .{});

    var buf: [std.fs.max_path_bytes]u8 = undefined;
    const target = buf[0..try dir.readLink(io, "link", &buf)];
    if (!std.mem.eql(u8, target, "a/b/f")) return error.WrongLinkTarget;

    var data: [16]u8 = undefined;
    if (!std.mem.eql(u8, try dir.readFile(io, "link", &data), "contents")) return error.WrongContents;

    var dir_real: [std.fs.max_path_bytes]u8 = undefined;
    const d = dir_real[0..try dir.realPath(io, &dir_real)];
    const l = buf[0..try dir.realPathFile(io, "link", &buf)];
    var want_buf: [std.fs.max_path_bytes]u8 = undefined;
    const want = try std.fmt.bufPrint(&want_buf, "{s}/a/b/f", .{d});
    if (!std.mem.eql(u8, l, want)) return error.WrongRealPath;
    if (!std.mem.startsWith(u8, d, "/private/tmp/")) return error.RealPathKeptTmpSymlink;

    try dir.deleteTree(io, "a");
    try std.Io.File.stdout().writeStreamingAll(io, "fs ok\n");
}
