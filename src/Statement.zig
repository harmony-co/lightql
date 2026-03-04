const shared = @import("./shared.zig");
const sqlite = @import("sqlite");
const std = @import("std");

const Database = @import("./Database.zig");
const parseResultCode = shared.parseResultCode;
const ErrorCodes = shared.ErrorCodes;
const OkCodes = shared.OkCodes;

const Statement = @This();

stmt: *sqlite.sqlite3_stmt,
db: *sqlite.sqlite3,
/// Keeps track of the current binding
pos: u8 = 1,
col: u8 = 0,

pub fn init(db: *Database, query: [:0]const u8) ErrorCodes!Statement {
    var stmt: ?*sqlite.sqlite3_stmt = undefined;
    const result = sqlite.sqlite3_prepare_v2(db.db.?, query, @intCast(query.len), &stmt, null);

    _ = try parseResultCode(result);

    return .{
        .stmt = stmt.?,
        .db = db.db.?,
    };
}

pub fn step(self: *const Statement) ErrorCodes!OkCodes {
    const result = sqlite.sqlite3_step(self.stmt);
    return parseResultCode(result);
}

pub fn clear(self: *const Statement) ErrorCodes!OkCodes {
    @constCast(self).pos = 1;
    const result = sqlite.sqlite3_clear_bindings(self.stmt);
    return parseResultCode(result);
}

pub fn reset(self: *const Statement) ErrorCodes!OkCodes {
    @constCast(self).col = 0;
    const result = sqlite.sqlite3_reset(self.stmt);
    return parseResultCode(result);
}

pub fn clearAndReset(self: *const Statement) !void {
    _ = try self.clear();
    _ = try self.reset();
}

pub fn deinit(self: *const Statement) ErrorCodes!OkCodes {
    const result = sqlite.sqlite3_finalize(self.stmt);
    return parseResultCode(result);
}

pub fn bindNull(self: *const Statement) ErrorCodes!void {
    defer @constCast(self).pos += 1;
    const result = sqlite.sqlite3_bind_null(self.stmt, @intCast(self.pos));
    _ = try parseResultCode(result);
}

pub fn bindText(self: *const Statement, text: []const u8) ErrorCodes!void {
    defer @constCast(self).pos += 1;

    // TODO: Check if transient really is the best option for us
    const result = sqlite.sqlite3_bind_text(self.stmt, @intCast(self.pos), text.ptr, @as(c_int, @intCast(text.len)), sqlite.SQLITE_TRANSIENT);
    _ = try parseResultCode(result);
}

pub fn bindBlob(self: *const Statement, blob: []const u8) ErrorCodes!void {
    defer @constCast(self).pos += 1;

    // TODO: Check if transient really is the best option for us
    const result = sqlite.sqlite3_bind_blob(self.stmt, @intCast(self.pos), blob.ptr, @as(c_int, @intCast(blob.len)), null);
    _ = try parseResultCode(result);
}

pub fn bindInt(self: *const Statement, int: i64) ErrorCodes!void {
    defer @constCast(self).pos += 1;
    const result = sqlite.sqlite3_bind_int64(self.stmt, @intCast(self.pos), int);
    _ = try parseResultCode(result);
}

pub fn bindUInt(self: *const Statement, int: u64) ErrorCodes!void {
    defer @constCast(self).pos += 1;
    const result = sqlite.sqlite3_bind_int64(self.stmt, @intCast(self.pos), @bitCast(int));
    _ = try parseResultCode(result);
}

pub fn bindFloat(self: *const Statement, float: f64) ErrorCodes!void {
    defer @constCast(self).pos += 1;
    const result = sqlite.sqlite3_bind_double(self.stmt, @intCast(self.pos), float);
    _ = try parseResultCode(result);
}

pub const CArrayType = enum(c_int) {
    i32,
    i64,
    float,
    text,
    blob,
};

fn CArray(comptime T: CArrayType) type {
    return switch (T) {
        .blob, .text => []u8,
        .i32 => []i32,
        .i64 => []i64,
        .float => []f64,
    };
}

