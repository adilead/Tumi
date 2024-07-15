const std = @import("std");
const tokenizer = @import("tokenizer.zig");
const tm = @import("tm.zig");
const Parser = @import("parser.zig");
const Ast = Parser.Ast;
const Token = tokenizer.Token;
const Allocator = std.mem.Allocator;

const Self = @This();

pub fn interpret(allocator: Allocator, ast: *const Ast) !void {
    var turing_machines = std.StringArrayHashMap(tm.TuringMachine).init(allocator);
    var tapes = std.ArrayList(tm.Tape).init(allocator);
    defer {
        for (turing_machines.keys()) |name| {
            allocator.free(name);
        }
        turing_machines.deinit();
        for (tapes.items) |*t| {
            t.deinit();
        }
        tapes.deinit();
    }
    var t_machine = try tm.TuringMachine.init(allocator);
    defer t_machine.deinit();
    try t_machine.states.put("<H>", 0);

    //register all turing machines
    for (ast.nodes[0].root.tm_decls) |decl| {
        const name = ast.nodes[ast.nodes[decl].tm_decl.tm_name].symbol.value;
        const trans_nodes = ast.nodes[decl].tm_decl.transitions;
        for (trans_nodes) |tn| {
            const trans_node = ast.nodes[tn].transition;

            const from_state = ast.nodes[trans_node.from_state].symbol.value;
            const read_symbol = ast.nodes[trans_node.read_symbol].symbol.value;
            const write_symbol = ast.nodes[trans_node.write_symbol].symbol.value;
            const move = ast.nodes[trans_node.move].move;
            const next_state = ast.nodes[trans_node.next_state].symbol.value;

            //register states and symbols
            if (t_machine.states.get(from_state) == null) {
                try t_machine.states.put(from_state, t_machine.states.keys().len);
            }

            if (t_machine.symbols.get(read_symbol) == null) {
                try t_machine.symbols.put(read_symbol, t_machine.symbols.keys().len);
            }

            if (t_machine.symbols.get(write_symbol) == null) {
                try t_machine.symbols.put(write_symbol, t_machine.symbols.keys().len);
            }

            if (t_machine.states.get(next_state) == null) {
                try t_machine.states.put(next_state, t_machine.states.keys().len);
            }

            //register the transition itself
            const tm_move: tm.Move = switch (move) {
                .move_left => .moveLeft,
                .move_right => .moveRight,
                .stay => .stay,
            };
            var t: tm.Transition = undefined;
            t.from_state = t_machine.states.get(from_state).?;
            t.next_state = t_machine.states.get(next_state).?;
            t.move = tm_move;
            t.read_symbol = t_machine.symbols.get(read_symbol).?;
            t.write_symbol = t_machine.symbols.get(write_symbol).?;

            try t_machine.transitions.put([_]usize{ t_machine.states.get(from_state).?, t_machine.symbols.get(read_symbol).? }, t);
        }
        try turing_machines.put(try allocator.dupe(u8, name), t_machine);
    }

    //then, run them using the given command
    for (ast.nodes[0].root.tm_runs) |tr| {
        switch (ast.nodes[tr]) {
            .run => |*run| {
                const name = ast.nodes[run.name].symbol.value;
                var curr_tm = turing_machines.get(name).?;
                try tapes.append(try tm.Tape.init(allocator, ast.nodes[run.tape].tape.values));
                const pos = ast.nodes[run.pos].number.number;
                const start_state = ast.nodes[run.start_state].symbol.value;
                try std.io.getStdOut().writer().print("Running Turing Machine {s}...\n", .{name});
                try curr_tm.run(&tapes.items[tapes.items.len - 1], curr_tm.states.get(start_state).?, pos);
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

    try interpret(allocator, &ast);
}
