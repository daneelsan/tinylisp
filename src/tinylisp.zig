const std = @import("std");
const debug = std.debug;
const assert = debug.assert;
const io = std.io;
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

pub const Lisp = struct {
    reader: io.AnyReader = undefined,
    writer: io.AnyWriter = undefined,

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

    // TODO: make this configurable via build.zig
    /// number of cells for the shared stack and atom heap, increase N as desired
    const N = 256;

    pub fn init(l: *Lisp, reader: io.AnyReader, writer: io.AnyWriter) void {
        l.reader = reader;
        l.writer = writer;

        //l.heap = @as([*]u8, @ptrCast(@alignCast(l.stack[0..])))[0 .. l.stack.len * @sizeOf(Expr)];
        l.heap = std.mem.sliceAsBytes(l.stack[0..]);

        l.err = l.atom("ERR");
        l.tru = l.atom("#t");
        l.env = l.pair(l.tru, l.tru, nil);

        for (primitive_funs, 0..) |prim, i| {
            l.env = l.pair(l.atom(prim.sym), box(PRIM, i), l.env);
        }
    }

    // Errors --------------------------------------------------------------

    pub const Error = error{
        ParseError,
    } || io.AnyReader.Error || io.AnyWriter.Error;

    fn checkStack(l: Lisp) void {
        if (l.heap_ptr > (l.stack_ptr * @sizeOf(Expr))) {
            @panic("stack overflow");
        }
    }

    // Core ----------------------------------------------------------------

    /// interning of atom names (Lisp symbols), returns a unique NaN-boxed ATOM
    fn atom(l: *Lisp, str: []const u8) Expr {
        var i: I = 0;
        while (i < l.heap_ptr) {
            if (std.mem.eql(u8, l.heap[i .. i + str.len], str)) {
                return box(ATOM, i);
            } else {
                i += strlen(l.heap[i..]) + 1;
            }
        }

        if (i == l.heap_ptr) {
            @memcpy(l.heap[l.heap_ptr .. l.heap_ptr + str.len], str);
            l.heap[l.heap_ptr + str.len] = 0;

            l.heap_ptr += str.len + 1;
            l.checkStack();
        }

        return box(ATOM, i);
    }

    fn atomName(l: *Lisp, x: Expr) []const u8 {
        assert(tag(x) == ATOM);
        return std.mem.sliceTo(l.heap[ord(x)..], 0);
    }

    /// construct pair (x . y) returns a NaN-boxed CONS
    fn cons(l: *Lisp, x: Expr, y: Expr) Expr {
        l.stack_ptr -= 1;
        l.stack[l.stack_ptr] = x;
        l.stack_ptr -= 1;
        l.stack[l.stack_ptr] = y;
        l.checkStack();
        return box(CONS, l.stack_ptr);
    }

    /// return the car of a pair or ERR if not a pair
    fn car(l: *Lisp, x: Expr) Expr {
        return if ((tag(x) & ~(CONS ^ CLOS)) == CONS) l.stack[ord(x) + 1] else l.err;
    }

    /// return the cdr of a pair or ERR if not a pair
    fn cdr(l: *Lisp, x: Expr) Expr {
        return if ((tag(x) & ~(CONS ^ CLOS)) == CONS) l.stack[ord(x)] else l.err;
    }

    /// construct a pair to add to environment e, returns the list ((v . x) . e))
    fn pair(l: *Lisp, v: Expr, x: Expr, env: Expr) Expr {
        return l.cons(l.cons(v, x), env);
    }

    /// construct a closure, returns a NaN-boxed CLOS
    fn closure(l: *Lisp, vars: Expr, body: Expr, env: Expr) Expr {
        return box(CLOS, ord(l.pair(vars, body, if (equ(env, l.env)) nil else env)));
    }

    /// look up a symbol in an environment, return its value or ERR if not found
    fn assoc(l: *Lisp, a: Expr, env: Expr) Expr {
        var env_tmp = env;
        while (tag(env_tmp) == CONS and !equ(a, l.car(l.car(env_tmp)))) {
            env_tmp = l.cdr(env_tmp);
        }
        return if (tag(env_tmp) == CONS) l.cdr(l.car(env_tmp)) else l.err;
    }

    fn eval(l: *Lisp, x: Expr, env: Expr) Expr {
        return switch (tag(x)) {
            ATOM => l.assoc(x, env),
            CONS => l.apply(l.eval(l.car(x), env), l.cdr(x), env),
            else => x,
        };
    }

    fn apply(l: *Lisp, f: Expr, t: Expr, env: Expr) Expr {
        return switch (tag(f)) {
            PRIM => primitive_funs[ord(f)].fun(l, t, env),
            CLOS => l.reduce(f, t, env),
            else => l.err,
        };
    }

    /// apply closure `clos` to arguments `args` in environment `env`
    fn reduce(l: *Lisp, clos: Expr, args: Expr, env: Expr) Expr {
        const clos_fun = l.car(clos);
        const clos_env = l.cdr(clos);
        const clos_vars = l.car(clos_fun);
        const clos_body = l.cdr(clos_fun);
        const eval_args = l.evlis(args, env);
        return l.eval(clos_body, l.bind(clos_vars, eval_args, if (not(clos_env)) l.env else clos_env));
    }

    // create environment by extending `env` with variables `vars` bound to values `vals` */
    fn bind(l: *Lisp, vars: Expr, vals: Expr, env: Expr) Expr {
        return switch (tag(vars)) {
            NIL => env,
            CONS => l.bind(l.cdr(vars), l.cdr(vals), l.pair(l.car(vars), l.car(vals), env)),
            else => l.pair(vars, vals, env),
        };
    }

    // return a new list of evaluated Lisp expressions `t` in environment `env`
    fn evlis(l: *Lisp, t: Expr, env: Expr) Expr {
        return switch (tag(t)) {
            CONS => l.cons(l.eval(l.car(t), env), l.evlis(l.cdr(t), env)),
            ATOM => l.assoc(t, env),
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
    fn f_eval(l: *Lisp, t: Expr, env: Expr) Expr {
        return l.eval(l.car(l.evlis(t, env)), env);
    }

    /// (quote x) special form, returns x unevaluated "as is"
    fn f_quote(l: *Lisp, t: Expr, _: Expr) Expr {
        return l.car(t);
    }

    /// (cons x y) construct pair (x . y)
    fn f_cons(l: *Lisp, t: Expr, env: Expr) Expr {
        const t1 = l.evlis(t, env);
        return l.cons(l.car(t1), l.car(l.cdr(t1)));
    }

    /// (car p) car of pair p
    fn f_car(l: *Lisp, t: Expr, env: Expr) Expr {
        return l.car(l.car(l.evlis(t, env)));
    }

    /// (cdr p) cdr of pair p
    fn f_cdr(l: *Lisp, t: Expr, env: Expr) Expr {
        return l.cdr(l.car(l.evlis(t, env)));
    }

    /// (+ n1 n2 ... nk) sum of n1 to nk
    fn f_add(l: *Lisp, t: Expr, env: Expr) Expr {
        var t1 = l.evlis(t, env);
        var n = l.car(t1);
        while (true) {
            t1 = l.cdr(t1);
            if (not(t1)) break;
            n += l.car(t1);
        }
        return num(n);
    }

    /// (- n1 n2 ... nk) n1 minus sum of n2 to nk
    fn f_sub(l: *Lisp, t: Expr, env: Expr) Expr {
        var t1 = l.evlis(t, env);
        var n = l.car(t1);
        while (true) {
            t1 = l.cdr(t1);
            if (not(t1)) break;
            n -= l.car(t1);
        }
        return num(n);
    }

    /// (* n1 n2 ... nk) product of n1 to nk
    fn f_mul(l: *Lisp, t: Expr, env: Expr) Expr {
        var t1 = l.evlis(t, env);
        var n = l.car(t1);
        while (true) {
            t1 = l.cdr(t1);
            if (not(t1)) break;
            n *= l.car(t1);
        }
        return num(n);
    }

    /// (/ n1 n2 ... nk) n1 divided by the product of n2 to nk
    fn f_div(l: *Lisp, t: Expr, env: Expr) Expr {
        var t1 = l.evlis(t, env);
        var n = l.car(t1);
        while (true) {
            t1 = l.cdr(t1);
            if (not(t1)) break;
            n /= l.car(t1);
        }
        return num(n);
    }

    /// (int n) integer part of n
    fn f_int(l: *Lisp, t: Expr, env: Expr) Expr {
        const n = l.car(l.evlis(t, env));
        // TODO
        return n;
    }

    /// (< n1 n2) #t if n1<n2, otherwise ()
    fn f_lt(l: *Lisp, t: Expr, env: Expr) Expr {
        const t1 = l.evlis(t, env);
        const x = l.car(t1);
        const y = l.car(l.cdr(t1));
        return if ((x - y) < 0) l.tru else nil;
    }

    /// (> n1 n2) #t if n1>n2, otherwise ()
    fn f_gt(l: *Lisp, t: Expr, env: Expr) Expr {
        const t1 = l.evlis(t, env);
        const x = l.car(t1);
        const y = l.car(l.cdr(t1));
        return if ((x - y) > 0) l.tru else nil;
    }

    /// (= x y) #t if x equals y, otherwise ()
    fn f_eq(l: *Lisp, t: Expr, env: Expr) Expr {
        const t1 = l.evlis(t, env);
        const x = l.car(t1);
        const y = l.car(l.cdr(t1));
        return if (equ(x, y)) l.tru else nil;
    }

    /// (not x) #t if x is (), otherwise ()
    fn f_not(l: *Lisp, t: Expr, env: Expr) Expr {
        return if (not(l.car(l.evlis(t, env)))) l.tru else nil;
    }

    /// (or x1 x2 ... xk)   first x that is not (), otherwise ()
    fn f_or(l: *Lisp, t: Expr, env: Expr) Expr {
        var x = nil;
        var t1 = t;
        while (true) {
            if (not(t1)) break;
            x = l.eval(l.car(t1), env);
            if (!not(x)) break;
            t1 = l.cdr(t1);
        }
        return x;
    }

    /// (and x1 x2 ... xk) last x if all x are not (), otherwise ()
    fn f_and(l: *Lisp, t: Expr, env: Expr) Expr {
        var x = nil;
        var t1 = t;
        while (true) {
            if (not(t1)) break;
            x = l.eval(l.car(t1), env);
            if (not(x)) break;
            t1 = l.cdr(t1);
        }
        return x;
    }

    /// (if x y z) if x is non-() then y else z
    fn f_if(l: *Lisp, t: Expr, env: Expr) Expr {
        const cond = l.eval(l.car(t), env);
        const branch = if (not(cond)) l.cdr(t) else t;
        return l.eval(l.car(l.cdr(branch)), env);
    }

    /// (lambda v x) construct a closure
    fn f_lambda(l: *Lisp, t: Expr, env: Expr) Expr {
        return l.closure(l.car(t), l.car(l.cdr(t)), env);
    }

    /// (define v x) define a named value globally
    fn f_define(l: *Lisp, t: Expr, env: Expr) Expr {
        l.env = l.pair(l.car(t), l.eval(l.car(l.cdr(t)), env), l.env);
        return l.car(t);
    }

    fn f_print_heap(l: *Lisp, t: Expr, env: Expr) Expr {
        _ = t;
        _ = env;
        l.printHeap() catch unreachable;
        return nil;
    }

    fn f_print_stack(l: *Lisp, t: Expr, env: Expr) Expr {
        _ = t;
        _ = env;
        l.printStack() catch unreachable;
        return nil;
    }

    fn f_print_env(l: *Lisp, t: Expr, env: Expr) Expr {
        _ = t;
        l.printEnv(env) catch unreachable;
        return nil;
    }

    fn f_echo(l: *Lisp, t: Expr, env: Expr) Expr {
        const t1 = l.car(l.evlis(t, env));
        l.writer.print("    >> ", .{}) catch unreachable;
        l.printExpr(t1) catch unreachable;
        l.writer.print("\n", .{}) catch unreachable;
        return l.eval(t1, env);
    }

    fn f_echo_eval(l: *Lisp, t: Expr, env: Expr) Expr {
        l.writer.print("    >> ", .{}) catch unreachable;
        l.printExpr(t) catch unreachable;
        l.writer.print("\n", .{}) catch unreachable;
        l.writer.print("    << ", .{}) catch unreachable;
        const t1 = l.car(l.evlis(t, env));
        l.printExpr(t1) catch unreachable;
        l.writer.print("\n", .{}) catch unreachable;
        return t1;
    }

    const PrimitiveFunction = struct {
        sym: []const u8,
        fun: *const fn (*Lisp, Expr, Expr) Expr,
    };
    const primitive_funs = [_]PrimitiveFunction{
        .{ .sym = "eval", .fun = f_eval },
        .{ .sym = "quote", .fun = f_quote },
        .{ .sym = "cons", .fun = f_cons },
        .{ .sym = "car", .fun = f_car },
        .{ .sym = "cdr", .fun = f_cdr },
        .{ .sym = "int", .fun = f_int },
        .{ .sym = "+", .fun = f_add },
        .{ .sym = "-", .fun = f_sub },
        .{ .sym = "*", .fun = f_mul },
        .{ .sym = "/", .fun = f_div },
        .{ .sym = "<", .fun = f_lt },
        .{ .sym = ">", .fun = f_gt },
        .{ .sym = "=", .fun = f_eq },
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
        .{ .sym = "echo-eval", .fun = f_echo_eval },
    };

    // Parser --------------------------------------------------------------

    pub fn parse(l: *Lisp, source: [:0]const u8) !Expr {
        var tokenizer = Tokenizer.init(source);
        const expr = l.parseExpr(&tokenizer, tokenizer.next()) catch |err| {
            switch (err) {
                error.ParseError => {
                    try l.writer.print("[ERROR] Cannot parse \"{s}\".\n", .{source});
                    return err;
                },
                else => return err,
            }
        };
        return expr;
    }

    fn parseExpr(l: *Lisp, tokenizer: *Tokenizer, token: Token) error{ParseError}!Expr {
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

    fn parseList(l: *Lisp, tokenizer: *Tokenizer) error{ParseError}!Expr {
        const token = tokenizer.next();
        switch (token.tag) {
            .parenthesis_right => {
                return nil;
            },
            .dot => {
                const next_token = tokenizer.next();
                const last_expr = try l.parseExpr(tokenizer, next_token);
                const right_paren = tokenizer.next();
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

    fn garbageCollect(l: *Lisp) void {
        l.stack_ptr = ord(l.env);
    }

    // Printer -------------------------------------------------------------

    fn printNIL(l: *Lisp, x: Expr) !void {
        assert(tag(x) == NIL);
        try l.writer.print("()", .{});
    }

    fn printATOM(l: *Lisp, x: Expr) !void {
        assert(tag(x) == ATOM);
        try l.writer.print("{s}", .{l.atomName(x)});
    }

    fn printPRIM(l: *Lisp, x: Expr) !void {
        assert(tag(x) == PRIM);
        try l.writer.print("< {s} >", .{primitive_funs[ord(x)].sym});
    }

    fn printCONS(l: *Lisp, x: Expr) !void {
        assert(tag(x) == CONS);
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

    fn printCLOS(l: *Lisp, x: Expr) !void {
        assert(tag(x) == CLOS);
        try l.writer.print("<{d}>", .{ord(x)});
    }

    fn printNUM(l: *Lisp, x: Expr) !void {
        try l.writer.print("{d}", .{x});
    }

    fn printExpr(l: *Lisp, x: Expr) anyerror!void {
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

    fn printHeap(l: *Lisp) !void {
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
                l.heap[last_i..trimmed_i :0],
                symbol_suffix,
            });

            atom_count += 1;
            last_i = i + 1;
        }
    }

    fn printStack(l: *Lisp) !void {
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

    fn printEnv(l: *Lisp, eIn: Expr) !void {
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

    fn printReplOutput(l: *Lisp, expr: Expr) !void {
        try l.writer.print("Out[]= ", .{});
        // TODO: Implement Expr formatter
        try l.printExpr(expr);
        try l.writer.print("\n\n", .{});
    }

    // REPL ------------------------------------------------------------------------

    pub fn run(l: *Lisp, code: [:0]const u8) ?Expr {
        const parsed_expr = l.parse(code) catch {
            return null;
        };
        return l.eval(parsed_expr, l.env);
    }

    pub fn repl(l: *Lisp) !void {
        const max_buffer_size = 1024; // TODO: use build options
        while (true) {
            defer l.garbageCollect();
            try l.writer.print("In[]:= ", .{});
            // Read input
            var buffer = try std.BoundedArray(u8, max_buffer_size).init(0);
            try l.reader.streamUntilDelimiter(buffer.writer(), '\n', max_buffer_size);
            try buffer.append(0);
            const line = buffer.slice();
            // Tokenize, parse and evaluate code
            const eval_expr = l.run(line[0 .. line.len - 1 :0]) orelse l.err;
            // Print result
            try l.printReplOutput(eval_expr);
        }
    }
};

// Utilities -------------------------------------------------------------------

fn strlen(ptr: []u8) I {
    var i: I = 0;
    while (ptr[i] != 0) {
        i += 1;
    }
    return i;
}

test "tinylisp - atoms" {
    try testExprTag("#t", ATOM);
    try testExprTag("ERR", ATOM);
}

test "tinylisp - primitive" {
    try testExprTag("+", PRIM);
    try testExprTag("define", PRIM);
}

test "tinylisp - cons" {
    try testExprTag("'(1 . 2)", CONS);
    try testExprTag("'(1 2 3)", CONS);
}

fn testExprTag(source: [:0]const u8, expected_expr_tag: I) !void {
    const reader = std.io.getStdIn().reader().any();
    const writer = std.io.getStdOut().writer().any();

    var lisp = Lisp{};
    lisp.init(reader, writer);
    const eval_expr = lisp.run(source) orelse lisp.err;
    try std.testing.expectEqual(tag(eval_expr), expected_expr_tag);
}
