const sqlitezig = @import("sqlitezig");
const std = @import("std");

pub fn main() !void {
    const db: sqlitezig.Database = try .init("test.db", .{});
    defer db.deinit();

    _ = try db.exec("CREATE TABLE IF NOT EXISTS TestTable (name)");
    _ = try db.exec("INSERT OR IGNORE INTO TestTable (name) VALUES ('test')");
}
