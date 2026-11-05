const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const gen = b.addExecutable(.{
        .name = "gen",
        .root_module = b.createModule(.{
            .root_source_file = b.path("gen.zig"),
            .target = b.graph.host,
        }),
    });
    const run_gen = b.addRunArtifact(gen);
    const generated = run_gen.addOutputFileArg("generated.zig");

    const exe = b.addExecutable(.{
        .name = "greeter",
        .root_module = b.createModule(.{
            .root_source_file = b.path("main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    exe.root_module.addAnonymousImport("generated", .{ .root_source_file = generated });
    b.installArtifact(exe);
}
