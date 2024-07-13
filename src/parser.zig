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
    NotANumber,
};

const Error = struct {
    token_idx: usize,
    message: [:0]u8,
};

const AstNodeTag = enum {
    tm_decl,
    run,
    trace,
    render,
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
    name: AstNodeHandle, //symbol
    pos: AstNodeHandle, //number
    tape: AstNodeHandle, //tape
};

const TmTrace = struct {
    name: AstNodeHandle, //symbol
    pos: AstNodeHandle, //number
    tape: AstNodeHandle, //tape
};

const TmRender = struct {
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
    values: []AstNodeHandle, //symbols

};

const Number = struct {
    number: i32,
};

const Move = enum { move_right, move_left, stay };

const Root = struct {
    tm_decls: []AstNodeHandle,
    tm_runs: []AstNodeHandle,
};

pub const Ast = struct {
    nodes: []AstNode,
    root: AstNodeHandle,
    allocator: Allocator,

    pub fn deinit(self: *Ast) void {
        for (self.nodes) |node| {
            switch (node) {
                .tape => |*tape| self.allocator.free(tape.values),
                .tm_decl => |*tm_decl| self.allocator.free(tm_decl.transitions),
                .root => |*root| {
                    self.allocator.free(root.tm_decls);
                    self.allocator.free(root.tm_runs);
                },
                else => {},
            }
        }
        self.allocator.free(self.nodes);
    }
};

const AstNode = union(AstNodeTag) {
    tm_decl: TmDecl,
    run: TmRun,
    trace: TmTrace,
    render: TmRender,
    tm_name: TmName,
    transition: Transition,
    symbol: Symbol,
    move: Move,
    number: Number,
    tape: Tape,
    root: Root,
};

pub fn printError(self: *Parser) !void {
    for (self.errors.items) |err| {
        std.debug.print("{s}\n", .{err.message});
    }
}

fn consume(self: *Parser, token_type: Token.Tag) !Token {
    const token = self.tokens[self.pos];
    if (self.pos == self.tokens.len) {
        return ParsingError.UnexpectedEof;
    }
    if (token.tag != token_type) {
        try self.errors.append(.{ .token_idx = self.pos, .message = try std.fmt.allocPrintZ(self.allocator, "Unexpected token \"{s}\" of type {s} at {d}", .{ self.source[token.loc.start..token.loc.end], @tagName(token.tag), self.pos }) });
        return ParsingError.UnexpectedToken;
    }
    self.pos += 1;
    self.peek_pos = self.pos;
    return token;
}

fn peek(self: *Parser, ahead: usize) !Token {
    const peek_pos = self.pos + ahead;
    if (peek_pos >= self.tokens.len) {
        return ParsingError.UnexpectedEof;
    }
    const token = self.tokens[peek_pos];
    return token;
}

