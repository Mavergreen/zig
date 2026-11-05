const std = @import("std");

noinline fn matrixTraceMarker(t: std.Io.Terminal) !void {
    try std.debug.writeCurrentStackTrace(.{}, t);
}

pub fn main(init: std.process.Init) !void {
    var out: std.Io.Writer.Allocating = .init(init.gpa);
    defer out.deinit();
    try matrixTraceMarker(.{ .writer = &out.writer, .mode = .no_color });
    const trace = out.written();
    try std.Io.File.stderr().writeStreamingAll(init.io, trace);
    const marker = std.mem.indexOf(u8, trace, "matrixTraceMarker") orelse return error.NoMarkerFrame;
    _ = std.mem.indexOfPos(u8, trace, marker + "matrixTraceMarker".len, "main") orelse return error.NoMainFrame;
    var lines = std.mem.splitScalar(u8, trace, '\n');
    while (lines.next()) |line| {
        if (std.mem.indexOf(u8, line, "Unwind error") == null) continue;
        if (std.mem.indexOf(u8, line, "/usr/lib/system/libdyld.dylib") == null) return error.UnwindErrorBeforeDyldStart;
    }
    try std.Io.File.stdout().writeStreamingAll(init.io, "trace ok\n");
}
