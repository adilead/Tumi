const std = @import("std");
pub const tokenizer = @import("tokenizer.zig");
pub const Parser = @import("parser.zig");
pub const tm = @import("tm.zig");
const Allocator = std.mem.Allocator;

const stdout = std.io.getStdOut().writer();
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    var args = std.process.args();
    _ = args.next();
    var file_path: ?[:0]const u8 = null;
    const alloc = gpa.allocator();
    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--help")) {
            try printHelpMessage();
            return;
        } else {
            file_path = try alloc.dupeZ(u8, arg);
        }
    }
    if (file_path == null) {
        try printHelpMessage();
        return;
    }
    defer alloc.free(file_path.?);

    if (!std.fs.path.isAbsolute(file_path.?)) {
        const working_dir = std.fs.cwd();
        const abs_path = try working_dir.realpathAlloc(alloc, file_path.?);
        defer alloc.free(abs_path);
        alloc.free(file_path.?);
        file_path = try alloc.dupeZ(u8, abs_path);
    }

    const content = try readFile(alloc, file_path.?);
    defer alloc.free(content);
    try runFile(alloc, content);
    std.debug.print("{s}", .{content});
}

pub fn runFile(alloc: Allocator, buff: [:0]const u8) !void {
    var scanner = tokenizer.Tokenizer.init(buff);
    const tokens = try scanner.tokenize(alloc);

    var parser = Parser.init(alloc, tokens.items, buff);
    defer parser.deinit();

    var ast_tree = parser.parse() catch {
        try parser.printError();
        return;
    };
    defer ast_tree.deinit();
}

pub fn readFile(alloc: Allocator, file_path: [:0]const u8) ![:0]const u8 {
    const file = try std.fs.openFileAbsoluteZ(file_path, .{});
    defer file.close();
    const file_size = try file.getEndPos();

    const buff = try file.readToEndAlloc(alloc, @intCast(file_size));
    defer alloc.free(buff);

    const sentinel_buff = try alloc.dupeZ(u8, buff);
    errdefer {
        alloc.free(sentinel_buff);
    }

    return sentinel_buff;
}

pub fn printHelpMessage() !void {
    try stdout.print("Usage: tumi <file>\n", .{});
}

test "test" {
    std.testing.refAllDecls(@This());
}