pub fn parse(self: *Parser) !Ast {
    std.debug.assert(self.tokens[self.tokens.len - 1].tag == .eof);
    var tm_decls = std.ArrayList(AstNodeHandle).init(self.allocator);
    defer tm_decls.deinit();
    var tm_runs = std.ArrayList(AstNodeHandle).init(self.allocator);
    defer tm_runs.deinit();
    try self.nodes.append(undefined);
    while (self.pos < self.tokens.len) {
        if ((try self.peek(0)).tag == .eof) {
            _ = try self.consume(.eof);
            break;
        }
        while ((try self.peek(0)).tag == .symbol and (try self.peek(1)).tag == .colon) {
            try tm_decls.append(try self.parseNode(.tm_decl));
        } else {
            while ((try self.peek(0)).isKeyword()) {
                switch ((try self.peek(0)).tag) {
                    .run => try tm_runs.append(try self.parseNode(.run)),
                    .trace => try tm_runs.append(try self.parseNode(.trace)),
                    .render => try tm_runs.append(try self.parseNode(.render)),
                    else => {
                        unreachable;
                    },
                }
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
            _ = try self.consume(Token.Tag.colon);
            _ = try self.consume(Token.Tag.new_line);

            var transitions = std.ArrayList(AstNodeHandle).init(self.allocator);
            defer transitions.deinit();

            //check if second next token is a symbol
            while ((try self.peek(0)).isKeyword() == false and (try self.peek(0)).tag != .eof and (try self.peek(1)).tag != .colon) {
                try transitions.append(try self.parseNode(.transition));
            }

            const new_node = AstNode{ .tm_decl = .{ .tm_name = name, .transitions = try transitions.toOwnedSlice() } };
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
        .move => {
            const sym_tok = try self.peek(0);
            const move: Move = switch (sym_tok.tag) {
                .move_right => .move_right,
                .move_left => .move_left,
                .stay => .stay,
                else => return ParsingError.UnexpectedToken,
            };
            _ = try self.consume(sym_tok.tag);
            self.nodes.items[handle] = AstNode{ .move = move };
        },
        .run => {
            _ = try self.consume(.run);
            const run_node: TmRun = .{
                .name = try self.parseNode(.symbol),
                .pos = try self.parseNode(.number),
                .tape = try self.parseNode(.tape),
            };
            _ = try self.consume(.new_line);
            self.nodes.items[handle] = AstNode{ .run = run_node };
        },
        .trace => {
            _ = try self.consume(.trace);
            const run_node: TmTrace = .{
                .name = try self.parseNode(.symbol),
                .pos = try self.parseNode(.number),
                .tape = try self.parseNode(.tape),
            };
            _ = try self.consume(.new_line);
            self.nodes.items[handle] = AstNode{ .trace = run_node };
        },
        .render => {
            _ = try self.consume(.render);
            const run_node: TmRender = .{
                .name = try self.parseNode(.symbol),
                .pos = try self.parseNode(.number),
                .tape = try self.parseNode(.tape),
            };
            _ = try self.consume(.new_line);
            self.nodes.items[handle] = AstNode{ .render = run_node };
        },
        .number => {
            const tok = try self.consume(.symbol);
            const val = self.source[tok.loc.start..tok.loc.end];
            const num = std.fmt.parseInt(i32, val, 10) catch {
                return ParsingError.NotANumber;
            };
            self.nodes.items[handle] = AstNode{ .number = .{ .number = num } };
        },
        .tape => {
            _ = try self.consume(.square_bracket_left);
            var syms = std.ArrayList(AstNodeHandle).init(self.allocator);
            defer syms.deinit();
            while ((try self.peek(0)).tag == .symbol) {
                const sym_node = try self.parseNode(.symbol);
                try syms.append(sym_node);
                if ((try self.peek(0)).tag == .square_bracket_right) break;
                _ = try self.consume(.comma);
            }
            _ = try self.consume(.square_bracket_right);
            self.nodes.items[handle] = AstNode{ .tape = .{ .values = try syms.toOwnedSlice() } };
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
    for (self.errors.items) |err| {
        self.allocator.free(err.message);
    }
    self.errors.deinit();
    self.nodes.deinit();
}

test "consume" {
    const allocator = std.testing.allocator;
    const source = "abc --";
    var scanner = tokenizer.Tokenizer.init(source);
    const tokens = try scanner.tokenize(allocator);
    defer tokens.deinit();
    var parser = Parser.init(allocator, tokens.items, source);
    defer parser.deinit();

    const tok1 = try parser.consume(Token.Tag.symbol);
    try std.testing.expectEqual(1, parser.pos);
    try std.testing.expectEqual(Token.Tag.symbol, tok1.tag);

    try std.testing.expectError(ParsingError.UnexpectedToken, parser.consume(Token.Tag.symbol));
    try std.testing.expectEqual(1, parser.pos);
}

test "peek" {
    const allocator = std.testing.allocator;
    var parser = Parser.init(allocator, &[_]Token{ .{ .tag = .symbol, .loc = .{ .start = 0, .end = 10 } }, .{ .tag = .stay, .loc = .{ .start = 0, .end = 10 } } }, "");
    defer parser.deinit();

    const tok1 = try parser.peek(0);
    try std.testing.expectEqual(Token.Tag.symbol, tok1.tag);

    const tok2 = try parser.peek(1);
    try std.testing.expectEqual(Token.Tag.stay, tok2.tag);

    try std.testing.expectEqual(0, parser.pos);
}

test "parse symbol" {
    const allocator = std.testing.allocator;
    var parser = Parser.init(allocator, &[_]Token{ .{ .tag = .symbol, .loc = .{ .start = 0, .end = 5 } }, .{ .tag = .stay, .loc = .{ .start = 0, .end = 10 } } }, "hello --");
    defer parser.deinit();
    const node_idx = try parser.parseNode(.symbol);
    try std.testing.expectEqual(0, node_idx);
    try std.testing.expectEqual(1, parser.nodes.items.len);
    try std.testing.expectEqual(AstNodeTag.symbol, @as(AstNodeTag, parser.nodes.items[0]));
    try std.testing.expectEqualSlices(u8, "hello", parser.nodes.items[0].symbol.value);
}

test "parse number" {
    const allocator = std.testing.allocator;
    const source = "-10\n";
    var scanner = tokenizer.Tokenizer.init(source);
    const tokens = try scanner.tokenize(allocator);
    defer tokens.deinit();
    var parser = Parser.init(allocator, tokens.items, source);
    defer parser.deinit();
    const node_idx = try parser.parseNode(.number);

    try std.testing.expectEqual(0, node_idx);
    try std.testing.expectEqual(1, parser.nodes.items.len);
    try std.testing.expectEqual(AstNodeTag.number, @as(AstNodeTag, parser.nodes.items[0]));
    try std.testing.expectEqual(-10, parser.nodes.items[0].number.number);
}

test "parse tape" {
    const allocator = std.testing.allocator;
    const source = "[a, b, c, ]\n";
    var scanner = tokenizer.Tokenizer.init(source);
    const tokens = try scanner.tokenize(allocator);
    defer tokens.deinit();
    var parser = Parser.init(allocator, tokens.items, source);
    defer parser.deinit();
    const node_idx = try parser.parseNode(.tape);

    try std.testing.expectEqual(0, node_idx);
    try std.testing.expectEqual(4, parser.nodes.items.len);
    try std.testing.expectEqual(AstNodeTag.tape, @as(AstNodeTag, parser.nodes.items[0]));
    defer parser.allocator.free(parser.nodes.items[0].tape.values);

    try std.testing.expectEqual(AstNodeTag.symbol, @as(AstNodeTag, parser.nodes.items[1]));
    try std.testing.expectEqual(AstNodeTag.symbol, @as(AstNodeTag, parser.nodes.items[2]));
    try std.testing.expectEqual(AstNodeTag.symbol, @as(AstNodeTag, parser.nodes.items[3]));

    const tape_node = parser.nodes.items[0];
    try std.testing.expectEqualSlices(AstNodeHandle, &[_]AstNodeHandle{ 1, 2, 3 }, tape_node.tape.values);
}

test "parse run" {
    const allocator = std.testing.allocator;
    const source = "run test 0 [a, b, c, ]\n";
    var scanner = tokenizer.Tokenizer.init(source);
    const tokens = try scanner.tokenize(allocator);
    defer tokens.deinit();
    var parser = Parser.init(allocator, tokens.items, source);
    defer parser.deinit();
    const node_idx = try parser.parseNode(.run);

    try std.testing.expectEqual(0, node_idx);
    try std.testing.expectEqual(7, parser.nodes.items.len);
    try std.testing.expectEqual(AstNodeTag.run, @as(AstNodeTag, parser.nodes.items[node_idx]));

    try std.testing.expectEqual(AstNodeTag.symbol, @as(AstNodeTag, parser.nodes.items[1]));
    try std.testing.expectEqual(AstNodeTag.number, @as(AstNodeTag, parser.nodes.items[2]));
    try std.testing.expectEqual(AstNodeTag.tape, @as(AstNodeTag, parser.nodes.items[3]));
    try std.testing.expectEqual(AstNodeTag.symbol, @as(AstNodeTag, parser.nodes.items[4]));
    try std.testing.expectEqual(AstNodeTag.symbol, @as(AstNodeTag, parser.nodes.items[5]));
    try std.testing.expectEqual(AstNodeTag.symbol, @as(AstNodeTag, parser.nodes.items[6]));

    try std.testing.expectEqual(1, parser.nodes.items[0].run.name);
    try std.testing.expectEqual(2, parser.nodes.items[0].run.pos);
    try std.testing.expectEqual(3, parser.nodes.items[0].run.tape);
    parser.allocator.free(parser.nodes.items[3].tape.values);
}

test "parse trace" {
    const allocator = std.testing.allocator;
    const source = "trace test 0 [a, b, c, ]\n";
    var scanner = tokenizer.Tokenizer.init(source);
    const tokens = try scanner.tokenize(allocator);
    defer tokens.deinit();
    var parser = Parser.init(allocator, tokens.items, source);
    defer parser.deinit();
    const node_idx = try parser.parseNode(.trace);

    try std.testing.expectEqual(0, node_idx);
    try std.testing.expectEqual(7, parser.nodes.items.len);
    try std.testing.expectEqual(AstNodeTag.trace, @as(AstNodeTag, parser.nodes.items[node_idx]));

    try std.testing.expectEqual(AstNodeTag.symbol, @as(AstNodeTag, parser.nodes.items[1]));
    try std.testing.expectEqual(AstNodeTag.number, @as(AstNodeTag, parser.nodes.items[2]));
    try std.testing.expectEqual(AstNodeTag.tape, @as(AstNodeTag, parser.nodes.items[3]));
    try std.testing.expectEqual(AstNodeTag.symbol, @as(AstNodeTag, parser.nodes.items[4]));
    try std.testing.expectEqual(AstNodeTag.symbol, @as(AstNodeTag, parser.nodes.items[5]));
    try std.testing.expectEqual(AstNodeTag.symbol, @as(AstNodeTag, parser.nodes.items[6]));

    try std.testing.expectEqual(1, parser.nodes.items[0].trace.name);
    try std.testing.expectEqual(2, parser.nodes.items[0].trace.pos);
    try std.testing.expectEqual(3, parser.nodes.items[0].trace.tape);

    parser.allocator.free(parser.nodes.items[3].tape.values);
}

test "parse render" {
    const allocator = std.testing.allocator;
    const source = "render test 0 [a, b, c, ]\n";
    var scanner = tokenizer.Tokenizer.init(source);
    const tokens = try scanner.tokenize(allocator);
    defer tokens.deinit();
    var parser = Parser.init(allocator, tokens.items, source);
    defer parser.deinit();
    const node_idx = try parser.parseNode(.render);

    try std.testing.expectEqual(0, node_idx);
    try std.testing.expectEqual(7, parser.nodes.items.len);
    try std.testing.expectEqual(AstNodeTag.render, @as(AstNodeTag, parser.nodes.items[node_idx]));

    try std.testing.expectEqual(AstNodeTag.symbol, @as(AstNodeTag, parser.nodes.items[1]));
    try std.testing.expectEqual(AstNodeTag.number, @as(AstNodeTag, parser.nodes.items[2]));
    try std.testing.expectEqual(AstNodeTag.tape, @as(AstNodeTag, parser.nodes.items[3]));
    try std.testing.expectEqual(AstNodeTag.symbol, @as(AstNodeTag, parser.nodes.items[4]));
    try std.testing.expectEqual(AstNodeTag.symbol, @as(AstNodeTag, parser.nodes.items[5]));
    try std.testing.expectEqual(AstNodeTag.symbol, @as(AstNodeTag, parser.nodes.items[6]));

    try std.testing.expectEqual(1, parser.nodes.items[0].render.name);
    try std.testing.expectEqual(2, parser.nodes.items[0].render.pos);
    try std.testing.expectEqual(3, parser.nodes.items[0].render.tape);

    parser.allocator.free(parser.nodes.items[3].tape.values);
}
test "parse transition" {
    const allocator = std.testing.allocator;
    const source = "from_state read_symbol write_symbol <- <H>\n";
    var scanner = tokenizer.Tokenizer.init(source);
    const tokens = try scanner.tokenize(allocator);
    defer tokens.deinit();
    var parser = Parser.init(allocator, tokens.items, source);
    defer parser.deinit();

    const t_node_idx = try parser.parseNode(.transition);
    try std.testing.expectEqual(0, t_node_idx);
    try std.testing.expectEqual(6, parser.nodes.items.len);
    try std.testing.expectEqual(AstNodeTag.transition, @as(AstNodeTag, parser.nodes.items[0]));
    try std.testing.expectEqual(AstNodeTag.symbol, @as(AstNodeTag, parser.nodes.items[1]));
    try std.testing.expectEqual(AstNodeTag.symbol, @as(AstNodeTag, parser.nodes.items[2]));
    try std.testing.expectEqual(AstNodeTag.symbol, @as(AstNodeTag, parser.nodes.items[3]));
    try std.testing.expectEqual(AstNodeTag.move, @as(AstNodeTag, parser.nodes.items[4]));
    try std.testing.expectEqual(AstNodeTag.symbol, @as(AstNodeTag, parser.nodes.items[5]));

    try std.testing.expectEqual(1, parser.nodes.items[0].transition.from_state);
    try std.testing.expectEqual(2, parser.nodes.items[0].transition.read_symbol);
    try std.testing.expectEqual(3, parser.nodes.items[0].transition.write_symbol);
    try std.testing.expectEqual(4, parser.nodes.items[0].transition.move);
    try std.testing.expectEqual(5, parser.nodes.items[0].transition.next_state);
}

test "parse tm_decl" {
    const allocator = std.testing.allocator;
    const source = "name:\nfrom_state read_symbol write_symbol <- <H>\n";
    var scanner = tokenizer.Tokenizer.init(source);
    const tokens = try scanner.tokenize(allocator);
    defer tokens.deinit();
    var parser = Parser.init(allocator, tokens.items, source);
    defer parser.deinit();

    const node_idx = try parser.parseNode(.tm_decl);
    try std.testing.expectEqual(0, node_idx);
    try std.testing.expectEqual(8, parser.nodes.items.len);
    try std.testing.expectEqual(AstNodeTag.tm_decl, @as(AstNodeTag, parser.nodes.items[0]));
    try std.testing.expectEqual(AstNodeTag.symbol, @as(AstNodeTag, parser.nodes.items[1]));
    try std.testing.expectEqual(AstNodeTag.transition, @as(AstNodeTag, parser.nodes.items[2]));
    try std.testing.expectEqual(AstNodeTag.symbol, @as(AstNodeTag, parser.nodes.items[3]));
    try std.testing.expectEqual(AstNodeTag.symbol, @as(AstNodeTag, parser.nodes.items[4]));
    try std.testing.expectEqual(AstNodeTag.symbol, @as(AstNodeTag, parser.nodes.items[5]));
    try std.testing.expectEqual(AstNodeTag.move, @as(AstNodeTag, parser.nodes.items[6]));
    try std.testing.expectEqual(AstNodeTag.symbol, @as(AstNodeTag, parser.nodes.items[7]));

    try std.testing.expectEqual(1, parser.nodes.items[0].tm_decl.tm_name);
    try std.testing.expectEqualSlices(AstNodeHandle, &[_]AstNodeHandle{2}, parser.nodes.items[0].tm_decl.transitions);
    parser.allocator.free(parser.nodes.items[0].tm_decl.transitions);
}

test "parse ast" {
    const allocator = std.testing.allocator;
    const source = "name:\nfrom_state read_symbol write_symbol <- <H>\name2:\nfs rs ws -- ns\n run name 0 [0,1,2]\n trace name2 1 [0,1]\n";
    var scanner = tokenizer.Tokenizer.init(source);
    const tokens = try scanner.tokenize(allocator);
    defer tokens.deinit();
    var parser = Parser.init(allocator, tokens.items, source);
    defer parser.deinit();

    var ast = try parser.parse();
    defer ast.deinit();

    // try std.testing.expectEqual(8, ast.nodes.len);
    try std.testing.expectEqual(AstNodeTag.root, @as(AstNodeTag, ast.nodes[0]));
    const root = ast.nodes[0].root;
    try std.testing.expectEqual(2, root.tm_decls.len);
    try std.testing.expectEqual(2, root.tm_runs.len);

    try std.testing.expectEqual(AstNodeTag.tm_decl, @as(AstNodeTag, ast.nodes[root.tm_decls[0]]));
    try std.testing.expectEqual(AstNodeTag.tm_decl, @as(AstNodeTag, ast.nodes[root.tm_decls[1]]));
    try std.testing.expectEqual(AstNodeTag.run, @as(AstNodeTag, ast.nodes[root.tm_runs[0]]));
    try std.testing.expectEqual(AstNodeTag.trace, @as(AstNodeTag, ast.nodes[root.tm_runs[1]]));
}
