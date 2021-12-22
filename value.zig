const std = @import("std");
pub const Value = union(enum) {
    nil: void,
    cons: [2]*Value,
    str: []const u8,
    sym: []const u8,
    int: i64,

    pub const nil = &nil_value;
    var nil_value: Value = .nil;

    pub fn cons(allocator: std.mem.Allocator, a: *Value, b: *Value) !*Value {
        const self = try allocator.create(Value);
        self.* = .{ .cons = .{ a, b } };
        return self;
    }

    pub fn str(allocator: std.mem.Allocator, string: []const u8) !*Value {
        const self = try allocator.create(Value);
        self.* = .{ .str = try allocator.dupe(u8, string) };
        return self;
    }

    pub fn sym(allocator: std.mem.Allocator, symbol: []const u8) !*Value {
        const self = try allocator.create(Value);
        self.* = .{ .sym = try allocator.dupe(u8, symbol) };
        return self;
    }

    pub fn int(allocator: std.mem.Allocator, value: i64) !*Value {
        const self = try allocator.create(Value);
        self.* = .{ .int = value };
        return self;
    }

    pub fn format(self: Value, comptime fmt: []const u8, opts: std.fmt.FormatOptions, writer: anytype) @TypeOf(writer).Error!void {
        switch (self) {
            .nil => try writer.writeAll("'()"),
            .str => |s| try writer.print("\"{}\"", .{std.zig.fmtEscapes(s)}),
            .sym => |s| try writer.writeAll(s),
            .int => |i| try writer.print("{}", .{i}),

            .cons => {
                try writer.writeByte('(');

                try self.cons[0].format(fmt, opts, writer);

                var cell = self.cons[1];
                while (cell.* != .nil) : (cell = cell.cons[1]) {
                    try writer.writeByte(' ');
                    try cell.cons[0].format(fmt, opts, writer);
                }

                try writer.writeByte(')');
            },
        }
    }
};
