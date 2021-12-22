const std = @import("std");
const Value = @import("value.zig").Value;

/// Parses a list of values from the provided code slice. Destructively modifies code.
/// No allocations are performed other than to create the returned values.
pub fn parse(allocator: std.mem.Allocator, code: []u8) ParseError!*Value {
    var toks = Tokenizer.init(code);
    return parseList(allocator, &toks, .eof);
}
pub const ParseError = error{
    EndOfStream,
    InvalidToken,
    UnexpectedToken,
    Overflow,
    OutOfMemory,
};

fn parseList(allocator: std.mem.Allocator, toks: *Tokenizer, end: Token.Tag) ParseError!*Value {
    var val = Value.nil;
    var tail: ?*Value = null;
    while (true) {
        const tok = toks.next();
        if (tok.tag == end) break;

        const parsed = try parseValue(allocator, toks, tok);

        const v = if (tail) |t| &t.cons[1] else &val;
        std.debug.assert(v.* == Value.nil);

        v.* = try Value.cons(allocator, parsed, Value.nil);
        tail = v.*;
    }
    return val;
}

fn parseValue(allocator: std.mem.Allocator, toks: *Tokenizer, tok: Token) ParseError!*Value {
    return switch (tok.tag) {
        .eof => error.EndOfStream,
        .invalid => error.InvalidToken,
        .@")" => error.UnexpectedToken,

        .@"(" => try parseList(allocator, toks, .@")"),
        .@"'" => try Value.cons(
            allocator,
            try Value.sym(allocator, "quote"),
            try Value.cons(
                allocator,
                try parseValue(allocator, toks, toks.next()),
                Value.nil,
            ),
        ),

        .integer => try Value.int(allocator, std.fmt.parseInt(i64, tok.text, 0) catch |err| switch (err) {
            error.InvalidCharacter => unreachable,
            else => |e| return e,
        }),
        .string => try Value.str(allocator, tok.text[1 .. tok.text.len - 1]),
        .symbol => try Value.sym(allocator, tok.text),
    };
}

const Token = struct {
    tag: Tag,
    text: []const u8,

    const Tag = enum {
        eof,
        invalid,
        @"(",
        @")",
        @"'",
        integer,
        string,
        symbol,
    };
};

const Tokenizer = struct {
    code: []u8,

    pub fn init(code: []u8) Tokenizer {
        var self = Tokenizer{ .code = code };
        self.skipSpace();
        return self;
    }

    fn skipSpace(self: *Tokenizer) void {
        while (self.code.len > 0 and std.ascii.isSpace(self.code[0])) {
            self.code = self.code[1..];
        }
    }

    pub fn next(self: *Tokenizer) Token {
        if (self.code.len == 0) {
            return .{ .tag = .eof, .text = "" };
        }

        var end: usize = 1;
        const tag: Token.Tag = switch (self.code[0]) {
            0x00...0x20, 0x7f...0xff => .invalid, // non-printing chars

            '(' => .@"(",
            ')' => .@")",
            '\'' => .@"'",

            '-', '0'...'9' => while (end < self.code.len and isDigit(self.code[end])) {
                end += 1;
            } else .integer,

            '"' => while (end < self.code.len) {
                const c = self.code[end];
                end += 1;
                switch (c) {
                    '"' => break Token.Tag.string,
                    '\\' => end += 1,
                    else => {},
                }
            } else .invalid,

            else => while (end < self.code.len and isSymbol(self.code[end])) {
                end += 1;
            } else .symbol,
        };

        const tok: Token = .{
            .tag = tag,
            .text = self.code[0..end],
        };

        self.code = self.code[end..];
        self.skipSpace();
        return tok;
    }

    inline fn isSymbol(c: u8) bool {
        return switch (c) {
            0x00...0x20, 0x7f...0xff => false, // non-printing chars
            '(', ')', '"' => false, // Reserved
            else => true,
        };
    }
    inline fn isDigit(c: u8) bool {
        return switch (c) {
            '0'...'9' => true,
            else => false,
        };
    }
};

test "Parse simple s-expr" {
    var code =
        \\"Hello, world!"
        \\(foo '(bar baz) 'quux)
        \\0 1 2 3 4 -1 -2 -3
    .*;

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const v = try parse(arena.allocator(), &code);
    try std.testing.expectEqualStrings(
        \\("Hello, world!" (foo (quote (bar baz)) (quote quux)) 0 1 2 3 4 -1 -2 -3)
    , try std.fmt.allocPrint(arena.allocator(), "{}", .{v}));
}

test "String escapes" {
    var code =
        \\"a\"b"
        \\"a\nb"
        \\"a\tb"
        \\"a\x00b"
    .*;

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const v = try parse(arena.allocator(), &code);
    try std.testing.expectEqualStrings(
        \\("a\"b" "a\nb" "a\tb" "a\x00b")
    , try std.fmt.allocPrint(arena.allocator(), "{}", .{v}));
}
