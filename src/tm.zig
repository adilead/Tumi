const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Move = enum {
    moveLeft,
    moveRight,
    stay,
};

const HALT: usize = 0;
const BLANK: usize = 0;
var chunk_size: usize = 512;

pub const TuringMachine = struct {
    //TODO Think about moving the lookup stuff to parsing
    states: std.StringArrayHashMap(usize), //does not own keys
    symbols: std.StringArrayHashMap(usize), //does not own keys
    curr_state: usize,
    transitions: std.AutoHashMap([2]usize, Transition), //looks up transitions for a state and read symbol, owns all data
    pos: i32, //position of the head, we used a signed integer as the head can move to the left as long as it wants
    allocator: Allocator,
    pub fn init(alloc: Allocator) !TuringMachine {
        return .{
            .states = std.StringArrayHashMap(usize).init(alloc),
            .symbols = std.StringArrayHashMap(usize).init(alloc),
            .curr_state = 0,
            .transitions = std.AutoHashMap([2]usize, Transition).init(alloc),
            .pos = 0,
            .allocator = alloc,
        };
    }

    pub fn deinit(self: *@This()) void {
        // for (self.states.keys()) |s| {
        //     self.allocator.free(s);
        // }
        // for (self.symbols.keys()) |s| {
        //     self.allocator.free(s);
        // }

        self.states.deinit();
        self.symbols.deinit();
        self.transitions.deinit();
    }

    pub fn run(self: *@This(), tape: *Tape, start_state: usize, pos: i32) !void {
        std.debug.assert(std.mem.eql(u8, "<H>", self.states.keys()[0]));
        self.pos = pos;
        self.curr_state = start_state;
        while (self.curr_state != HALT) {
            const read_symbol = try tape.read(self.pos);
            const transition = self.transitions.get([_]usize{ self.curr_state, read_symbol });
            if (transition) |t| {
                try tape.write(self.pos, t.write_symbol);
                switch (t.move) {
                    .moveLeft => self.pos -= 1,
                    .moveRight => self.pos += 1,
                    .stay => {},
                }
                self.curr_state = t.next_state;
            } else {
                return error.FailState;
            }
        }
    }

    pub fn printState(self: *@This(), tape: ?*const Tape) !void {
        if (tape == null)
            try std.io.getStdOut().writer().print("Halted in state {s} on position {d}\n", .{ self.states.keys()[self.curr_state], self.pos });
    }
};

pub const Transition = struct {
    from_state: usize,
    read_symbol: usize,
    write_symbol: usize,
    move: Move,
    next_state: usize,
};

pub const Tape = struct {
    allocator: Allocator,
    num_chunks: usize,
    table: std.AutoHashMap(i32, usize),
    mem: std.ArrayList(usize),

    pub fn init(allocator: Allocator, start_tape: []const usize) !Tape {
        // const chunk_size = 512;
        const num_chunks: usize = @divTrunc(start_tape.len, chunk_size) + 1;

        var table = std.AutoHashMap(i32, usize).init(allocator);
        var mem = try std.ArrayList(usize).initCapacity(allocator, chunk_size * num_chunks);
        @memset(mem.items, BLANK);

        for (0..num_chunks) |i| {
            const offset: i32 = @divTrunc(@as(i32, @intCast(num_chunks)), 2);
            std.debug.print("{d}, {d}\n", .{ i, offset });
            try table.put(@as(i32, @intCast(i)) - offset, i * chunk_size);
            try mem.appendNTimes(BLANK, chunk_size);
        }
        std.mem.copyForwards(usize, mem.items[table.get(0).?..], start_tape);

        return .{ .allocator = allocator, .num_chunks = num_chunks, .table = table, .mem = mem };
    }

    fn getValueAt(self: *@This(), pos: i32) !*usize {
        const chunk_id = @divFloor(pos, @as(i32, @intCast(chunk_size)));
        var mem_offset: usize = undefined;
        if (self.table.get(chunk_id)) |res| {
            mem_offset = res;
        } else {
            mem_offset = try self.addChunkToMem(chunk_id);
        }
        const idx: usize = @as(usize, @abs(@rem(pos, @as(i32, @intCast(chunk_size)))));
        return &self.mem.items[mem_offset + idx];
    }

    pub fn read(self: *@This(), pos: i32) !usize {
        return (try self.getValueAt(pos)).*;
    }
    pub fn write(self: *@This(), pos: i32, tape_symbol: usize) !void {
        (try self.getValueAt(pos)).* = tape_symbol;
    }

    pub fn addChunkToMem(self: *@This(), new_chunk_handle: i32) !usize {
        std.debug.assert(self.table.get(new_chunk_handle) == null);
        const mem_offset = self.mem.items.len;
        try self.mem.appendNTimes(HALT, chunk_size);
        try self.table.put(new_chunk_handle, mem_offset);
        self.num_chunks += 1;
        return mem_offset;
    }

    pub fn deinit(self: *@This()) void {
        self.mem.deinit();
        self.table.deinit();
    }
};

