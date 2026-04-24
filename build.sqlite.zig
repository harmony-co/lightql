const std = @import("std");
const mem = std.mem;

const Target = struct {
    include: [][]const u8,
    files: [][]const u8,
    flags: [][]const u8,
    modules: [][]const u8,
};

const Options = struct {
    enable_fts5: bool,
    enable_carray: bool,
};

pub fn sqlite(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    opts: Options,
) !*std.Build.Step.Compile {
    const sqlite_dep = b.dependency("sqlite", .{});
    const sqlite_path = sqlite_dep.path("");

    const libsqlite = b.addLibrary(.{
        .name = "sqlite",
        .linkage = .static,
        .root_module = b.createModule(.{
            .link_libc = true,
            .target = target,
            .optimize = optimize,
        }),
    });

    const base = try getConfig(Target, b, "targets", "base");
    for (base.include) |include_path| libsqlite.root_module.addIncludePath(sqlite_dep.path(include_path));
    libsqlite.root_module.addCSourceFiles(.{
        .root = sqlite_path,
        .files = base.files,
        .flags = base.flags,
    });

    const lemon = genLemon(b, sqlite_path);
    const jimsh = genJimsh(b, sqlite_path);
    const mksourceid = genMKSourceid(b, sqlite_path);
    const mkkeywordhash = genMKKeywordHash(b, sqlite_path);
    const pipe_concat = pipeAndConcat(b);

    const parse_run = b.addRunArtifact(lemon);
    const parse_dir = parse_run.addPrefixedOutputDirectoryArg("-d", "parse");
    parse_run.addPrefixedFileArg("-T", sqlite_path.path(b, "tool/lempar.c"));
    parse_run.addArg("-S");
    parse_run.addFileArg(sqlite_path.path(b, "src/parse.y"));

    const parse_vdbe_concat_run = b.addRunArtifact(pipe_concat);
    parse_vdbe_concat_run.setStdIn(.{ .lazy_path = parse_dir.path(b, "parse.h") });
    parse_vdbe_concat_run.addFileArg(sqlite_path.path(b, "src/vdbe.c"));
    const parse_vdbe = parse_vdbe_concat_run.captureStdOut(.{});

    const opcodes_h_run = b.addRunArtifact(jimsh);
    opcodes_h_run.setStdIn(.{ .lazy_path = parse_vdbe });
    opcodes_h_run.addFileArg(sqlite_path.path(b, "tool/mkopcodeh.tcl"));
    const opcodes_h = opcodes_h_run.captureStdOut(.{});

    const mksqlite3h_scope = b.addWriteFiles();
    _ = mksqlite3h_scope.addCopyDirectory(mksourceid.getEmittedBinDirectory(), "", .{});
    const mksqlite3h = mksqlite3h_scope.addCopyDirectory(sqlite_path, "", .{ .include_extensions = &.{
        "VERSION",
        "manifest",
        "manifest.uuid",
        "manifest.tags",
        "tool/mksqlite3h.tcl",
        "src/sqlite.h.in",
        "ext/rtree/sqlite3rtree.h",
        "ext/session/sqlite3session.h",
        "ext/fts5/fts5.h",
    } });

    const sqlite_h_run = b.addRunArtifact(jimsh);
    sqlite_h_run.setCwd(mksqlite3h);
    sqlite_h_run.addFileArg(mksqlite3h.path(b, "tool/mksqlite3h.tcl"));
    sqlite_h_run.addDirectoryArg(mksqlite3h);
    const sqlite_h = sqlite_h_run.captureStdOut(.{});

    const keywordhash_run = b.addRunArtifact(mkkeywordhash);
    const keywordhash_h = keywordhash_run.captureStdOut(.{});

    const pragma_h_run = b.addRunArtifact(jimsh);
    pragma_h_run.addFileArg(sqlite_path.path(b, "tool/mkpragmatab.tcl"));
    const pragma_h = pragma_h_run.addOutputFileArg("pragma.h");

    const ctime_c_run = b.addRunArtifact(jimsh);
    ctime_c_run.addFileArg(sqlite_path.path(b, "tool/mkctimec.tcl"));
    const ctime_c = ctime_c_run.addOutputFileArg("ctime.c");

    if (opts.enable_fts5) {
        const awf_fts5 = b.addWriteFiles();
        const fts5_parse_dir = awf_fts5.addCopyDirectory(sqlite_path.path(b, "ext/fts5"), "parse/fts5", .{ .exclude_extensions = &.{".test"} });
        _ = awf_fts5.addCopyFile(sqlite_path.path(b, "manifest"), "manifest");
        _ = awf_fts5.addCopyFile(sqlite_path.path(b, "manifest.uuid"), "manifest.uuid");

        const parse_fts5_run = b.addRunArtifact(lemon);
        parse_fts5_run.setCwd(fts5_parse_dir);
        parse_fts5_run.addPrefixedFileArg("-T", sqlite_path.path(b, "tool/lempar.c"));
        parse_fts5_run.addPrefixedDirectoryArg("-d", fts5_parse_dir);
        parse_fts5_run.addArg("-S");
        parse_fts5_run.addFileArg(fts5_parse_dir.path(b, "fts5parse.y"));

        const fts5_c_run = b.addRunArtifact(jimsh);
        fts5_c_run.setCwd(fts5_parse_dir);
        fts5_c_run.addFileArg(fts5_parse_dir.path(b, "tool/mkfts5c.tcl"));

        fts5_c_run.step.dependOn(&parse_fts5_run.step);
        libsqlite.step.dependOn(&fts5_c_run.step);

        libsqlite.root_module.addIncludePath(fts5_parse_dir);
        libsqlite.root_module.addCSourceFile(.{ .file = fts5_parse_dir.path(b, "fts5.c") });
        libsqlite.root_module.addCMacro("SQLITE_ENABLE_FTS5", "1");
    }

    const awf_h = b.addWriteFiles();
    const opcodes_h_file = awf_h.addCopyFile(opcodes_h, "opcodes.h");
    const sqlite_h_file = awf_h.addCopyFile(sqlite_h, "sqlite3.h");
    _ = awf_h.addCopyFile(keywordhash_h, "keywordhash.h");
    _ = awf_h.addCopyFile(pragma_h, "pragma.h");

    const opcodes_c_run = b.addRunArtifact(jimsh);
    opcodes_c_run.addFileArg(sqlite_path.path(b, "tool/mkopcodec.tcl"));
    opcodes_c_run.addFileArg(opcodes_h_file);
    const opcodes_c = opcodes_c_run.captureStdOut(.{});

    const awf_c = b.addWriteFiles();
    const opcodes_c_file = awf_c.addCopyFile(opcodes_c, "opcodes.c");

    libsqlite.root_module.addIncludePath(parse_dir);
    libsqlite.root_module.addIncludePath(awf_h.getDirectory());
    libsqlite.root_module.addCSourceFile(.{ .file = ctime_c });
    libsqlite.root_module.addCSourceFile(.{ .file = opcodes_c_file });
    libsqlite.root_module.addCSourceFile(.{ .file = parse_dir.path(b, "parse.c") });

    libsqlite.root_module.addCMacro("SQLITE_CORE", "1");

    // TODO: Allow users to set the debug mode themselves
    if (optimize == .Debug) {
        libsqlite.root_module.addCMacro("SQLITE_DEBUG", "1");
    }

    if (opts.enable_carray) libsqlite.root_module.addCMacro("SQLITE_ENABLE_CARRAY", "1");

    const sqlitebindings = b.addTranslateC(.{
        .optimize = optimize,
        .target = target,
        .root_source_file = sqlite_h_file,
    });
    sqlitebindings.addIncludePath(awf_h.getDirectory());

    _ = b.addModule("sqlite3.h", .{ .root_source_file = sqlite_h_file });

    const lib = b.addLibrary(.{
        .name = "sqlite",
        .linkage = .static,
        .root_module = sqlitebindings.createModule(),
    });
    lib.root_module.linkLibrary(libsqlite);

    return lib;
}

