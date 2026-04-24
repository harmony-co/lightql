///! Takes an input from the `stdin` and a file path as an argument,
///! prints the concatenation of whatever is sent through `stdin` and
///! the contents of the file passed as the argument.
///! Emulates what you'd see if you do `cat file1 file2`
///! if you could do it like this `file1 | cat file2`.
///! This is needed to pass `file1` as a lazily generated file
///! from another build step.
const std = @import("std");

const logger = std.log.scoped(.pipe_concat);

pub fn main(init: std.process.Init) !void {
    // `std.fs.cwd()` is always relative to where the process is being called from
    //
    // ```sh
    // # from `/path/to/lightql/../` (parent dir of where the project is)
    // echo "something" | zig run lightql/scripts/build.pipe_concat.zig -- ./build.zig.zon
    // error(opcodes): /path/to/lightql/../build.zig.zon File not found.
    // ```
    //
    // ```sh
    // # from `/path/to/lightql/` (inside the project dir)
    // echo "something" | zig run scripts/build.pipe_concat.zig -- ./build.zig.zon
    // something
    //
    // .{
    //     .name = .lightql,
    // ...
    // ```
    const io = init.io;
    const arena = init.arena.allocator();

    const cwd = std.Io.Dir.cwd();
    // TODO: maybe this is the correct dir to use across all open/realpath calls?
    const self_exe_dir_path = try std.process.executableDirPathAlloc(io, arena);
    var self_exe_dir = try cwd.openDir(io, self_exe_dir_path, .{});
    defer self_exe_dir.close(io);

    const args = try init.minimal.args.toSlice(arena);
    if (args.len != 2) {
        logger.err("Must pass exactly one file path.", .{});
        std.process.exit(1);
    }

    const file_path = cwd.realPathFileAlloc(io, args[1], arena) catch |err| switch (err) {
        error.FileNotFound => {
            logger.err("{s} File not found.", .{try std.fs.path.resolve(arena, &.{
                try cwd.realPathFileAlloc(io, ".", arena), args[1],
            })});
            std.process.exit(1);
        },
        else => return err,
    };
    const file = try self_exe_dir.openFile(io, file_path, .{});
    defer file.close(io);

    var allocating: std.Io.Writer.Allocating = .init(arena);
    defer allocating.deinit();
    const allocating_writer = allocating.writer;

    var stdin_reader = std.Io.File.stdin().reader(io, allocating_writer.buffer);
    const stdin = &stdin_reader.interface;
    const input = try stdin.allocRemaining(arena, .unlimited);
    if (input.len == 0 or std.mem.eql(u8, "", std.mem.trim(u8, input, &std.ascii.whitespace))) {
        logger.err("No stdin input was provided.", .{});
        std.process.exit(1);
    }

    const file_buffer = try self_exe_dir.readFileAlloc(io, file_path, arena, .unlimited);
    const stdout_buffer = try arena.alloc(u8, input.len + file_buffer.len);
    var stdout_writer = std.Io.File.stdout().writer(io, stdout_buffer);
    const stdout = &stdout_writer.interface;

    try stdout.print("{s}\n{s}\n", .{ input, file_buffer });
    try stdout.flush();
}
