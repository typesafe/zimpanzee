const std = @import("std");
const Lexer = @import("./Lexer.zig");

/// Represents a statement or expression node.
pub const Node = union(enum) {
    expression: Expression,
    statement: Statement,

    pub fn format(value: @This(), comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        return switch (value) {
            .expression => |e| writer.print("{s}", .{e}),
            .statement => |s| writer.print("{s}", .{s}),
        };
    }
};

/// Represents a Monkey program.
pub const Program = struct {
    const Self = @This();

    nodes: std.ArrayList(Node),
    statements: std.ArrayList(*Node),

    pub fn deinit(self: Self) void {
        self.statements.deinit();
        self.nodes.deinit();
    }
};

/// Represents a program statement.
pub const Statement = union(enum) {
    let_statement: LetStatement,
    if_statement: IfStatement,
    return_statement: ReturnStatement,

    pub const LetStatement = struct {
        token: Lexer.Token,
        identifier: []const u8,
        value: *Node,
    };

    pub const ReturnStatement = struct {
        token: Lexer.Token,
        value: *Node,
    };

    pub const IfStatement = struct {
        token: Lexer.Token,
        condition: *Expression,
        then_expression: *Node,
        else_expression: *Node,
    };

    pub fn format(value: @This(), comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        return switch (value) {
            .let_statement => |v| writer.print("<let {s} = {}>", .{ v.identifier, v.value }),
            .return_statement => |v| writer.print("<ret {}>", .{v.value}),
            else => writer.print("<{s}>", .{@tagName(value)}),
        };
    }
};

/// Represents a program expression that evaluates to a value.
pub const Expression = union(enum) {
    identifier: Identifier,
    literal: Literal,
    infix: Infix,
    prefix: Prefix,

    const Identifier = struct {
        token: Lexer.Token,
        name: []const u8,
    };

    const Literal = struct {
        token: Lexer.Token,
        value: LiteralValue,

        const LiteralValue = union(enum) {
            int: u64,
            float: f64,
            string: []const u8,
            bool: bool,
        };
    };

    const Infix = struct {
        token: Lexer.Token,
        operator: Lexer.Operator,
        left: *Node,
        right: *Node,
    };

    const Prefix = struct {
        token: Lexer.Token,

        /// `!` or `-`
        operator: u8,
        right: *Node,
    };

    pub fn format(value: @This(), comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        return switch (value) {
            .identifier => |v| writer.print("{s}", .{v.name}),
            .prefix => |v| writer.print("{c}{s}", .{ v.operator, v.right }),
            .infix => |v| writer.print("{s}{}{s}", .{ v.left, v.token.operator, v.right }),
            .literal => |v| switch (v.value) {
                .string => |s| writer.print("<{s}>", .{s}),
                .int => |i| writer.print("<{}>", .{i}),
                else => writer.print("<{s}>", .{@tagName(v.value)}),
            },
        };
    }
};

test "Expression.format" {
    try expectFormat(
        "foo",
        .{ .identifier = .{ .name = "foo", .token = Lexer.Token{ .identifier = "foo" } } },
    );
}

fn expectFormat(expected: []const u8, value: Expression) !void {
    const actual = try std.fmt.allocPrint(std.testing.allocator, "{}", .{value});
    defer std.testing.allocator.free(actual);

    try std.testing.expectEqualStrings(expected, actual);
}
