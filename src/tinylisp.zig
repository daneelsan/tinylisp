const std = @import("std");
// const build_options = @import("build_options");

const Tokenizer = @import("tokenizer.zig").Tokenizer;
const Token = @import("tokenizer.zig").Token;

// Expr ------------------------------------------------------------------------

const Expr = f64;
const I = u64; // TODO: Rename me

const tag_shift = 48;
const ord_mask = 0xFFFF_FFFF_FFFF;

/// atom, primitive, cons, closure and nil tags for NaN boxing
const ATOM: I = 0x77F8;
const PRIM: I = 0x77F9;
const CONS: I = 0x77FA;
const CLOS: I = 0x77FB;
const NIL: I = 0x7FFC;

inline fn unbox(x: Expr) I {
    return @bitCast(x);
}

/// returns a new NaN-boxed f64 with tag t and ordinal i
fn box(t: I, i: I) Expr {
    return @bitCast(t << tag_shift | i);
}

/// tag(x) returns the tag bits of a NaN-boxed Lisp expression x
fn tag(x: Expr) I {
    return unbox(x) >> tag_shift;
}

/// returns the ordinal of the NaN-boxed double x
fn ord(x: Expr) I {
    return unbox(x) & ord_mask; // narrowed to 48 bits to remove the tag
}

/// convert or check number n (does nothing, e.g. could check for NaN)
fn num(n: Expr) Expr {
    return n;
}

/// returns nonzero if x equals y
fn equ(x: Expr, y: Expr) bool {
    return unbox(x) == unbox(y);
}

/// not(x) is nonzero if x is the Lisp () empty list
fn not(x: Expr) bool {
    return tag(x) == NIL;
}

// Lisp ------------------------------------------------------------------------

var nil: Expr = box(NIL, 0);