fn parseArrayType(comptime arr: anytype) CArrayType {
    switch (@typeInfo(@TypeOf(arr))) {
        .pointer => |ptr_info| {
            if (ptr_info.size != .slice) @compileError("Only slices are allowed");
            switch (@typeInfo(ptr_info.child)) {
                .int => |int| {
                    if (int.signedness == .unsigned and int.bits == 8) return .text;
                    if (int.bits == 32) return .i32;
                    if (int.bits == 64) return .i64;
                    @compileError("Invalid integer size");
                },
                .float => |float| {
                    if (float.bits == 64) return .float;
                    @compileError("Invalid float size");
                },
                else => @compileError("Invalid array type"),
            }
        },
        else => @compileError("Invalid type"),
    }
}

/// For binding blobs use `bindCArray`
pub fn bindCArrayAuto(self: *const Statement, arr: anytype) ErrorCodes!void {
    defer @constCast(self).pos += 1;
    const result = sqlite.sqlite3_carray_bind(self.stmt, @intCast(self.pos), arr.ptr, @as(c_int, @intCast(arr.len)), parseArrayType(arr), null);
    _ = try parseResultCode(result);
}

pub fn bindCArray(self: *const Statement, comptime T: CArrayType, arr: CArray(T)) ErrorCodes!void {
    defer @constCast(self).pos += 1;
    const result = sqlite.sqlite3_carray_bind(self.stmt, @intCast(self.pos), arr.ptr, @as(c_int, @intCast(arr.len)), @intFromEnum(T), null);
    _ = try parseResultCode(result);
}

pub fn textColumn(self: *const Statement, allocator: std.mem.Allocator) ![]const u8 {
    defer @constCast(self).col += 1;
    const text = sqlite.sqlite3_column_text(self.stmt, @intCast(self.col));
    const len: usize = @intCast(sqlite.sqlite3_column_bytes(self.stmt, @intCast(self.col)));

    return try allocator.dupe(u8, text[0..len]);
}

pub fn blobColumn(self: *const Statement, allocator: std.mem.Allocator) ![]const u8 {
    defer @constCast(self).col += 1;
    const blob: [*c]const u8 = @ptrCast(sqlite.sqlite3_column_blob(self.stmt, @intCast(self.col)));
    const len: usize = @intCast(sqlite.sqlite3_column_bytes(self.stmt, @intCast(self.col)));

    return try allocator.dupe(u8, blob[0..len]);
}

pub fn intColumn(self: *const Statement) i64 {
    defer @constCast(self).col += 1;
    return sqlite.sqlite3_column_int64(self.stmt, @intCast(self.col));
}

pub fn uIntColumn(self: *const Statement) u64 {
    defer @constCast(self).col += 1;
    return @bitCast(sqlite.sqlite3_column_int64(self.stmt, @intCast(self.col)));
}

pub fn floatColumn(self: *const Statement) f64 {
    defer @constCast(self).col += 1;
    return sqlite.sqlite3_column_double(self.stmt, @intCast(self.col));
}

pub fn columnCount(self: *const Statement) i32 {
    return sqlite.sqlite3_column_count(self.stmt);
}

pub fn dataCount(self: *const Statement) i32 {
    return sqlite.sqlite3_data_count(self.stmt);
}

pub fn changes(self: *const Statement) i64 {
    return sqlite.sqlite3_changes64(self.db);
}

pub const ColumnType = enum(u8) {
    integer = sqlite.SQLITE_INTEGER,
    float = sqlite.SQLITE_FLOAT,
    blob = sqlite.SQLITE_BLOB,
    null = sqlite.SQLITE_NULL,
    text = sqlite.SQLITE_TEXT,
};

pub fn columnIs(self: *const Statement, t: ColumnType) bool {
    return sqlite.sqlite3_column_type(self.stmt, @intCast(self.col)) == @intFromEnum(t);
}

/// If type is `t` advance col by 1
pub fn columnIsSkip(self: *const Statement, t: ColumnType) bool {
    if (sqlite.sqlite3_column_type(self.stmt, @intCast(self.col)) == @intFromEnum(t)) {
        @constCast(self).col += 1;
        return true;
    }

    return false;
}
