const std = @import("std");

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const real = std.Io.Timestamp.now(io, .real);
    if (real.nanoseconds < 1_600_000_000 * std.time.ns_per_s) return error.RealClockBeforeSeptember2020;
    const start = std.Io.Timestamp.now(io, .awake);
    try io.sleep(.fromMilliseconds(50), .awake);
    const slept = start.durationTo(std.Io.Timestamp.now(io, .awake));
    if (slept.nanoseconds < 50 * std.time.ns_per_ms) return error.SleptTooLittle;
    _ = std.Io.Timestamp.now(io, .boot);
    _ = std.Io.Timestamp.now(io, .cpu_process);
    _ = std.Io.Timestamp.now(io, .cpu_thread);
    try std.Io.File.stdout().writeStreamingAll(io, "time ok\n");
}