pub fn Lisp(comptime Reader: type, comptime Writer: type) type {
    return struct {
        reader: Reader = undefined,
        writer: Writer = undefined,

        /// cell[N] array of Lisp expressions, shared by the stack and atom heap
        stack: [N]Expr = [_]Expr{0} ** N,

        /// address of the atom heap is at the bottom of the cell stack
        heap: []u8 = undefined,

        /// heap pointer, heap+hp with hp=0 points to the first atom string in stack[]
        heap_ptr: I = 0,
        /// stack pointer, the stack starts at the top of stack[] with sp=N
        stack_ptr: I = N,

        err: Expr = undefined,
        tru: Expr = undefined,
        env: Expr = undefined,

        const Self = @This();

        // TODO: make this configurable?
        /// number of cells for the shared stack and atom heap, increase N as desired
        const N = 1024;

        pub fn init(reader: Reader, writer: Writer) Self {
            var l = Self{};

            l.reader = reader;
            l.writer = writer;

            // TODO: improve me
            l.heap = @as([*]u8, @ptrCast(@alignCast(l.stack[0..])))[0..l.stack.len];

            l.err = l.atom("ERR");
            l.tru = l.atom("#t");
            l.env = l.pair(l.tru, l.tru, nil);

            for (primitive_funs, 0..) |prim, i| {
                l.env = l.pair(l.atom(prim.sym), box(PRIM, i), l.env);
            }

            return l;
        }

        // Errors --------------------------------------------------------------

        pub const Error = error{
            ParseError,
        } || Reader.Error || Writer.Error;

        // Core ----------------------------------------------------------------

        /// interning of atom names (Lisp symbols), returns a unique NaN-boxed ATOM
        fn atom(l: *Self, str: []const u8) Expr {
            var i: I = 0;

            while (i < l.heap_ptr) {
                if (std.mem.eql(u8, l.heap[i .. i + str.len], str)) {
                    return box(ATOM, i);
                } else {
                    i += strlen(l.heap[i..]) + 1;
                }
            }

            if (i == l.heap_ptr) {
                std.mem.copy(u8, l.heap[l.heap_ptr..], str);
                l.heap[l.heap_ptr + str.len] = 0;

                l.heap_ptr += str.len + 1;
                if (l.heap_ptr > (l.stack_ptr << 3)) {
                    @panic("stack overflow");
                }
            }

            return box(ATOM, i);
        }

        fn atomName(l: *Self, x: Expr) []const u8 {
            std.debug.assert(tag(x) == ATOM);
            return std.mem.sliceTo(l.heap[ord(x)..], 0);
        }

        /// construct pair (x . y) returns a NaN-boxed CONS
        fn cons(l: *Self, x: Expr, y: Expr) Expr {
            l.stack_ptr -= 1;
            l.stack[l.stack_ptr] = x;
            l.stack_ptr -= 1;
            l.stack[l.stack_ptr] = y;
            if (l.heap_ptr > (l.stack_ptr << 3)) {
                @panic("stack overflow");
            }
            return box(CONS, l.stack_ptr);
        }

        /// return the car of a pair or ERR if not a pair
        fn car(l: *Self, x: Expr) Expr {
            return if ((tag(x) & ~(CONS ^ CLOS)) == CONS) l.stack[ord(x) + 1] else l.err;
        }

        /// return the cdr of a pair or ERR if not a pair
        fn cdr(l: *Self, x: Expr) Expr {
            return if ((tag(x) & ~(CONS ^ CLOS)) == CONS) l.stack[ord(x)] else l.err;
        }

        /// construct a pair to add to environment e, returns the list ((v . x) . e)
        fn pair(l: *Self, v: Expr, x: Expr, e: Expr) Expr {
            return l.cons(l.cons(v, x), e);
        }

        /// construct a closure, returns a NaN-boxed CLOS
        fn closure(l: *Self, v: Expr, x: Expr, e: Expr) Expr {
            return box(CLOS, ord(l.pair(v, x, if (equ(e, l.env)) nil else e)));
        }

        /// look up a symbol in an environment, return its value or ERR if not found
        fn assoc(l: *Self, a: Expr, e: Expr) Expr {
            var e1 = e;
            while (tag(e1) == CONS and !equ(a, l.car(l.car(e1)))) {
                e1 = l.cdr(e1);
            }
            return if (tag(e1) == CONS) l.cdr(l.car(e1)) else l.err;
        }

        fn eval(l: *Self, x: Expr, e: Expr) Expr {
            return switch (tag(x)) {
                ATOM => l.assoc(x, e),
                CONS => l.apply(l.eval(l.car(x), e), l.cdr(x), e),
                else => x,
            };
        }

        fn apply(l: *Self, f: Expr, t: Expr, e: Expr) Expr {
            return switch (tag(f)) {
                PRIM => primitive_funs[ord(f)].fun(l, t, e),
                CLOS => l.reduce(f, t, e),
                else => l.err,
            };
        }

        /// apply closure f to arguments t in environment e
        fn reduce(l: *Self, f: Expr, t: Expr, e: Expr) Expr {
            const fun = l.car(f);
            const body = l.cdr(fun);
            const params = l.car(fun);
            const args = l.evlis(t, e);
            const fun_env = l.cdr(f);
            return l.eval(body, l.bind(params, args, if (not(fun_env)) l.env else fun_env));
        }

        // create environment by extending e with variables v bound to values t */
        fn bind(l: *Self, v: Expr, t: Expr, e: Expr) Expr {
            return switch (tag(v)) {
                NIL => e,
                CONS => l.bind(l.cdr(v), l.cdr(t), l.pair(l.car(v), l.car(t), e)),
                else => l.pair(v, t, e),
            };
        }

        // return a new list of evaluated Lisp expressions t in environment e
        fn evlis(l: *Self, t: Expr, e: Expr) Expr {
            return switch (tag(t)) {
                CONS => l.cons(l.eval(l.car(t), e), l.evlis(l.cdr(t), e)),
                ATOM => l.assoc(t, e),
                else => nil,
            };
        }

        // Primitives ----------------------------------------------------------

        //    (cond (x1 y1)
        //          (x2 y2)
        //          ...
        //          (xk yk))      the first yi for which xi evaluates to non-()
        //    (let* (v1 x1)
        //          (v2 x2)
        //          ...
        //          y)            sequentially binds each variable v1 to xi to evaluate y

        /// (eval x) return evaluated x (such as when x was quoted)
        fn f_eval(l: *Self, t: Expr, e: Expr) Expr {
            return l.eval(l.car(l.evlis(t, e)), e);
        }

        /// (quote x) special form, returns x unevaluated "as is"
        fn f_quote(l: *Self, t: Expr, _: Expr) Expr {
            return l.car(t);
        }

        /// (cons x y) construct pair (x . y)
        fn f_cons(l: *Self, t: Expr, e: Expr) Expr {
            const t1 = l.evlis(t, e);
            return l.cons(l.car(t1), l.car(l.cdr(t1)));
        }

        /// (car p) car of pair p
        fn f_car(l: *Self, t: Expr, e: Expr) Expr {
            return l.car(l.car(l.evlis(t, e)));
        }

        /// (cdr p) cdr of pair p
        fn f_cdr(l: *Self, t: Expr, e: Expr) Expr {
            return l.cdr(l.car(l.evlis(t, e)));
        }

        /// (add n1 n2 ... nk) sum of n1 to nk
        fn f_add(l: *Self, t: Expr, e: Expr) Expr {
            var t1 = l.evlis(t, e);
            var n = l.car(t1);
            while (true) {
                t1 = l.cdr(t1);
                if (not(t1)) break;
                n += l.car(t1);
            }
            return num(n);
        }

        /// (sub n1 n2 ... nk) n1 minus sum of n2 to nk
        fn f_sub(l: *Self, t: Expr, e: Expr) Expr {
            var t1 = l.evlis(t, e);
            var n = l.car(t1);
            while (true) {
                t1 = l.cdr(t1);
                if (not(t1)) break;
                n -= l.car(t1);
            }
            return num(n);
        }

        /// (mul n1 n2 ... nk) product of n1 to nk
        fn f_mul(l: *Self, t: Expr, e: Expr) Expr {
            var t1 = l.evlis(t, e);
            var n = l.car(t1);
            while (true) {
                t1 = l.cdr(t1);
                if (not(t1)) break;
                n *= l.car(t1);
            }
            return num(n);
        }

        /// (div n1 n2 ... nk) n1 divided by the product of n2 to nk
        fn f_div(l: *Self, t: Expr, e: Expr) Expr {
            var t1 = l.evlis(t, e);
            var n = l.car(t1);
            while (true) {
                t1 = l.cdr(t1);
                if (not(t1)) break;
                n /= l.car(t1);
            }
            return num(n);
        }

        /// (int n) integer part of n
        fn f_int(l: *Self, t: Expr, e: Expr) Expr {
            const n = l.car(l.evlis(t, e));
            // TODO
            return n;
        }

        /// (< n1 n2) #t if n1<n2, otherwise ()
        fn f_lt(l: *Self, t: Expr, e: Expr) Expr {
            const t1 = l.evlis(t, e);
            const x = l.car(t1);
            const y = l.car(l.cdr(t1));
            return if ((x - y) < 0) l.tru else nil;
        }

        /// (eq? x y) #t if x equals y, otherwise ()
        fn f_eq(l: *Self, t: Expr, e: Expr) Expr {
            const t1 = l.evlis(t, e);
            const x = l.car(t1);
            const y = l.car(l.cdr(t1));
            return if (equ(x, y)) l.tru else nil;
        }

        /// (not x) #t if x is (), otherwise ()
        fn f_not(l: *Self, t: Expr, e: Expr) Expr {
            return if (not(l.car(l.evlis(t, e)))) l.tru else nil;
        }

        /// (or x1 x2 ... xk)   first x that is not (), otherwise ()
        fn f_or(l: *Self, t: Expr, e: Expr) Expr {
            var x = nil;
            var t1 = t;
            while (true) {
                if (not(t1)) break;
                x = l.eval(l.car(t1), e);
                if (!not(x)) break;
                t1 = l.cdr(t1);
            }
            return x;
        }

        /// (and x1 x2 ... xk) last x if all x are not (), otherwise ()
        fn f_and(l: *Self, t: Expr, e: Expr) Expr {
            var x = nil;
            var t1 = t;
            while (true) {
                if (not(t1)) break;
                x = l.eval(l.car(t1), e);
                if (not(x)) break;
                t1 = l.cdr(t1);
            }
            return x;
        }

        /// (if x y z) if x is non-() then y else z
        fn f_if(l: *Self, t: Expr, e: Expr) Expr {
            const cond = l.eval(l.car(t), e);
            const branch = if (not(cond)) l.cdr(t) else t;
            return l.eval(l.car(l.cdr(branch)), e);
        }

        /// (lambda v x) construct a closure
        fn f_lambda(l: *Self, t: Expr, e: Expr) Expr {
            return l.closure(l.car(t), l.car(l.cdr(t)), e);
        }

        /// (define v x) define a named value globally
        fn f_define(l: *Self, t: Expr, e: Expr) Expr {
            l.env = l.pair(l.car(t), l.eval(l.car(l.cdr(t)), e), l.env);
            return l.car(t);
        }

        fn f_print_heap(l: *Self, t: Expr, e: Expr) Expr {
            _ = t;
            _ = e;
            l.printHeap() catch unreachable;
            return nil;
        }

        fn f_print_stack(l: *Self, t: Expr, e: Expr) Expr {
            _ = t;
            _ = e;
            l.printStack() catch unreachable;
            return nil;
        }

        fn f_print_env(l: *Self, t: Expr, e: Expr) Expr {
            _ = t;
            l.printEnv(e) catch unreachable;
            return nil;
        }

        fn f_echo(l: *Self, t: Expr, e: Expr) Expr {
            const t1 = l.car(l.evlis(t, e));
            l.writer.print("   >> ", .{}) catch unreachable;
            l.printExpr(t1) catch unreachable;
            l.writer.print("\n", .{}) catch unreachable;
            return l.eval(t1, e);
        }

        fn f_echo_evaluation(l: *Self, t: Expr, e: Expr) Expr {
            l.writer.print("   >> ", .{}) catch unreachable;
            l.printExpr(t) catch unreachable;
            l.writer.print("\n", .{}) catch unreachable;
            l.writer.print("   << ", .{}) catch unreachable;
            const t1 = l.car(l.evlis(t, e));
            l.printExpr(t1) catch unreachable;
            l.writer.print("\n", .{}) catch unreachable;
            return t1;
        }

        const PrimitiveFunction = struct {
            sym: []const u8,
            fun: *const fn (*Self, Expr, Expr) Expr,
        };
        const primitive_funs = [_]PrimitiveFunction{
            .{ .sym = "eval", .fun = f_eval },
            .{ .sym = "quote", .fun = f_quote },
            .{ .sym = "cons", .fun = f_cons },
            .{ .sym = "car", .fun = f_car },
            .{ .sym = "cdr", .fun = f_cdr },
            .{ .sym = "add", .fun = f_add },
            .{ .sym = "sub", .fun = f_sub },
            .{ .sym = "mul", .fun = f_mul },
            .{ .sym = "div", .fun = f_div },
            .{ .sym = "int", .fun = f_int },
            .{ .sym = "lt", .fun = f_lt },
            .{ .sym = "eq", .fun = f_eq },
            .{ .sym = "not", .fun = f_not },
            .{ .sym = "or", .fun = f_or },
            .{ .sym = "and", .fun = f_and },
            .{ .sym = "if", .fun = f_if },
            .{ .sym = "lambda", .fun = f_lambda },
            .{ .sym = "define", .fun = f_define },

            // debugging
            .{ .sym = "print-heap", .fun = f_print_heap },
            .{ .sym = "print-stack", .fun = f_print_stack },
            .{ .sym = "print-env", .fun = f_print_env },
            .{ .sym = "echo", .fun = f_echo },
            .{ .sym = "echo-evaluation", .fun = f_echo_evaluation },
        };

        // Parser --------------------------------------------------------------

        // pub fn parse(source: [:0]const u8) Expr {
        //     var tokenizer = Tokenizer.init(source);
        //     var expr = parseExpr(&tokenizer);
        //     return expr;
        // }

        fn parseExpr(l: *Self, tokenizer: *Tokenizer, token: Token) error{ParseError}!Expr {
            switch (token.tag) {
                .parenthesis_left => {
                    return try l.parseList(tokenizer);
                },
                .quote => {
                    const next_token = tokenizer.next();
                    const quoted_expr = try l.parseExpr(tokenizer, next_token);
                    return l.cons(l.atom("quote"), l.cons(quoted_expr, nil));
                },
                .integer, .real => {
                    const n = std.fmt.parseFloat(Expr, tokenizer.getTokenString(token).?) catch unreachable;
                    return n;
                },
                .symbol => {
                    return l.atom(tokenizer.getTokenString(token).?);
                },
                else => {
                    tokenizer.dump(l.writer, token) catch unreachable;
                    return error.ParseError;
                },
            }
        }

        fn parseList(l: *Self, tokenizer: *Tokenizer) error{ParseError}!Expr {
            // std.debug.assert(tokenizer.current_token.tag == .parenthesis_left);
            const token = tokenizer.next();
            switch (token.tag) {
                .parenthesis_right => {
                    return nil;
                },
                .dot => {
                    const next_token = tokenizer.next();
                    const last_expr = try l.parseExpr(tokenizer, next_token);
                    const right_paren = tokenizer.next();
                    // std.debug.assert(right_paren.tag == .parenthesis_right);
                    if (right_paren.tag != .parenthesis_right) {
                        return error.ParseError;
                    }
                    return last_expr;
                },
                else => {
                    const first_expr = try l.parseExpr(tokenizer, token);
                    const rest_expr = try l.parseList(tokenizer);
                    return l.cons(first_expr, rest_expr);
                },
            }
        }

        // GC ------------------------------------------------------------------

        fn gc(l: *Self) void {
            l.stack_ptr = ord(l.env);
        }

        // Printer -------------------------------------------------------------

        fn printNIL(l: *Self, x: Expr) !void {
            std.debug.assert(tag(x) == NIL);
            try l.writer.print("()", .{});
        }

        fn printATOM(l: *Self, x: Expr) !void {
            std.debug.assert(tag(x) == ATOM);
            try l.writer.print("{s}", .{l.atomName(x)});
        }

        fn printPRIM(l: *Self, x: Expr) !void {
            std.debug.assert(tag(x) == PRIM);
            try l.writer.print("<{s}>", .{primitive_funs[ord(x)].sym});
        }

        fn printCONS(l: *Self, x: Expr) !void {
            std.debug.assert(tag(x) == CONS);
            var t = x;
            try l.writer.print("(", .{});
            while (true) {
                try l.printExpr(l.car(t));
                t = l.cdr(t);
                switch (tag(t)) {
                    NIL => break,
                    CONS => {},
                    else => {
                        try l.writer.print(" . ", .{});
                        try l.printExpr(t);
                        break;
                    },
                }
                try l.writer.print(" ", .{});
            }
            try l.writer.print(")", .{});
        }

        fn printCLOS(l: *Self, x: Expr) !void {
            std.debug.assert(tag(x) == CLOS);
            try l.writer.print("<{d}>", .{ord(x)});
        }

        fn printNUM(l: *Self, x: Expr) !void {
            try l.writer.print("{d}", .{x});
        }

        fn printExpr(l: *Self, x: Expr) anyerror!void {
            switch (tag(x)) {
                NIL => try l.printNIL(x),
                ATOM => try l.printATOM(x),
                PRIM => try l.printPRIM(x),
                CONS => try l.printCONS(x),
                CLOS => try l.printCLOS(x),
                else => try l.printNUM(x),
            }
        }

        // Debugger ------------------------------------------------------------

        fn printHeap(l: *Self) !void {
            // TODO: use this value to generate the main fmt string used in this function
            const max_symbol_len = 20;

            try l.writer.print("------------------- HEAP -------------------\n", .{});
            try l.writer.print("|  #  |  address |  symbol                 |\n", .{});
            try l.writer.print("|-----|----------|-------------------------|\n", .{});

            var atom_count: usize = 0;
            var last_i: usize = 0;

            var trimmed_i: usize = undefined;
            var symbol_suffix: *const [3:0]u8 = undefined;

            for (l.heap, 0..) |byte, i| {
                if (byte != 0) continue;

                if (i == l.heap_ptr) {
                    try l.writer.print("|                    ...                   |\n", .{});
                    try l.writer.print("--------------------------------------------\n", .{});
                    break;
                }

                if (i - last_i <= max_symbol_len) {
                    trimmed_i = i;
                    symbol_suffix = "   ";
                } else {
                    trimmed_i = last_i + max_symbol_len;
                    symbol_suffix = "...";
                }
                try l.writer.print("| {:>3} |  0x{X:0>4}  |  {s:<20}{s}|\n", .{
                    atom_count,
                    last_i,
                    l.heap[last_i..trimmed_i],
                    symbol_suffix,
                });

                atom_count += 1;
                last_i = i + 1;
            }
        }

        fn printStack(l: *Self) !void {
            try l.writer.print("------------- STACK ------------\n", .{});
            try l.writer.print("|  pointer |   tag  |  ordinal |     Expr     \n", .{});
            try l.writer.print("|----------|--------|----------|--------------\n", .{});

            var counter: usize = 0;
            var sp: I = N;
            while (sp > l.stack_ptr) : (counter += 1) {
                try l.writer.print("|   {:>5}  |", .{N - counter});
                sp -= 1;
                const x = l.stack[sp];
                switch (tag(x)) {
                    NIL => try l.writer.print("  NIL   |   {:>5}  |  {s}\n", .{ ord(x), "()" }),
                    ATOM => try l.writer.print("  ATOM  |  0x{X:0>4}  |  {s}\n", .{ ord(x), l.atomName(x) }),
                    PRIM => try l.writer.print("  PRIM  |   {:>5}  |  <{s}>\n", .{ ord(x), primitive_funs[ord(x)].sym }),
                    CONS => try l.writer.print("  CONS  |   {:>5}  |\n", .{ord(x)}),
                    CLOS => try l.writer.print("  CLOS  |   {:>5}  |\n", .{ord(x)}),
                    else => try l.writer.print("        |          |  {d:<.10}\n", .{x}),
                }
            }
            try l.writer.print("|             ...              |\n", .{});
            try l.writer.print("|------------------------------|\n", .{});
        }

        fn printEnv(l: *Self, eIn: Expr) !void {
            var e = eIn;
            try l.writer.print("(\n", .{});
            while (!not(e)) {
                const p = l.car(e);
                try l.writer.print("\t", .{});
                try l.printExpr(p);
                try l.writer.print("\n", .{});
                e = l.cdr(e);
            }
            try l.writer.print(")\n", .{});
        }

        // REPL ------------------------------------------------------------------------

        pub fn repl(l: *Self) anyerror!void {
            var buffer: [1024]u8 = undefined;
            while (true) {
                try l.writer.print("In[]:= ", .{});
                const line = try readLineInput(l.reader, &buffer);
                var tokenizer = Tokenizer.init(line.?);
                inner: while (true) {
                    const token = tokenizer.next();
                    if (token.tag == .eof) {
                        break;
                    }
                    const parse_expr = l.parseExpr(&tokenizer, token) catch |err| {
                        switch (err) {
                            error.ParseError => {
                                try l.writer.print("<<ParseError>>\n\n", .{});
                                break :inner;
                            },
                        }
                    };
                    const eval_expr = l.eval(parse_expr, l.env);
                    try l.writer.print("Out[]= ", .{});
                    try l.printExpr(eval_expr);
                    try l.writer.print("\n\n", .{});
                    l.gc();
                }
            }
        }
    };
}

// Utilities -------------------------------------------------------------------

fn strlen(ptr: []u8) I {
    var i: I = 0;
    while (ptr[i] != 0) {
        i += 1;
    }
    return i;
}

fn readLineInput(reader: anytype, buffer: []u8) !?[:0]const u8 {
    var line = (try reader.readUntilDelimiterOrEof(
        buffer[0 .. buffer.len - 1],
        '\n',
    )) orelse return null;
    buffer[line.len + 1] = 0;
    return buffer[0 .. line.len + 1 :0];
}
