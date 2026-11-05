const std = @import("std");

export fn zig_add(a: c_int, b: c_int) c_int {
    return a + b;
}

export fn zig_now_nonzero() c_int {
    var ts: std.c.timespec = undefined;
    if (std.c.clock_gettime(.MONOTONIC, &ts) != 0) return 0;
    return @intFromBool(ts.sec != 0 or ts.nsec != 0);
}
