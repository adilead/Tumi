const std = @import("std");
const Allocator = std.mem.Allocator;

//Inspired by std/zig/tokenizer.zig

//TODO remove empty lines -> if last token is a \n, don't add new ones

pub const Token = struct {
    tag: Tag,
    loc: Loc,

    pub const Loc = struct {
        start: usize,
        end: usize,
    };

    pub const keywords = std.StaticStringMap(Tag).initComptime(.{ .{ "run", .run }, .{ "trace", .trace }, .{ "render", .render }, .{ "->", .move_right }, .{ "<-", .move_left }, .{ "--", .stay } });

    pub const Tag = enum { run, trace, render, halt, square_bracket_left, square_bracket_right, colon, move_left, move_right, stay, new_line, comma, symbol, invalid, eof };

    pub fn lexeme(tag: Tag) ?[]const u8 {
        return switch (tag) {
            .symbol => "symbol",
            .run => "run",
            .trace => "trace",
            .render => "render",
            .halt => "<H>",
            .square_bracket_left => "[",
            .square_bracket_right => "]",
            .colon => ":",
            .move_left => "<-",
            .move_right => "->",
            .stay => ".",
            .new_line => "\n",
            .comma => ",",
            .invalid => "invalid",
            .eof => "eof",
        };
    }

    pub fn getKeyword(bytes: []const u8) ?Tag {
        return keywords.get(bytes);
    }

    pub fn isKeyword(self: *const Token) bool {
        return keywords.get(lexeme(self.tag).?) != null;
    }
};

pub const Tokenizer = struct {
    buff: [:0]const u8,
    index: usize,

    pub fn init(buff: [:0]const u8) Tokenizer {
        const src_start: usize = if (std.mem.startsWith(u8, buff, "\xEF\xBB\xBF")) 3 else 0;
        return Tokenizer{ .buff = buff, .index = src_start };
    }

    /// For debugging purposes
    pub fn dump(self: *Tokenizer, token: *const Token) void {
        std.debug.print("{s} \"{s}\" {d}\n", .{ @tagName(token.tag), self.buff[token.loc.start..token.loc.end], self.index });
    }

    const State = enum { start, symbol, halt, run, trace, render };

    pub fn next(self: *@This()) Token {
        var result = Token{
            .tag = .eof,
            .loc = .{
                .start = self.index,
                .end = undefined,
            },
        };

        var state: State = .start;
        while (true) : (self.index += 1) {
            const c = self.buff[self.index];
            switch (state) {
                .start => switch (c) {
                    0 => {
                        if (self.index != self.buff.len) {
                            result.tag = .invalid;
                            result.loc.start = self.index;
                            self.index += 1;
                            result.loc.end = self.index;
                            return result;
                        }
                        break;
                    },
                    ' ' => {
                        result.loc.start = self.index + 1;
                    },
                    '\n' => {
                        result.tag = .new_line;
                        self.index += 1;
                        break;
                    },
                    '[' => {
                        result.tag = .square_bracket_left;
                        self.index += 1;
                        break;
                    },
                    ']' => {
                        result.tag = .square_bracket_right;
                        self.index += 1;
                        break;
                    },
                    ':' => {
                        result.tag = .colon;
                        self.index += 1;
                        break;
                    },
                    ',' => {
                        result.tag = .comma;
                        self.index += 1;
                        break;
                    },
                    'a'...'z', 'A'...'Z', '_', '0'...'9', '-', '<', '>', '.' => {
                        result.tag = .symbol;
                        state = .symbol;
                    },
                    else => {},
                },
                .symbol => switch (c) {
                    'a'...'z', 'A'...'Z', '_', '0'...'9', '-', '<', '>', '.' => {},
                    else => {
                        if (Token.getKeyword(self.buff[result.loc.start..self.index])) |tag| {
                            result.tag = tag;
                        }
                        break;
                    },
                },
                else => {},
            }
        }
        if (result.tag == .eof) result.loc.start = self.index;
        result.loc.end = self.index;
        return result;
    }

    pub fn tokenize(self: *@This(), allocator: Allocator) !std.ArrayList(Token) {
        // _ = self;
        var token_list = std.ArrayList(Token).init(allocator);
        errdefer {
            token_list.deinit();
        }
        // const next_token: Token = undefined;
        var token = self.next();
        while (token.tag != .eof) : (token = self.next()) {
            if (token.tag == .new_line and (token_list.items.len == 0 or token_list.items[token_list.items.len - 1].tag == .new_line)) {
                continue;
            }
            try token_list.append(token);
        }
        try token_list.append(token);
        return token_list;
    }
};

test "keywords" {
    try testTokenize("run trace render <H> -> <- --", &.{ .run, .trace, .render, .symbol, .move_right, .move_left, .stay }, &[_][]const u8{ "run", "trace", "render", "<H>", "->", "<-", "--" });
}

test "symbols" {
    try testTokenize("99 H here h29-j", &.{ .symbol, .symbol, .symbol, .symbol }, null);
}

test "wrong zero byte" {
    try testTokenize("99 \x00 11", &.{ .symbol, .invalid, .symbol }, null);
}

test "new lines" {
    try testTokenize("\n\nhello\n\n", &.{ .symbol, .new_line }, null);
}

test "brackets" {
    try testTokenize("[]", &.{ .square_bracket_left, .square_bracket_right }, &[_][]const u8{ "[", "]" });
}

test "run" {
    try testTokenize(" run name 0 x [0,1] ", &.{ .run, .symbol, .symbol, .symbol, .square_bracket_left, .symbol, .comma, .symbol, .square_bracket_right }, &[_][]const u8{ "run", "name", "0", "x", "[", "0", ",", "1", "]" });
}

test "colon" {
    try testTokenize(":", &.{.colon}, null);
}

test "empty file" {
    try testTokenize("", &.{}, null);
}

test "tokenize" {
    const alloc = std.testing.allocator;
    const buff = "TM1:\nasdf 0 1 -> H\n";
    var tokenizer = Tokenizer.init(buff);
    const tokens: std.ArrayList(Token) = try tokenizer.tokenize(alloc);
    defer tokens.deinit();
    const expected_tags = [_]Token.Tag{ .symbol, .colon, .new_line, .symbol, .symbol, .symbol, .move_right, .symbol, .new_line, .eof };
    try std.testing.expectEqual(expected_tags.len, tokens.items.len);
    for (0..expected_tags.len) |i| {
        try std.testing.expectEqual(expected_tags[i], tokens.items[i].tag);
    }
}

fn testTokenize(source: [:0]const u8, expected_token_tags: []const Token.Tag, expected_values: ?[]const []const u8) !void {
    var tokenizer = Tokenizer.init(source);
    const tokens = try tokenizer.tokenize(std.testing.allocator);
    defer tokens.deinit();
    for (expected_token_tags, 0..) |expected_token_tag, i| {
        // const token = tokenizer.next();
        try std.testing.expectEqual(expected_token_tag, tokens.items[i].tag);
        if (expected_values) |values| {
            try std.testing.expectEqualStrings(values[i], source[tokens.items[i].loc.start..tokens.items[i].loc.end]);
        }
    }
    const last_token = tokenizer.next();
    try std.testing.expectEqual(Token.Tag.eof, last_token.tag);
    try std.testing.expectEqual(source.len, last_token.loc.start);
    try std.testing.expectEqual(source.len, last_token.loc.end);
}
