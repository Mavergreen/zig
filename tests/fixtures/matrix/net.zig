const std = @import("std");
const HostName = std.Io.net.HostName;

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const host: HostName = try .init("ziglang.org");

    var results_buf: [16]HostName.LookupResult = undefined;
    var results: std.Io.Queue(HostName.LookupResult) = .init(&results_buf);
    try host.lookup(io, &results, .{ .port = 80 });
    var addresses: usize = 0;
    while (results.getOne(io)) |res| switch (res) {
        .address => addresses += 1,
        .canonical_name => {},
    } else |err| switch (err) {
        error.Closed => {},
        else => |e| return e,
    }
    if (addresses == 0) return error.NoAddresses;

    var stream = try host.connect(io, 80, .{ .mode = .stream });
    defer stream.close(io);
    var wbuf: [256]u8 = undefined;
    var w = stream.writer(io, &wbuf);
    try w.interface.writeAll("HEAD / HTTP/1.0\r\nHost: ziglang.org\r\n\r\n");
    try w.interface.flush();
    var rbuf: [256]u8 = undefined;
    var r = stream.reader(io, &rbuf);
    const line = try r.interface.takeDelimiterExclusive('\n');
    if (!std.mem.startsWith(u8, line, "HTTP/1.")) return error.NotHttp;
    try std.Io.File.stdout().writeStreamingAll(io, "net ok\n");
}
