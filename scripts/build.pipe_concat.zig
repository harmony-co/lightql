///! Takes an input from the `stdin` and a file path as an argument,
///! prints the concatenation of whatever is sent through `stdin` and
///! the contents of the file passed as the argument.
///! Emulates what you'd see if you do `cat file1 file2`
///! if you could do it like this `file1 | cat file2`.
///! This is needed to pass `file1` as a lazily generated file
///! from another build step.
const std = @import("std");

const logger = std.log.scoped(.pipe_concat);

pub fn main() !void {
    // `std.fs.cwd()` is always relative to where the process is being called from
    //
    // ```sh
    // # from `/path/to/sqlitezig/../` (parent dir of where the project is)
    // echo "something" | zig run sqlitezig/scripts/build.pipe_concat.zig -- ./build.zig.zon
    // error(opcodes): /path/to/sqlitezig/../build.zig.zon File not found.
    // ```
    //
    // ```sh
    // # from `/path/to/sqlitezig/` (inside the project dir)
    // echo "something" | zig run scripts/build.pipe_concat.zig -- ./build.zig.zon
    // something
    //
    // .{
    //     .name = .sqlitezig,
    // ...
    // ```
    const cwd = std.fs.cwd();

    var arena_state: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    // TODO: maybe this is the correct dir to use across all open/realpath calls?
    const self_exe_dir_path = try std.fs.selfExeDirPathAlloc(arena);
    var self_exe_dir = try cwd.openDir(self_exe_dir_path, .{});
    defer self_exe_dir.close();

    const args = try std.process.argsAlloc(arena);
    defer std.process.argsFree(arena, args);
    if (args.len != 2) {
        logger.err("Must pass exactly one file path.", .{});
        std.process.exit(1);
    }

    const file_path = cwd.realpathAlloc(arena, args[1]) catch |err| switch (err) {
        error.FileNotFound => {
            logger.err("{s} File not found.", .{try std.fs.path.resolve(arena, &.{
                try cwd.realpathAlloc(arena, "."), args[1],
            })});
            std.process.exit(1);
        },
        else => return err,
    };
    const file = try self_exe_dir.openFile(file_path, .{});
    defer file.close();

    var allocating: std.Io.Writer.Allocating = .init(arena);
    defer allocating.deinit();
    const allocating_writer = allocating.writer;

    var stdin_reader = std.fs.File.stdin().reader(allocating_writer.buffer);
    const stdin = &stdin_reader.interface;
    const input = try stdin.allocRemaining(arena, .unlimited);
    if (input.len == 0 or std.mem.eql(u8, "", std.mem.trim(u8, input, &std.ascii.whitespace))) {
        logger.err("No stdin input was provided.", .{});
        std.process.exit(1);
    }

    const file_size = (try file.stat()).size;
    const file_buffer = try self_exe_dir.readFileAlloc(arena, file_path, file_size);

    const stdout_buffer = try arena.alloc(u8, input.len + file_size);
    var stdout_writer = std.fs.File.stdout().writer(stdout_buffer);
    const stdout = &stdout_writer.interface;

    try stdout.print("{s}\n{s}\n", .{ input, file_buffer });
    try stdout.flush();
}
