const std = @import("std");
const Lexer = @import("./Lexer.zig");
const ast = @import("./ast.zig");
const TokenReader = @import("./TokenReader.zig");

const Self = @This();

tokens: *TokenReader,
nodes: *std.ArrayList(ast.Node),

/// Parses a program from source.
pub fn parseProgram(source: []const u8, allocator: std.mem.Allocator) !ast.Program {
    var nodes = std.ArrayList(ast.Node).init(allocator);
    errdefer nodes.deinit();

    var iterator = Lexer.get_tokens(source);
    var tokens = TokenReader.init(&iterator);

    var instance = Self{ .tokens = &tokens, .nodes = &nodes };

    var statements = std.ArrayList(*ast.Node).init(allocator);
    errdefer statements.deinit();

    while (try instance.parseStatement()) |s| {
        try statements.append(s);
    }

    return ast.Program{
        .statements = statements,
        .nodes = instance.nodes.*,
    };
}

fn parseStatement(self: *Self) !?*ast.Node {
    if (self.tokens.current) |token| {
        const res = switch (token) {
            .keyword => {
                return switch (token.keyword) {
                    .let => try self.parseLetStatement(),
                    .ret => try self.parseReturnStatement(),

                    else => error.NotImplemented,
                };
            },
            else => try self.parseExpression(Precedence.lowest),
        };

        // move past the semicolon so that subsequent statement are identitical to first
        _ = self.tokens.advance();
        return res;
    }

    // we're done
    return null;
}

fn parseLetStatement(self: *Self) !*ast.Node {
    const token = self.tokens.current.?;
    const name = self.tokens.advance().?.identifier;

    _ = try self.tokens.ensureNext(Lexer.Token{ .operator = Lexer.Operator.assign });
    _ = self.tokens.advance();

    const value = try self.parseExpression(Precedence.lowest);

    return self.allocateNode(.{ .statement = .{ .let_statement = .{
        .token = token,
        .identifier = name,
        .value = value,
    } } });
}

fn parseReturnStatement(self: *Self) !*ast.Node {
    const token = self.tokens.current.?;
    const value = try self.parseExpression(Precedence.lowest);
    _ = try self.tokens.ensureNext(Lexer.Token.semicolon);
    _ = self.tokens.advance();

    return self.allocateNode(.{ .statement = .{ .return_statement = .{ .token = token, .value = value } } });
}

const Precedence = enum(u4) {
    lowest = 0,
    equals,
    lt,
    gt,
    sum,
    sub,
    multiply,
    divide,
    prefix,
    call,
};

const TokenPrecedences = std.ComptimeStringMap(Precedence, .{
    .{ "==", .equals },
    .{ "<", .lt },
    .{ ">", .gt },
    .{ "+", .sum },
    .{ "-", .sub },
    .{ "*", .multiply },
    .{ "/", .divide },
    .{ "!", .prefix },
    //.{ "(", .call },
});

fn getPrecedence(op: Lexer.Operator) Precedence {
    return switch (op) {
        .fslash => Precedence.divide,
        .asterisk => Precedence.multiply,
        .lt => Precedence.lt,
        .gt => Precedence.gt,
        .eq => Precedence.equals,
        .ne => Precedence.equals,
        .plus => Precedence.sum,
        .minus => Precedence.sub,

        else => Precedence.lowest,
    };
}

fn parseExpression(self: *Self, precedence: Precedence) ParseError!*ast.Node {
    if (self.tokens.current) |token| {
        if (self.getPrefixParseFunction(token)) |prefixFn| {
            var left = try prefixFn(self);

            if (self.tokens.next) |next| {
                switch (next) {
                    .operator => |op| {
                        if (@intFromEnum(precedence) < @intFromEnum(getPrecedence(op))) {
                            if (self.getInfixParseFunction(next)) |infixFn| {
                                _ = self.tokens.advance();
                                left = try infixFn(self, left, getPrecedence(op));
                            }
                        }
                    },
                    else => {},
                }
            }

            return left;
        }
    }

    return error.IllegalToken;
}

const ParseError = error{
    IllegalToken,
} || std.mem.Allocator.Error;

const PrefixParseFn = *const fn (self: *Self) ParseError!*ast.Node;
const InfixParseFn = *const fn (self: *Self, left: *ast.Node, current_precedence: Precedence) ParseError!*ast.Node;

fn getPrefixParseFunction(self: *Self, token: Lexer.Token) ?PrefixParseFn {
    _ = self;
    return switch (token) {
        //.lbrace => parse_grouped_expression,
        .identifier => parseIdentitifier,
        .integer => parseInteger,
        // .literal => |lit| switch (lit) {
        //     .integer => parse_integer,
        //     else => parse_illegal_token,
        // },
        .operator => |op| switch (op) {
            .minus => parsePrefix,
            .bang => parsePrefix,
            else => null,
        },
        else => null,
    };
}

