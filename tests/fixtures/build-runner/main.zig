const std = @import("std");
const generated = @import("generated");

pub fn main(init: std.process.Init) !void {
    try std.Io.File.stdout().writeStreamingAll(init.io, generated.greeting ++ "\n");
}
