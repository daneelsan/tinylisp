const std = @import("std");

const tinylisp = @import("tinylisp.zig");

pub fn main() anyerror!void {
    const reader = std.io.getStdIn().reader().any();
    const writer = std.io.getStdOut().writer().any();

    var lisp = tinylisp.Lisp{};
    lisp.init(writer);
    try lisp.repl(reader);
}
