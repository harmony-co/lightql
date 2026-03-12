## lightql

Build SQLite with a minimal setup, using zig

## Installation

```sh
zig fetch --save git+https://github.com/harmony-co/lightql
```

And import it on your `build.zig` file:

```zig
const lightql = b.dependency("lightql", .{ .target = target, .optimize = optimize });

const exe = b.addExecutable(.{
    .name = "your_project",
    .root_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "lightql", .module = lightql.module("lightql") },
        },
    }),
});
b.installArtifact(exe);
```