test "tape" {
    chunk_size = 1024;
    const allocator = std.testing.allocator;
    var tape = try Tape.init(allocator, &[_]usize{ 1, 2 });
    defer tape.deinit();
    try std.testing.expectEqual(1, tape.read(0));
    try std.testing.expectEqual(2, tape.read(1));
    try std.testing.expectEqual(BLANK, tape.read(2));
    try std.testing.expectEqual(BLANK, tape.read(1024));
    try std.testing.expectEqual(BLANK, tape.read(-1024));
    try tape.write(-1024, 50);
    try std.testing.expectEqual(50, tape.read(-1024));
    try std.testing.expectEqual(1, tape.read(0));
    try std.testing.expectEqual(50, tape.read(-1024));

    try tape.write(1024, 100);
    try std.testing.expectEqual(100, tape.read(1024));
    try std.testing.expectEqual(2, tape.read(1));
    try std.testing.expectEqual(100, tape.read(1024));

    try tape.write(3000, 200);
    try std.testing.expectEqual(200, tape.read(3000));
    try std.testing.expectEqual(2, tape.read(1));
    try std.testing.expectEqual(200, tape.read(3000));
}

test "tm run fail state" {
    const allocator = std.testing.allocator;
    var tm = try TuringMachine.init(allocator);
    defer tm.deinit();
    try tm.states.put("<H>", HALT);
    try tm.transitions.put([2]usize{ 1, 1 }, .{ .from_state = 1, .read_symbol = 1, .write_symbol = 1, .move = .moveRight, .next_state = 0 });
    var tape = try Tape.init(allocator, &[_]usize{ 3, 3 });
    defer tape.deinit();
    try std.testing.expectError(error.FailState, tm.run(&tape, 1, 0));
}

test "tm run" {
    const allocator = std.testing.allocator;
    var tm = try TuringMachine.init(allocator);
    defer tm.deinit();
    try tm.states.put("<H>", HALT);
    try tm.transitions.put([2]usize{ 1, 1 }, .{ .from_state = 1, .read_symbol = 1, .write_symbol = 2, .move = .moveLeft, .next_state = 2 });
    try tm.transitions.put([2]usize{ 2, 1 }, .{ .from_state = 2, .read_symbol = 1, .write_symbol = 3, .move = .moveLeft, .next_state = 3 });
    try tm.transitions.put([2]usize{ 3, BLANK }, .{ .from_state = 3, .read_symbol = BLANK, .write_symbol = 4, .move = .stay, .next_state = 0 });
    var tape = try Tape.init(allocator, &[_]usize{ 1, 1 });
    defer tape.deinit();
    try tm.run(&tape, 1, 1);
    try std.testing.expectEqual(HALT, tm.curr_state);
    try std.testing.expectEqual(-1, tm.pos);
    try std.testing.expectEqual(2, try tape.read(1));
    try std.testing.expectEqual(3, try tape.read(0));
    try std.testing.expectEqual(4, try tape.read(-1));
}
