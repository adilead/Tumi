const std = @import("std");
pub const tokenizer = @import("tokenizer.zig");
pub const Parser = @import("parser.zig");
pub const tm = @import("tm.zig");
pub const Interpreter = @import("interpreter.zig");
const Allocator = std.mem.Allocator;
const gui = @import("gui.zig");

const stdout = std.io.getStdOut().writer();
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const alloc = gpa.allocator();

    var args = std.process.args();
    _ = args.next();

    var file_path: ?[:0]const u8 = null;
    defer {
        if (file_path) |fp| alloc.free(fp);
    }

    var start_gui = false;
    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--help")) {
            try printHelpMessage();
            return;
        } else if (std.mem.eql(u8, arg, "--gui")) {
            start_gui = true;
        } else {
            file_path = try createAbsPath(alloc, arg);
        }
    }
    if (file_path == null and !start_gui) {
        try printHelpMessage();
        return;
    }

    if (start_gui) {
        gui.gui_main();
        return;
    }

    const content = try readFile(alloc, file_path.?);
    defer alloc.free(content);
    try runFile(alloc, content);
    // std.debug.print("{s}", .{content});
}

pub fn runFile(alloc: Allocator, buff: [:0]const u8) !void {
    var scanner = tokenizer.Tokenizer.init(buff);
    const tokens = try scanner.tokenize(alloc);
    defer tokens.deinit();

    var parser = Parser.init(alloc, tokens.items, buff);
    defer parser.deinit();

    var ast_tree = parser.parse() catch {
        try parser.printError();
        return;
    };
    defer ast_tree.deinit();

    var inter = Interpreter.init(alloc);
    defer inter.deinit();

    try inter.interpret(alloc, &ast_tree);
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

fn createAbsPath(allocator: Allocator, file_path: [:0]const u8) ![:0]const u8 {
    if (!std.fs.path.isAbsolute(file_path)) {
        const working_dir = std.fs.cwd();
        const abs_path = try working_dir.realpathAlloc(allocator, file_path);
        defer allocator.free(abs_path);
        return try allocator.dupeZ(u8, abs_path);
    } else {
        return try allocator.dupeZ(u8, file_path);
    }
}

test "test" {
    std.testing.refAllDecls(@This());
}
