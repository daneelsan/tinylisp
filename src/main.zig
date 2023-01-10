const std = @import("std");

const tinylisp = @import("tinylisp.zig");

pub fn main() anyerror!void {
    const reader = std.io.getStdIn().reader();
    const writer = std.io.getStdOut().writer();

    var lisp = tinylisp.Lisp(@TypeOf(reader), @TypeOf(writer)).init(reader, writer);
    try lisp.repl();
}