// fn parse_grouped_expression(self: *Self) ParseError!*ast.Node {
//     _ = self.tokens.advance();

//     const exp = try self.parse_expression(Precedence.lowest);

//     try self.tokens.ensureNext(Lexer.Token.rbrace);
//     _ = self.tokens.advance();

//     return exp;
// }

fn parse_illegal_token(self: *Self) ParseError!*ast.Node {
    _ = self;
    return error.IllegalToken;
}

fn parseIdentitifier(self: *Self) ParseError!*ast.Node {
    if (std.mem.eql(u8, self.tokens.current.?.identifier, "true")) {
        return try self.allocate_expression(.{ .literal = .{
            .token = self.tokens.current.?,
            .value = .{ .bool = true },
        } });
    }

    if (std.mem.eql(u8, self.tokens.current.?.identifier, "false")) {
        return try self.allocate_expression(.{ .literal = .{
            .token = self.tokens.current.?,
            .value = .{ .bool = false },
        } });
    }

    return try self.allocate_expression(.{ .identifier = .{ .token = self.tokens.current.?, .name = self.tokens.current.?.identifier } });
}

fn parseInteger(self: *Self) ParseError!*ast.Node {
    return try self.allocate_expression(.{ .literal = .{
        .token = self.tokens.current.?,
        .value = .{ .int = std.fmt.parseInt(u64, self.tokens.current.?.integer, 10) catch 0 },
    } });
}

fn parsePrefix(self: *Self) ParseError!*ast.Node {
    const token = self.tokens.current.?; // `!` or `-`
    _ = self.tokens.advance();

    var operator: u8 = undefined;

    switch (token.operator) {
        .bang => operator = '!',
        .minus => operator = '-',
        else => return error.IllegalToken,
    }

    return try self.allocate_expression(.{ .prefix = .{
        .token = token,
        .operator = switch (token.operator) {
            .bang => '!',
            .minus => '-',
            else => unreachable,
        },
        .right = try self.parseExpression(Precedence.lowest),
    } });
}

fn getInfixParseFunction(self: *Self, token: Lexer.Token) ?InfixParseFn {
    _ = self;
    return switch (token) {
        .operator => parseInfixExpression,
        else => null,
    };
}

fn parseInfixExpression(self: *Self, left: *ast.Node, current_precedence: Precedence) ParseError!*ast.Node {
    const token = self.tokens.current.?;
    _ = self.tokens.advance();
    return self.allocate_expression(.{ .infix = .{
        .token = token,
        .operator = token.operator,
        .left = left,
        .right = try self.parseExpression(current_precedence),
    } });
}

fn allocate_expression(self: *Self, value: ast.Expression) !*ast.Node {
    const node = try self.nodes.addOne();
    node.* = .{ .expression = value };
    return node;
}

fn allocateNode(self: *Self, value: ast.Node) !*ast.Node {
    const node = try self.nodes.addOne();
    node.* = value;
    return node;
}

test "parsePrefix -3" {
    const p = try parse("-3");
    defer p.deinit();

    std.debug.print("\nparsed {s}\n", .{p.statements.items[0]});

    try std.testing.expectEqual(p.statements.items.len, 1);

    try std.testing.expectEqual(p.statements.items[0].expression.prefix.operator, '-');
    try std.testing.expectEqual(p.statements.items[0].expression.prefix.right.expression.literal.value.int, 3);
}

test "parsePrefix !true" {
    const p = try parse("!true");
    defer p.deinit();

    std.debug.print("\nparsed {s}\n", .{p.statements.items[0]});

    try std.testing.expectEqual(p.statements.items.len, 1);

    try std.testing.expectEqual(p.statements.items[0].expression.prefix.operator, '!');
    try std.testing.expectEqual(p.statements.items[0].expression.prefix.right.expression.literal.value.bool, true);
}

test "parsePrefix /3 should fail" {
    try std.testing.expectError(ParseError.IllegalToken, parse("/3"));
}

test "parsePrefix *3 should fail" {
    try std.testing.expectError(ParseError.IllegalToken, parse("*3"));
}

fn parse(source: []const u8) !ast.Program {
    return try parseProgram(source, std.testing.allocator);
}

fn check(source: []const u8, expected: []const u8) !void {
    const program = try parse(source);
    defer program.deinit();

    const actual = try std.fmt.allocPrint(std.testing.allocator, "{}", .{program.statements.items[0]});
    defer std.testing.allocator.free(actual);

    try std.testing.expectEqualStrings(actual, expected);
}

