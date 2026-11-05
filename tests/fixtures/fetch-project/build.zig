const std = @import("std");

pub fn build(b: *std.Build) void {
    const jsmn = b.dependency("jsmn", .{});
    b.getInstallStep().dependOn(&b.addInstallFile(jsmn.path("jsmn.h"), "include/jsmn.h").step);
}
