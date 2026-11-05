const std = @import("std");

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = args[1], .data = "pub const greeting = \"generated at build time\";\n" });
}
