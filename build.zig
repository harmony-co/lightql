const std = @import("std");
const sqlite_compile = @import("build.sqlite.zig").sqlite;

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const enable_fts5 = b.option(bool, "enable_fts5", "Whether to compile sqlite with FTS5") orelse false;
    const enable_carray = b.option(bool, "enable_carray", "Whether to compile sqlite with CARRAY extension") orelse false;

    const sqlite = (try sqlite_compile(b, target, optimize)).root_module;

    if (enable_fts5) sqlite.addCMacro("SQLITE_ENABLE_FTS5", "1");
    if (enable_carray) sqlite.addCMacro("SQLITE_ENABLE_CARRAY", "1");

    const sqlitezig = b.addLibrary(.{
        .name = "sqlitezig",
        .root_module = b.addModule("sqlitezig", .{
            .root_source_file = b.path("src/root.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "sqlite", .module = sqlite },
            },
        }),
    });

    b.installArtifact(sqlitezig);

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "sqlitezig", .module = sqlitezig.root_module },
        },
    });
    const exe = b.addExecutable(.{
        .name = "main",
        .root_module = exe_mod,
    });

    b.installArtifact(exe);

    const run_exe = b.addRunArtifact(exe);
    const run_step = b.step("run", "Run the application");
    run_step.dependOn(&run_exe.step);
}
