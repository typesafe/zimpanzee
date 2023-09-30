const std = @import("std");

pub const Lexer = struct {
    const Self = @This();
    input: []const u8,
    i: usize = 0,

    pub fn init(input: []const u8) Self {
        return .{ .input = input };
    }

    /// Return the next token. The last token returned, is always `.eof`.
    pub fn next_token(self: *Self) Token {
        const char = self.read_char();

        if (char) |c| {
            return switch (c) {

                // operators
                '!' => if (self.read_matching_char('=')) |_| .ne else .bang,
                '=' => if (self.read_matching_char('=')) |_| .eq else .assign,
                '/' => if (self.read_matching_char('/')) |_| .{ .comment = self.read_comment_line() } else .fslash,
                '+' => .plus,
                '-' => .minus,
                '*' => .asterisk,
                '<' => .lt,
                '>' => .gt,

                // separators
                ';' => .semicolon,
                ',' => .comma,
                '.' => .dot,
                '{' => .lbrace,
                '}' => .rbrace,
                '(' => .lparen,
                ')' => .rparen,
                '[' => .lbracket,
                ']' => .rbracket,

                '0'...'9' => {
                    const v = self.read_integer();
                    return .{ .integer = v };
                },

                'a'...'z', 'A'...'Z', '_' => {
                    const v = self.read_identifier();
                    if (Keywords.get(v)) |kw| {
                        return .{ .keyword = kw };
                    } else {
                        return .{ .identifier = v };
                    }
                },

                else => return .{ .illegal = c },
            };
        } else {
            return .eof;
        }
    }

    /// Returns the next non-whitespace character or null when the end of the input is reached.
    /// i is incremented to match the index of the _next_ character.
    fn read_char(self: *Self) ?u8 {
        while (true) {
            if (self.i >= self.input.len) {
                return null;
            }

            const char = self.input[self.i];
            self.i = self.i + 1;

            if (std.ascii.isWhitespace(char)) continue;

            return char;
        }
    }

    fn peek_char(self: *Self) ?u8 {
        if (self.i >= self.input.len) {
            return null;
        }

        return self.input[self.i];
    }

    /// Returns the next character (and incremnts the index) if it matches the given character.
    fn read_matching_char(self: *Self, c: u8) ?u8 {
        if (self.peek_char() == c) {
            self.i = self.i + 1;
            return c;
        } else {
            return null;
        }
    }

    fn read_comment_line(self: *@This()) []const u8 {
        return self.read_matching(is_no_linebeak);
    }

    fn read_identifier(self: *@This()) []const u8 {
        return self.read_matching(is_identifier_char);
    }

    fn read_integer(self: *@This()) []const u8 {
        return self.read_matching(std.ascii.isDigit);
    }

    fn read_matching(self: *Self, m: anytype) []const u8 {
        const offset = self.i - 1;

        while (if (self.peek_char()) |c| m(c) else false) {
            self.i = self.i + 1;
        }

        return self.input[offset..self.i];
    }

    fn is_identifier_char(c: ?u8) bool {
        return if (c) |v| std.ascii.isAlphanumeric(v) or v == '_' else false;
    }

    fn is_no_linebeak(c: ?u8) bool {
        return (c != '\n' and c != '\r');
    }
};

pub const Keyword = enum {
    let,
    ret,
    _if,
    _else,
    _fn,
    // _true,
    // _false,
};

const Keywords = std.ComptimeStringMap(Keyword, .{
    .{ "let", .let },
    .{ "return", .ret },
    .{ "fn", ._fn },
    .{ "if", ._if },
    .{ "else", ._else },
    //.{ "true", .true_op },
    //.{ "false", .false_op },
});

pub const Token = union(enum) {
    eof: void,
    illegal: u8,
    comment: []const u8,

    keyword: Keyword,
    identifier: []const u8,
    integer: []const u8,

    // operators
    assign: void,
    plus: void,
    minus: void,
    asterisk: void,
    fslash: void,
    lt: void,
    gt: void,
    bang: void,
    eq: void,
    ne: void,

    // separators
    semicolon: void,
    comma: void,
    dot: void,
    lbrace: void,
    rbrace: void,
    lparen: void,
    rparen: void,
    lbracket: void,
    rbracket: void,
};

const testing = std.testing;

test "Lexer.next_token > literal to var assignment" {
    const input = "let foo = 123;";
    var l = Lexer.init(input);

    try expectTokens(&l, &[_]Token{
        .{ .keyword = .let },
        .{ .identifier = "foo" },
        .assign,
        .{ .integer = "123" },
        .semicolon,
        .eof,
    });
}

test "Lexer.next_token > sum of ints" {
    const input = "1+2;";
    var l = Lexer.init(input);

    try expectTokens(&l, &[_]Token{
        .{ .integer = "1" },
        .plus,
        .{ .integer = "2" },
        .semicolon,
        .eof,
    });
}

test "Lexer.next_token > operators" {
    const input = "!= == = !true<>*.1+2;";
    var l = Lexer.init(input);

    try expectTokens(&l, &[_]Token{
        .ne,
        .eq,
        .assign,
        .bang,
        .{ .identifier = "true" },
        .lt,
        .gt,
        .asterisk,
        .dot,
        .{ .integer = "1" },
        .plus,
        .{ .integer = "2" },
        .semicolon,
        .eof,
    });

    l = Lexer.init("a == b");

    try expectTokens(&l, &[_]Token{
        .{ .identifier = "a" },
        .eq,
        .{ .identifier = "b" },
        .eof,
    });
}

test "Lexer.next_token > variables, function declaration and invocation" {
    const input =
        \\// comment1
        \\let five = 5; // comment2
        \\let ten = 10;
        \\   let add = fn(x, y) {
        \\     x + y;
        \\};
        \\   let result = add(five, ten);
    ;
    var l = Lexer.init(input);

    try expectTokens(&l, &[_]Token{
        .{ .comment = " comment1" },
        .{ .keyword = .let },
        .{ .identifier = "five" },
        .assign,
        .{ .integer = "5" },
        .semicolon,
        .{ .comment = " comment2" },

        .{ .keyword = .let },
        .{ .identifier = "ten" },
        .assign,
        .{ .integer = "10" },
        .semicolon,

        .{ .keyword = .let },
        .{ .identifier = "add" },
        .assign,
        .{ .keyword = ._fn },
        .lparen,
        .{ .identifier = "x" },
        .comma,
        .{ .identifier = "y" },
        .rparen,
        .lbrace,
        .{ .identifier = "x" },
        .plus,
        .{ .identifier = "y" },
        .semicolon,
        .rbrace,
        .semicolon,

        .{ .keyword = .let },
        .{ .identifier = "result" },
        .assign,
        .{ .identifier = "add" },
        .lparen,
        .{ .identifier = "five" },
        .comma,
        .{ .identifier = "ten" },
        .rparen,
        .semicolon,

        .eof,
    });
}

fn expectTokens(l: *Lexer, t: []const Token) !void {
    for (t) |value| {
        const actual = l.next_token();

        try switch (value) {
            .keyword => testing.expectEqual(value.keyword, actual.keyword),
            .identifier => testing.expectEqualSlices(u8, value.identifier, actual.identifier),
            .integer => testing.expectEqualSlices(u8, value.integer, actual.integer),
            else => testing.expectEqual(@intFromEnum(value), @intFromEnum(actual)) catch {
                std.debug.print("expected: {}, actual: {}\n", .{ value, actual });
                return error.TokenMismatch;
            },
        };
    }
}
