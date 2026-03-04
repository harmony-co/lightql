## sqlitezig

Build SQLite with a minimal setup, using zig

## Installation

```sh
git submodule add git@github.com:brianferri/sqlitezig.git
git submodule update --init --recursive --remote
```

In your `build.zig.zon`:

```zig
.dependencies = .{
    .sqlitezig = .{
        .path = "sqlitezig",
    },
},
```

And import it on your `build.zig` file:

```zig
const sqlitezig = b.dependency("sqlitezig", .{ .target = target, .optimize = optimize });

const exe = b.addExecutable(.{
    .name = "your_project",
    .root_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "sqlitezig", .module = sqlitezig.module("sqlitezig") },
        },
    }),
});
b.installArtifact(exe);
```

