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
        string,
        symbol,

        const Self = @This();

        pub fn lexeme(self: Self) ?[]const u8 {
            return switch (self) {
                .eof,
                .integer,
                .invalid,
                .string,
                .symbol,
                => null,

                .dot => ".",
                .parenthesis_left => "(",
                .parenthesis_right => ")",
                .quote => "'",
            };
        }

        pub fn symbol(self: Self) []const u8 {
            return self.lexeme() orelse switch (self) {
                .eof => "EOF",
                .integer => "an integer",
                .invalid => "invalid bytes",
                .real => "a real",
                .string => "a string",
                .symbol => "a symbol",
            };
        }

        pub inline fn isEOF(self: Self) bool {
            return self == .eof;
        }
    };
};

pub const Tokenizer = struct {
    buffer: [:0]const u8,
    // current_token: Token,
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
        start,
        integer_decimal,
        number_dot_decimal,
        real_fraction_decimal,
        string,
        symbol,
        zero,
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
        var state: State = .start;
        var result = Token{
            .tag = .eof,
            .loc = .{
                .start = self.index,
                .end = undefined,
            },
        };
        while (true) : (self.index += 1) {
            const c = self.buffer[self.index];
            switch (state) {
                .start => switch (c) {
                    0 => break,
                    ' ', '\n', '\t', '\r' => {
                        result.loc.start = self.index + 1;
                    },
                    '"' => {
                        state = .string;
                        result.tag = .string;
                    },
                    '.' => {
                        result.tag = .dot;
                        self.index += 1;
                        break;
                    },
                    '(' => {
                        result.tag = .parenthesis_left;
                        self.index += 1;
                        break;
                    },
                    ')' => {
                        result.tag = .parenthesis_right;
                        self.index += 1;
                        break;
                    },
                    '\'' => {
                        result.tag = .quote;
                        self.index += 1;
                        break;
                    },
                    'a'...'z', 'A'...'Z' => {
                        state = .symbol;
                        result.tag = .symbol;
                    },
                    '0' => {
                        state = .zero;
                        result.tag = .integer;
                    },
                    '1'...'9' => {
                        state = .integer_decimal;
                        result.tag = .integer;
                    },
                    else => {
                        result.tag = .invalid;
                        result.loc.end = self.index;
                        self.index += 1;

                        // self.current_token = result;
                        return result;
                    },
                },
                .integer_decimal => switch (c) {
                    '.' => {
                        state = .number_dot_decimal;
                        result.tag = .real;
                    },
                    '0'...'9' => {},
                    else => break,
                },
                .number_dot_decimal => switch (c) {
                    '0'...'9' => {
                        result.tag = .real;
                        state = .real_fraction_decimal;
                    },
                    else => break,
                },
                .real_fraction_decimal => switch (c) {
                    '0'...'9' => {},
                    else => break,
                },
                .string => switch (c) {
                    '"' => {
                        self.index += 1;
                        break;
                    },
                    else => continue,
                },
                .symbol => switch (c) {
                    'a'...'z', 'A'...'Z', '0'...'9', '-', '_' => continue,
                    else => break,
                },
                .zero => switch (c) {
                    '0'...'9', '.' => {
                        // reinterpret as a decimal number
                        self.index -= 1;
                        state = .integer_decimal;
                    },
                    else => break,
                },
            }
        }
        result.loc.end = self.index;

        // self.current_token = result;
        return result;
    }
};

test "tokenizer - real" {
    try testTokenize("(add 1.4 3.1416)", &.{
        .parenthesis_left,
        .symbol,
        .real,
        .real,
        .parenthesis_right,
    });
}

fn testTokenize(source: [:0]const u8, expected_tokens: []const Token.Tag) !void {
    var tokenizer = Tokenizer.init(source);
    for (expected_tokens) |expected_token_id| {
        const token = tokenizer.next();
        tokenizer.dump(token);
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
