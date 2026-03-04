const shared = @import("./shared.zig");
const sqlite = @import("sqlite");
const std = @import("std");

const parseResultCode = shared.parseResultCode;
pub const ErrorCodes = shared.ErrorCodes;
pub const OkCodes = shared.OkCodes;

pub const Database = @This();

db: ?*sqlite.sqlite3,

pub const DatabaseInitOptions = struct {
    readonly: bool = false,
    auto_create: bool = true,
    /// Interpret the filename as a URI
    is_uri: bool = false,
    /// Open the db as an in memory db
    in_memory: bool = false,
    /// Allow symlinks as your filename
    follow: bool = false,
};

pub fn init(name: [*c]const u8, options: DatabaseInitOptions) !Database {
    var db: ?*sqlite.sqlite3 = undefined;

    var flags = if (options.readonly) sqlite.SQLITE_OPEN_READONLY else sqlite.SQLITE_OPEN_READWRITE;
    if (options.auto_create) flags |= sqlite.SQLITE_OPEN_CREATE;
    if (options.is_uri) flags |= sqlite.SQLITE_OPEN_URI;
    if (options.in_memory) flags |= sqlite.SQLITE_OPEN_MEMORY;
    if (!options.follow) flags |= sqlite.SQLITE_OPEN_NOFOLLOW;

    if (sqlite.sqlite3_open_v2(name, &db, flags, null) != sqlite.SQLITE_OK) return error.FailedToOpenDatabase;

    return .{
        .db = db,
    };
}

pub fn deinit(self: *const Database) void {
    _ = sqlite.sqlite3_close_v2(self.db);
}

/// Please don't use this for `SELECT` as it wont return anything
pub fn exec(self: *const Database, query: [:0]const u8) ErrorCodes!OkCodes {
    const result = sqlite.sqlite3_exec(self.db, query, null, null, null);
    return parseResultCode(result);
}

pub fn enableExtensionLoading(self: *const Database) !void {
    const result = sqlite.sqlite3_db_config(self.db, sqlite.SQLITE_DBCONFIG_ENABLE_LOAD_EXTENSION, @as(c_int, 1), @as(c_int, 0));
    if (result != sqlite.SQLITE_OK) return error.FailedToEnableExtensions;
}

pub fn loadExtension(self: *const Database, path: [:0]const u8, init_fn_name: [:0]const u8) !void {
    const result = sqlite.sqlite3_load_extension(self.db, path, init_fn_name, null);
    if (result != sqlite.SQLITE_OK) return error.FailedToLoadExtension;
}
