const std = @import("std");

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    var client: std.http.Client = .{ .allocator = init.gpa, .io = io };
    defer client.deinit();
    var body: std.Io.Writer.Allocating = .init(init.gpa);
    defer body.deinit();
    const res = try client.fetch(.{ .location = .{ .url = "https://ziglang.org/" }, .response_writer = &body.writer });
    if (res.status != .ok) return error.NotOk;
    if (std.mem.indexOf(u8, body.written(), "Zig") == null) return error.UnexpectedBody;
    try std.Io.File.stdout().writeStreamingAll(io, "http ok\n");
}
