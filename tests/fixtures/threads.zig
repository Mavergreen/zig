const std = @import("std");

var ready: std.atomic.Value(u32) = .init(0);

fn worker(io: std.Io) void {
    ready.store(1, .release);
    io.futexWake(u32, &ready.raw, 1);
}

pub fn main(init: std.process.Init) !void {
    const t = try std.Thread.spawn(.{}, worker, .{init.io});
    while (ready.load(.acquire) == 0) try init.io.futexWait(u32, &ready.raw, 0);
    t.join();
    try std.Io.File.stdout().writeStreamingAll(init.io, "threads\n");
}