test "parseInfix" {
    try check("1+ 3", "1+3");

    try verify("1 + 3", Lexer.Operator.plus, 1, 3);
    try verify("1 * 3", Lexer.Operator.asterisk, 1, 3);
    try verify("1 / 3", Lexer.Operator.fslash, 1, 3);

    const program = try parseProgram("1+2*3", std.testing.allocator);
    defer program.deinit();

    try std.testing.expectEqual(program.statements.items.len, 1);
    try std.testing.expectEqual(program.statements.items[0].expression.infix.operator, Lexer.Operator.plus);
    try std.testing.expectEqual(program.statements.items[0].expression.infix.left.expression.literal.value.int, 1);
    try std.testing.expectEqual(program.statements.items[0].expression.infix.right.expression.infix.operator, Lexer.Operator.asterisk);
    try std.testing.expectEqual(program.statements.items[0].expression.infix.right.expression.infix.left.expression.literal.value.int, 2);
    try std.testing.expectEqual(program.statements.items[0].expression.infix.right.expression.infix.right.expression.literal.value.int, 3);
}

fn verify(source: []const u8, operator: Lexer.Operator, left: u64, right: u64) !void {
    const program = try parseProgram(source, std.testing.allocator);
    defer program.deinit();

    try std.testing.expectEqual(program.statements.items.len, 1);
    try std.testing.expectEqual(program.statements.items[0].expression.infix.operator, operator);
    try std.testing.expectEqual(program.statements.items[0].expression.infix.left.expression.literal.value.int, left);
    try std.testing.expectEqual(program.statements.items[0].expression.infix.right.expression.literal.value.int, right);
}

test "parseLetStatement" {
    // const f = self.get_parse_function(.{ .identifier = "foo" });

    // const v = f.?(.{ .identifier = "foo" });

    // try std.testing.expectEqualStrings(v.identifier.name, "foo");

    //var l = Lexer.get_tokens("let foo = 12;");
    //var p = init(std.testing.allocator);

    const program = try parseProgram("let foo = 12;", std.testing.allocator);
    defer program.deinit();

    try std.testing.expectEqual(program.statements.items.len, 1);
    try std.testing.expectEqualStrings(program.statements.items[0].statement.let_statement.identifier, "foo");
    try std.testing.expectEqual(program.statements.items[0].statement.let_statement.value.expression.literal.value.int, 12);

    // inverted args to avoid "argument to parameter with comptime-only type must be comptime-known"
    // const stmt = program.statements[0];
    // const let_stmt = stmt.let_stmt;
    // std.testing.expect(let_stmt.name.value == "foo");
    // std.testing.expect(let_stmt.name.token_literal() == "foo");

}

test "let foo = 1 + 2;" {
    const program = try parseProgram("let foo = 1 + 2;", std.testing.allocator);
    defer program.deinit();

    try std.testing.expectEqual(program.statements.items.len, 1);
    try std.testing.expectEqualStrings(program.statements.items[0].statement.let_statement.identifier, "foo");
    const sum = program.statements.items[0].statement.let_statement.value.expression;
    try std.testing.expectEqual(sum.op.token.operator, .plus);
    try std.testing.expectEqual(sum.op.left.expression.literal.value.int, 1);
    try std.testing.expectEqual(sum.op.right.expression.literal.value.int, 2);
}

test "let foo = 1 + 2 * 3;" {
    const program = try parseProgram("let foo = 1 + 2 * 3;", std.testing.allocator);
    defer program.deinit();

    try std.testing.expectEqual(program.statements.items.len, 1);
    try std.testing.expectEqualStrings(program.statements.items[0].statement.let_statement.identifier, "foo");

    const sum = program.statements.items[0].statement.let_statement.value.expression.op;
    try std.testing.expectEqual(sum.token.operator, .plus);
    try std.testing.expectEqual(sum.left.expression.literal.value.int, 1);
    try std.testing.expectEqual(sum.right.expression.op.token.operator, .asterisk);
    try std.testing.expectEqual(sum.right.expression.op.left.expression.literal.value.int, 2);
    try std.testing.expectEqual(sum.right.expression.op.right.expression.literal.value.int, 3);
}

test "multiple statements" {
    const code =
        \\let foo = 1;
        \\let bar = 2;
        \\let foobar = foo + bar;
        \\return foobar;
    ;

    const program = try parseProgram(code, std.testing.allocator);
    defer program.deinit();

    try std.testing.expectEqual(program.statements.items.len, 4);
    try std.testing.expectEqualStrings(program.statements.items[0].let_statement.identifier, "foo");
    try std.testing.expectEqual(program.statements.items[0].let_statement.value.expression.literal.value.int, 1);
    try std.testing.expectEqualStrings(program.statements.items[1].let_statement.identifier, "bar");
    try std.testing.expectEqualStrings(program.statements.items[2].let_statement.identifier, "foobar");
    try std.testing.expectEqualStrings(program.statements.items[3].return_statement.value.expression.identifier.name, "foobar");
}
