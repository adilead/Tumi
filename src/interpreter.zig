const std = @import("std");
const builtin = @import("builtin");
const tokenizer = @import("tokenizer.zig");
const tm = @import("tm.zig");
const Parser = @import("parser.zig");
const Ast = Parser.Ast;
const Token = tokenizer.Token;
const Allocator = std.mem.Allocator;

const Self = @This();

symbols: std.StringArrayHashMap(usize),
states: std.StringArrayHashMap(usize),
allocator: Allocator,

pub fn init(allocator: Allocator) Self {
    return .{
        .allocator = allocator,
        .symbols = std.StringArrayHashMap(usize).init(allocator),
        .states = std.StringArrayHashMap(usize).init(allocator),
    };
}

pub fn deinit(self: *Self) void {
    self.symbols.deinit();
    self.states.deinit();
}

pub fn interpret(self: *Self, allocator: Allocator, ast: *const Ast) !void {
    var turing_machines = std.StringArrayHashMap(tm.TuringMachine).init(allocator);
    var tapes = std.ArrayList(tm.Tape).init(allocator);
    defer {
        for (turing_machines.keys()) |name| {
            turing_machines.getPtr(name).?.deinit();
            allocator.free(name);
        }
        turing_machines.deinit();
        for (tapes.items) |*t| {
            t.deinit();
        }
        tapes.deinit();
    }
    try self.states.put("<H>", 0);

    //register all turing machines
    for (ast.nodes[0].root.tm_decls) |decl| {
        const name = ast.nodes[ast.nodes[decl].tm_decl.tm_name].symbol.value;
        var t_machine = try tm.TuringMachine.init(allocator, &self.states, &self.symbols, name);
        const trans_nodes = ast.nodes[decl].tm_decl.transitions;
        for (trans_nodes) |tn| {
            const trans_node = ast.nodes[tn].transition;

            const from_state = ast.nodes[trans_node.from_state].symbol.value;
            const read_symbol = ast.nodes[trans_node.read_symbol].symbol.value;
            const write_symbol = ast.nodes[trans_node.write_symbol].symbol.value;
            const move = ast.nodes[trans_node.move].move;
            const next_state = ast.nodes[trans_node.next_state].symbol.value;

            //register states and symbols
            if (self.states.get(from_state) == null) {
                try self.states.putNoClobber(from_state, self.states.keys().len);
            }

            if (self.symbols.get(read_symbol) == null) {
                try self.symbols.putNoClobber(read_symbol, self.symbols.keys().len);
            }

            if (self.symbols.get(write_symbol) == null) {
                try self.symbols.putNoClobber(write_symbol, self.symbols.keys().len);
            }

            if (self.states.get(next_state) == null) {
                try self.states.putNoClobber(next_state, self.states.keys().len);
            }

            //register the transition itself
            const tm_move: tm.Move = switch (move) {
                .move_left => .moveLeft,
                .move_right => .moveRight,
                .stay => .stay,
            };
            var t: tm.Transition = undefined;
            t.from_state = self.states.get(from_state).?;
            t.next_state = self.states.get(next_state).?;
            t.move = tm_move;
            t.read_symbol = self.symbols.get(read_symbol).?;
            t.write_symbol = self.symbols.get(write_symbol).?;

            try t_machine.transitions.putNoClobber([_]usize{ t.from_state, t.read_symbol }, t);
        }
        try turing_machines.putNoClobber(try allocator.dupe(u8, name), t_machine);
    }

    //then, run them using the given command
    for (ast.nodes[0].root.tm_runs) |tr| {
        switch (ast.nodes[tr]) {
            .run => |*run| {
                const name = ast.nodes[run.name].symbol.value;
                var curr_tm = turing_machines.get(name).?;
                const v_nodes = ast.nodes[run.tape].tape.values;

                const tape_values = try allocator.alloc(usize, v_nodes.len);
                defer allocator.free(tape_values);
                for (v_nodes, 0..) |vn, i| {
                    const value = ast.nodes[vn].symbol.value;
                    if (self.symbols.get(value) == null) try self.symbols.putNoClobber(value, self.symbols.keys().len);
                    tape_values[i] = self.symbols.get(value).?;
                }
                try tapes.append(try tm.Tape.init(allocator, tape_values));
                const pos = ast.nodes[run.pos].number.number;
                const start_state = ast.nodes[run.start_state].symbol.value;
                if (!builtin.is_test) {
                    try std.io.getStdOut().writer().print("Running Turing Machine {s}...\n", .{name});
                }
                curr_tm.run(&tapes.items[tapes.items.len - 1], self.states.get(start_state).?, pos) catch |e| {
                    std.debug.print("ERROR\n", .{});
                    try curr_tm.printState(null);
                    return e;
                };
                std.debug.print("SUCCESS\n", .{});
                try curr_tm.printState(null);
            },
            else => {
                unreachable;
            },
        }
    }
}

test "interpret" {
    const allocator = std.testing.allocator;
    const source = "name:\ns 0 1 -> <H>\name2:\nfs rs ws -- ns\n run name 0 s [0,1,2]\n";
    var scanner = tokenizer.Tokenizer.init(source);
    const tokens = try scanner.tokenize(allocator);
    defer tokens.deinit();
    var parser = Parser.init(allocator, tokens.items, source);
    defer parser.deinit();

    var ast = try parser.parse();
    defer ast.deinit();

    var inter = Self.init(allocator);
    defer inter.deinit();

    try inter.interpret(allocator, &ast);
}
