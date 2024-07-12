const std = @import("std");
const Allocator = std.mem.Allocator;

const Move = enum {
    moveLeft,
    moveRight,
    stay,
};

const HALT: usize = 0;
const BLANK: usize = 0;

pub const TuringMachine = struct {
    //TODO Think about moving the lookup stuff to parsing
    states: std.StringArrayHashMap(usize),
    symbols: std.StringArrayHashMap(usize),
    curr_state: usize,
    transitions: std.AutoHashMap([2]usize, Transition), //looks up transitions for a state and read symbol
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
        self.states.deinit();
        self.symbols.deinit();
        self.transitions.deinit();
    }

    pub fn run(self: *@This(), tape: *Tape, start_state: usize, pos: i32) !void {
        std.debug.assert(self.states.values()[0] == HALT);
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
};

const Transition = struct {
    from_state: usize,
    read_symbol: usize,
    write_symbol: usize,
    move: Move,
    next_state: usize,
};

const Tape = struct {
    const DL = std.DoublyLinkedList([]usize);

    allocator: Allocator,
    chunk_size: usize,
    // pos: usize,
    offset: usize, //(num_chunks-1)*chunk_size + tm_pos == pos, offset the number of cells from the first to the original 0 tm position
    chunks: DL,
    curr_chunk_idx: usize,
    curr_chunk: *DL.Node,
    num_chunks: usize,
    // length: usize,

    pub fn init(allocator: Allocator, start_tape: []const usize) !Tape {
        const chunk_size = 1024;
        const num_chunks: usize = @divTrunc(start_tape.len, chunk_size) + 1;
        var chunks = DL{};
        var start: usize = 0;
        for (0..num_chunks) |_| {
            const chunk = try allocator.alloc(usize, chunk_size);
            @memset(chunk, BLANK);
            const end = if (start + chunk_size > start_tape.len - start) start_tape.len else start + chunk_size;
            std.mem.copyForwards(usize, chunk, start_tape[start..end]);
            chunks.append(try allocator.create(DL.Node));
            chunks.last.?.data = chunk;
            start += chunk_size;
        }

        return .{ .allocator = allocator, .chunk_size = chunk_size, .chunks = chunks, .offset = (chunks.len - 1) * chunk_size, .curr_chunk_idx = 0, .curr_chunk = chunks.last.?, .num_chunks = num_chunks };
    }

    fn getValueAt(self: *@This(), pos: i32) !*usize {
        var idx: i32 = @as(i32, @intCast(self.offset)) + pos;
        if (idx < 0) {
            const num_new_chunks: usize = @abs(@divTrunc(@as(usize, @intCast(-idx)), self.chunk_size) + 1);
            for (0..num_new_chunks) |_| {
                try self.createNewChunk(true);
            }
            self.curr_chunk_idx += num_new_chunks;
        }
        idx = @as(i32, @intCast(self.offset)) + pos;

        const index: usize = @intCast(idx);
        //check if last read/write was in the current chunk
        const c_idx = @divTrunc(index, self.chunk_size);
        if (c_idx == self.curr_chunk_idx) {
            return &self.curr_chunk.data[@rem(index, self.chunk_size)];
        } else {
            if (c_idx >= self.num_chunks) {
                for (0..(c_idx - self.num_chunks + 1)) |_| {
                    try self.createNewChunk(false);
                }
            }
            var c: usize = 0;
            var curr: ?*DL.Node = self.chunks.first;
            while (curr) |node| : (c += 1) {
                if (c == c_idx) break;
                curr = node.next;
            }
            self.curr_chunk = curr.?;
            self.curr_chunk_idx = c_idx;
            return &self.curr_chunk.data[@rem(index, self.chunk_size)];
        }
        // return self.chunks.items[@divTrunc(index, self.chunk_size)][@rem(index, self.chunk_size)];
        unreachable;
    }

    pub fn read(self: *@This(), pos: i32) !usize {
        return (try self.getValueAt(pos)).*;
    }
    pub fn write(self: *@This(), pos: i32, tape_symbol: usize) !void {
        (try self.getValueAt(pos)).* = tape_symbol;
    }

    pub fn createNewChunk(self: *@This(), prepend: bool) !void {
        const new_chunk = try self.allocator.alloc(usize, self.chunk_size);
        @memset(new_chunk, BLANK);
        self.num_chunks += 1;
        if (prepend) {
            self.chunks.prepend(try self.allocator.create(DL.Node));
            self.chunks.first.?.data = new_chunk;
            self.offset += self.chunk_size;
        } else {
            self.chunks.append(try self.allocator.create(DL.Node));
            self.chunks.last.?.data = new_chunk;
        }
    }

    pub fn deinit(self: *@This()) void {
        var node: ?*DL.Node = self.chunks.first;
        while (node) |n| {
            node = n.next;
            self.allocator.free(n.data);
            self.allocator.destroy(n);
        }
    }
};

test "tape" {
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
