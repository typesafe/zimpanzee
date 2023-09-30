const std = @import("std");
const lexer = @import("./lexer.zig");

pub const Repl = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Repl {
        return .{
            .allocator = allocator,
        };
    }

    pub fn run(self: *Repl) !void {
        while (true) {
            const input = try self.read();
            defer self.allocator.free(input);

            self.evaluate(input) catch break;
        }
    }

    fn read(self: *Repl) ![]u8 {
        std.debug.print(" > ", .{});

        var input = std.ArrayList(u8).init(self.allocator);
        defer input.deinit();

        try std.io.getStdIn().reader().streamUntilDelimiter(input.writer(), '\n', null);

        return input.toOwnedSlice();
    }

    fn evaluate(self: *Repl, input: []u8) !void {
        _ = self;

        if (std.mem.eql(u8, input, "exit")) {
            return error.Exit;
        }

        std.debug.print("EVAL: {s}\n", .{input});
    }
};
