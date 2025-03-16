pub const std = @import("std");

const ByteOffset = usize;

pub const Token = struct {
    loc: Location,
    tag: Tag,

    pub const Location = struct {
        start: ByteOffset,
        end: ByteOffset,
    };

    pub const Tag = enum {
        dot,
        eof,
        integer,
        invalid,
        parenthesis_left,
        parenthesis_right,
        quote,
        real,
        symbol,

        pub fn lexeme(self: Tag) ?[]const u8 {
            return switch (self) {
                .eof,
                .integer,
                .invalid,
                .real,
                .symbol,
                => null,

                .dot => ".",
                .parenthesis_left => "(",
                .parenthesis_right => ")",
                .quote => "'",
            };
        }

        pub fn toString(self: Tag) []const u8 {
            return self.lexeme() orelse switch (self) {
                .eof => "EOF",
                .integer => "an integer",
                .invalid => "invalid bytes",
                .real => "a real",
                .symbol => "a symbol",
                else => unreachable,
            };
        }
    };
};

pub const Tokenizer = struct {
    buffer: [:0]const u8,
    index: ByteOffset,

    // For debugging purposes
    pub fn dump(self: *Tokenizer, writer: anytype, token: Token) !void {
        try writer.print("[start: {d}, end: {d}] {s} - \"{s}\"\n", .{
            token.loc.start,
            token.loc.end,
            @tagName(token.tag),
            self.buffer[token.loc.start..token.loc.end],
        });
    }

    pub fn init(buffer: [:0]const u8) Tokenizer {
        return Tokenizer{
            .buffer = buffer,
            .index = 0,
        };
    }

    const State = enum {
        integer,
        integer_dot,
        invalid,
        real_fractional_part,
        start,
        symbol,
    };

    pub fn getTokenString(self: *Tokenizer, token: Token) ?[]const u8 {
        return switch (token.tag) {
            .eof,
            .invalid,
            => null,
            else => self.buffer[token.loc.start..token.loc.end],
        };
    }

    pub fn next(self: *Tokenizer) Token {
        var result = Token{
            .tag = undefined,
            .loc = .{
                .start = self.index,
                .end = undefined,
            },
        };
        state: switch (State.start) {
            .start => switch (self.buffer[self.index]) {
                0 => {
                    if (self.index == self.buffer.len) return .{
                        .tag = .eof,
                        .loc = .{
                            .start = self.index,
                            .end = self.index,
                        },
                    };
                    continue :state .invalid;
                },
                ' ', '\t', '\r' => {
                    self.index += 1;
                    result.loc.start = self.index;
                    continue :state .start;
                },
                '.' => {
                    result.tag = .dot;
                    self.index += 1;
                },
                '\'' => {
                    result.tag = .quote;
                    self.index += 1;
                },
                '(' => {
                    result.tag = .parenthesis_left;
                    self.index += 1;
                },
                ')' => {
                    result.tag = .parenthesis_right;
                    self.index += 1;
                },
                '<', '>', '+', '-', '*', '/', '=' => {
                    result.tag = .symbol;
                    self.index += 1;
                },
                'a'...'z', 'A'...'Z', '#' => {
                    result.tag = .symbol;
                    continue :state .symbol;
                },
                '0'...'9' => continue :state .integer,
                else => continue :state .invalid,
            },

            .integer => {
                self.index += 1;
                switch (self.buffer[self.index]) {
                    '.' => continue :state .integer_dot,
                    '0'...'9' => continue :state .integer,
                    else => result.tag = .integer,
                }
            },
            .integer_dot => {
                self.index += 1;
                switch (self.buffer[self.index]) {
                    0 => result.tag = .real,
                    else => continue :state .real_fractional_part,
                }
            },

            .invalid => {
                self.index += 1;
                switch (self.buffer[self.index]) {
                    0 => if (self.index == self.buffer.len) {
                        result.tag = .invalid;
                    } else {
                        continue :state .invalid;
                    },
                    '\n' => result.tag = .invalid,
                    else => continue :state .invalid,
                }
            },

            .real_fractional_part => {
                self.index += 1;
                switch (self.buffer[self.index]) {
                    '0'...'9' => continue :state .real_fractional_part,
                    else => result.tag = .real,
                }
            },

            .symbol => {
                self.index += 1;
                switch (self.buffer[self.index]) {
                    'a'...'z', 'A'...'Z', '0'...'9', '-', '_' => continue :state .symbol,
                    else => {},
                }
            },
        }
        result.loc.end = self.index;
        return result;
    }
};

test "tokenizer - symbol" {
    try testTokenize("eval", &.{.symbol});
    try testTokenize("define", &.{.symbol});
    try testTokenize("echo-eval", &.{.symbol});
    try testTokenize("#t", &.{.symbol});
    try testTokenize("+", &.{.symbol});
}

test "tokenizer - numbers" {
    try testTokenize("1", &.{.integer});
    try testTokenize("42", &.{.integer});
    try testTokenize("1.", &.{.real});
    try testTokenize("4.2", &.{.real});
    try testTokenize("0.5", &.{.real});
}

test "tokenizer - expressions" {
    try testTokenize("(+ 1.4 3.1416)", &.{
        .parenthesis_left,
        .symbol,
        .real,
        .real,
        .parenthesis_right,
    });
    try testTokenize("(x . y)", &.{
        .parenthesis_left,
        .symbol,
        .dot,
        .symbol,
        .parenthesis_right,
    });
}

fn testTokenize(source: [:0]const u8, expected_tokens: []const Token.Tag) !void {
    var tokenizer = Tokenizer.init(source);
    for (expected_tokens) |expected_token_id| {
        const token = tokenizer.next();
        if (token.tag != expected_token_id) {
            std.debug.panic("expected {s}, found {s}\n", .{
                @tagName(expected_token_id), @tagName(token.tag),
            });
        }
    }
    const last_token = tokenizer.next();
    try std.testing.expectEqual(Token.Tag.eof, last_token.tag);
    try std.testing.expectEqual(source.len, last_token.loc.start);
}
