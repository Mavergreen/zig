const std = @import("std");

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const echo = try std.process.run(init.gpa, io, .{ .argv = &.{ "/bin/echo", "from child" } });
    defer init.gpa.free(echo.stdout);
    defer init.gpa.free(echo.stderr);
    if (!echo.term.success()) return error.EchoFailed;
    if (!std.mem.eql(u8, echo.stdout, "from child\n")) return error.WrongChildOutput;

    var child = try std.process.spawn(io, .{ .argv = &.{ "/bin/sh", "-c", "exit 3" } });
    const term = try child.wait(io);
    switch (term) {
        .exited => |code| if (code != 3) return error.WrongExitCode,
        else => return error.ChildDidNotExit,
    }
    try std.Io.File.stdout().writeStreamingAll(io, "child ok\n");
}
