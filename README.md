# tinylisp

A lisp implemented using NaN boxing and in Zig.

## Examples

### Arithmetic

add, sub, mul, div:

```lisp
In[]:= (add 1 2 3 4)
Out[]= 10
```

```lisp
In[]:= (div 3.4 4)
Out[]= 0.85
```

### Structural

car, cdr, cons:
```lisp
In[]:= (car '(1 2 3))
Out[]= 1
```

```lisp
In[]:= (cons 1 2)
Out[]= (1 . 2)
```

## Build

Compiled using zig version:
```shell
$ zig version
0.11.0
```

Compile the main.zig file using `zig build-exe`:
```shell
$ zig build-exe src/main.zig

$ ./main
```

Or run it directly using `zig run`:
```shell
$ zig run src/main.zig
```

## TODO:

- [] Compile to .wasm and add a javascript REPL
- [] Expand documentation

## Resources
* [Lisp in 99 lines of C and how to write one yourself - Robert-van-Engelen](https://github.com/Robert-van-Engelen/tinylisp#lisp-in-99-lines-of-c-and-how-to-write-one-yourself)
