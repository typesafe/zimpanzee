const std = @import("std");
const Lexer = @import("./Lexer.zig");
const ast = @import("./ast.zig");
const Parser = @import("./Parser.zig");

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
        if (std.mem.eql(u8, input, "exit")) {
            return error.Exit;
        }

        const p = try Parser.parseProgram(input, self.allocator);
        defer p.deinit();

        // const program = try p.parse_program();
        var it = Lexer.get_tokens(input);

        while ((&it).next()) |token| {
            std.debug.print("TOKEN: {any}\n", .{token});
        }
    }
};