fn pipeAndConcat(b: *std.Build) *std.Build.Step.Compile {
    return b.addExecutable(.{ .name = "pipe_concat", .root_module = b.createModule(.{
        .root_source_file = b.path("scripts/build.pipe_concat.zig"),
        .optimize = .ReleaseSmall,
        .target = b.graph.host,
    }) });
}

fn genMKKeywordHash(
    b: *std.Build,
    sqlite_path: std.Build.LazyPath,
) *std.Build.Step.Compile {
    const tool_path = sqlite_path.path(b, "tool");
    const mkkeywordhash = b.addExecutable(.{ .name = "mkkeywordhash", .root_module = b.createModule(.{
        .optimize = .ReleaseSmall,
        .target = b.graph.host,
        .link_libc = true,
    }) });
    mkkeywordhash.root_module.addCSourceFile(.{ .file = tool_path.path(b, "mkkeywordhash.c") });
    return mkkeywordhash;
}

fn genMKSourceid(
    b: *std.Build,
    sqlite_path: std.Build.LazyPath,
) *std.Build.Step.Compile {
    const tool_path = sqlite_path.path(b, "tool");
    const mksourceid = b.addExecutable(.{ .name = "mksourceid", .root_module = b.createModule(.{
        .optimize = .ReleaseSmall,
        .target = b.graph.host,
        .link_libc = true,
    }) });
    mksourceid.root_module.addCSourceFile(.{ .file = tool_path.path(b, "mksourceid.c") });
    return mksourceid;
}

fn genLemon(
    b: *std.Build,
    sqlite_path: std.Build.LazyPath,
) *std.Build.Step.Compile {
    const tool_path = sqlite_path.path(b, "tool");
    const lemon = b.addExecutable(.{ .name = "lemon", .root_module = b.createModule(.{
        .optimize = .ReleaseSmall,
        .target = b.graph.host,
        .link_libc = true,
    }) });
    lemon.root_module.addCSourceFile(.{ .file = tool_path.path(b, "lemon.c") });
    return lemon;
}

fn genJimsh(
    b: *std.Build,
    sqlite_path: std.Build.LazyPath,
) *std.Build.Step.Compile {
    const autosetup_path = sqlite_path.path(b, "autosetup");
    const jimsh = b.addExecutable(.{ .name = "jimsh", .root_module = b.createModule(.{
        .optimize = .ReleaseSmall,
        .target = b.graph.host,
        .link_libc = true,
    }) });
    jimsh.root_module.addCSourceFile(.{
        .file = autosetup_path.path(b, "jimsh0.c"),
        .flags = &.{"-DHAVE_REALPATH"},
    });
    return jimsh;
}

fn getConfig(comptime T: type, b: *std.Build, dir: []const u8, name: []const u8) !T {
    const alloc = b.allocator;
    const io = b.graph.io;

    const cwd = std.Io.Dir.cwd();

    const config_path = try cwd.realPathFileAlloc(io, b.fmt("{s}/{s}.zon", .{ dir, name }), alloc);
    defer alloc.free(config_path);

    const config_file = try cwd.openFile(io, config_path, .{});
    defer config_file.close(io);

    const file = try config_file.stat(io);
    var buffer = try alloc.allocSentinel(u8, file.size, 0);
    errdefer alloc.destroy(&buffer);

    var reader = config_file.reader(io, buffer);
    try reader.interface.readSliceAll(buffer);

    return try std.zon.parse.fromSliceAlloc(T, alloc, buffer, null, .{});
}
