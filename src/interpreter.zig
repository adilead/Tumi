const std = @import("std");
const tokenizer = @import("tokenizer.zig");
const tm = @import("tm.zig");
const parser = @import("parser.zig");
const Ast = parser.Ast;
const Token = tokenizer.Token;
const Allocator = std.mem.Allocator;

const Self = @This();

pub fn interpret(allocator: Allocator, ast: *const Ast) !void {
    var turing_machines = std.StringHashMap(tm.TuringMachine).init(allocator);
    defer {
        var it = turing_machines.keyIterator();
        while (it.next()) |name| {
            allocator.free(name.*);
        }
        turing_machines.deinit();
    }
    var t_machine = try tm.TuringMachine.init(allocator);
    defer t_machine.deinit();

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
                try t_machine.states.put(try allocator.dupe(u8, from_state), t_machine.states.keys().len);
            }

            if (t_machine.symbols.get(read_symbol) == null) {
                try t_machine.symbols.put(try allocator.dupe(u8, read_symbol), t_machine.symbols.keys().len);
            }

            if (t_machine.symbols.get(write_symbol) == null) {
                try t_machine.symbols.put(try allocator.dupe(u8, write_symbol), t_machine.symbols.keys().len);
            }

            if (t_machine.states.get(next_state) == null) {
                try t_machine.states.put(try allocator.dupe(u8, next_state), t_machine.states.keys().len);
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
    // for (ast.nodes[0].root.tm_runs) |tr| {

    //     switch(ast.nodes[tr]){
    //         .run => |*run| {},
    //         else => {},

    //     }
    // }
    //build a tape
    //then run
}
