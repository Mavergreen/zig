const std = @import("std");

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    var a: [32]u8 = @splat(0);
    var b: [32]u8 = @splat(0);
    try io.randomSecure(&a);
    io.random(&b);
    if (std.mem.allEqual(u8, &a, 0) or std.mem.allEqual(u8, &b, 0)) return error.NoEntropy;
    if (std.mem.eql(u8, &a, &b)) return error.SameBytesTwice;
    try std.Io.File.stdout().writeStreamingAll(io, "random ok\n");
}
