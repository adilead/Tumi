const std = @import("std");
const tokenizer = @import("tokenizer.zig");
const Token = tokenizer.Token;
const Allocator = std.mem.Allocator;

const AstNodeHandle = usize;
const Parser = @This();

source: [:0]const u8,
pos: usize,
peek_pos: usize,
tokens: []const Token,
allocator: Allocator,

errors: std.ArrayList(Error),
nodes: std.ArrayList(AstNode),

pub const ParsingError = error{
    ParsingIsFucked,
    UnexpectedToken,
    UnexpectedEof,
};

const Error = struct {
    token_idx: usize,
};

const AstNodeTag = enum {
    tm_decl,
    tm_run,
    tm_name,
    transition,
    symbol,
    move,
    number,
    tape,
    root,
};

const TmDecl = struct {
    tm_name: AstNodeHandle,
    transitions: []AstNodeHandle,
};

const TmRun = struct {
    instruction: AstNodeHandle, //symbol
    name: AstNodeHandle, //symbol
    pos: AstNodeHandle, //number
    tape: AstNodeHandle, //tape
};

const TmName = struct {
    symbol: AstNodeHandle,
};

const Transition = struct {
    from_state: AstNodeHandle,
    read_symbol: AstNodeHandle,
    write_symbol: AstNodeHandle,
    move: AstNodeHandle,
    next_state: AstNodeHandle,
};
const Symbol = struct {
    value: []const u8,
};

const Tape = struct {
    value: []AstNodeHandle,
};

const Number = struct {
    number: i32,
};

const Move = enum { moveRight, moveLeft, stay };

const Root = struct {
    tm_decls: []AstNodeHandle,
    tm_runs: []AstNodeHandle,
};

pub const Ast = struct {
    nodes: []AstNode,
    root: AstNodeHandle,
    allocator: Allocator,

    pub fn deinit(self: *Ast) void {
        self.allocator.free(self.nodes);
    }
};

const AstNode = union(AstNodeTag) {
    tm_decl: TmDecl,
    tm_run: TmRun,
    tm_name: TmName,
    transition: Transition,
    symbol: Symbol,
    move: Move,
    number: Number,
    tape: Tape,
    root: Root,
};

fn consume(self: *Parser, token_type: Token.Tag) !Token {
    const token = self.tokens[self.pos];
    if (self.pos == self.tokens.len) {
        return ParsingError.UnexpectedEof;
    }
    if (token.tag != token_type) {
        try self.errors.append(.{ .token_idx = self.pos });
        return ParsingError.UnexpectedToken;
    }
    self.pos += 1;
    self.peek_pos = self.pos;
    return token;
}

fn peek(self: *Parser, ahead: usize) !Token {
    self.peek_pos += ahead;
    const token = self.tokens[self.peek_pos];
    if (self.peek_pos == self.tokens.len) {
        return ParsingError.UnexpectedEof;
    }
    return token;
}

pub fn parse(self: *Parser) !Ast {
    var tm_decls = std.ArrayList(AstNodeHandle).init(self.allocator);
    defer tm_decls.deinit();
    var tm_runs = std.ArrayList(AstNodeHandle).init(self.allocator);
    defer tm_runs.deinit();
    try self.nodes.append(undefined);
    while (self.pos < self.tokens.len) {
        while ((try self.peek(0)).tag == .symbol and (try self.peek(1)).tag == .colon) {
            try tm_decls.append(try self.parseNode(.tm_decl));
        } else {
            try tm_runs.append(try self.parseNode(.tm_run));
            while ((try self.peek(0)).isKeyword()) {
                try tm_runs.append(try self.parseNode(.tm_run));
            }
        }
    }
    self.nodes.items[0] = .{ .root = .{ .tm_decls = try tm_decls.toOwnedSlice(), .tm_runs = try tm_runs.toOwnedSlice() } };
    return .{ .nodes = try self.nodes.toOwnedSlice(), .root = 0, .allocator = self.allocator };
}

pub fn parseNode(self: *Parser, tag: AstNodeTag) !AstNodeHandle {
    try self.nodes.append(undefined);
    const handle = self.nodes.items.len - 1;
    switch (tag) {
        .tm_decl => {
            const name = try self.parseNode(.symbol);
            _ = name;
            _ = try self.consume(Token.Tag.colon);
            _ = try self.consume(Token.Tag.new_line);

            var transitions = std.ArrayList(AstNodeHandle).init(self.allocator);
            defer transitions.deinit();

            //check if second next token is a symbol
            while ((try self.peek(0)).isKeyword() == false and (try self.peek(1)).tag != .symbol) {
                try transitions.append(try self.parseNode(.transition));
            }

            const new_node = AstNode{ .tm_decl = undefined };
            self.nodes.items[handle] = new_node;
        },
        .transition => {
            var transition: Transition = undefined;
            transition.from_state = try self.parseNode(.symbol);
            transition.read_symbol = try self.parseNode(.symbol);
            transition.write_symbol = try self.parseNode(.symbol);
            transition.move = try self.parseNode(.move);
            transition.next_state = try self.parseNode(.symbol);
            _ = try self.consume(.new_line);

            const new_node = AstNode{ .transition = transition };
            self.nodes.items[handle] = new_node;
        },
        .symbol => {
            const sym_tok = try self.consume(.symbol);
            const new_node = AstNode{ .symbol = .{ .value = self.source[sym_tok.loc.start..sym_tok.loc.end] } };
            self.nodes.items[handle] = new_node;
        },
        else => {
            unreachable;
        },
    }
    return handle;
}

pub fn init(allocator: Allocator, tokens: []const Token, source: [:0]const u8) Parser {
    return .{
        .allocator = allocator,
        .source = source,
        .pos = 0,
        .peek_pos = 0,
        .tokens = tokens,
        .nodes = std.ArrayList(AstNode).init(allocator),
        .errors = std.ArrayList(Error).init(allocator),
    };
}

pub fn deinit(self: *Parser) void {
    self.errors.deinit();
    self.nodes.deinit();
}

test "consume" {
    const allocator = std.testing.allocator;
    var parser = Parser.init(allocator, &[_]Token{ .{ .tag = .symbol, .loc = .{ .start = 0, .end = 10 } }, .{ .tag = .stay, .loc = .{ .start = 0, .end = 10 } } });
    defer parser.deinit();

    const tok1 = try parser.consume(Token.Tag.symbol);
    try std.testing.expectEqual(1, parser.pos);
    try std.testing.expectEqual(Token.Tag.symbol, tok1.tag);

    try std.testing.expectError(ParsingError.UnexpectedToken, parser.consume(Token.Tag.symbol));
    try std.testing.expectEqual(1, parser.pos);
}
