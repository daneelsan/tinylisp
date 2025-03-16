# tinylisp

tinylisp is a minimal Lisp interpreter implemented in Zig, using NaN boxing for efficient memory representation. It supports core Lisp features like atoms, lists, conditionals, arithmetic, and closures, along with an interactive REPL and debugging tools for inspecting the heap, stack, and environment.

## Documentation

### Atoms

`#t` (True):
```lisp
In[]:= #t
Out[]= #t
```

`ERR` (Error):
```lisp
In[]:= (cdr 42)
Out[]= ERR
```

### Arithmetic

`+` (Addition):
```lisp
In[]:= (+ 1 2 3 4)
Out[]= 10
```

`-` (Subtraction):
```lisp
In[]:= (- 10 2 3)
Out[]= 5
```

`*` (Multiplication):
```lisp
In[]:= (* 2 3 4)
Out[]= 24
```

`/` (Division):
```lisp
In[]:= (/ 3.4 4)
Out[]= 0.85
```

### Structural

`car`:
```lisp
In[]:= (car '(1 2 3))
Out[]= 1
```

`cdr`:
```lisp
In[]:= (cdr '(1 2 3))
Out[]= (2 3)
```

`cons`:
```lisp
In[]:= (cons 1 2)
Out[]= (1 . 2)
```
```lisp
In[]:= (cons 1 '(2 3))
Out[]= (1 2 3)
```

### Quoting and Evaluation

`'` (Quoting):
```lisp
In[]:= '(+ 1 2 3)
Out[]= (+ 1 2 3)
```

`eval` (Evaluation):
```lisp
In[]:= (eval '(+ 1 2 3))
Out[]= 6
```


### Conditionals and Logic

`if`:
```lisp
In[]:= (if (< 1 2) 'true 'false)
Out[]= true
```

`and`:
```lisp
In[]:= (and (< 1 2) (< 2 3))
Out[]= #t
```
```lisp
In[]:= (and (< 2 1) (< 2 3))
Out[]= ()
```

`or`:
```lisp
In[]:= (or (< 1 2) (< 3 2))
Out[]= #t
```

`not`:
```lisp
In[]:= (not (< 1 2))
Out[]= ()
```

`=` (Equality):
```lisp
In[]:= (= 1.0 1)
Out[]= #t
```
```lisp
In[]:= (= 1.1 1)
Out[]= ()
```

### Lambdas and Closures

`lambda`:
```lisp
In[]:= ((lambda (x) (* x x)) 5)
Out[]= 25
```

`define`:
```lisp
In[]:= (define square (lambda (x) (* x x)))
Out[]= square
```
```lisp
In[]:= (square 5)
Out[]= 25
```

### Debugging and Introspection

`echo`:
```lisp
In[]:= (+ (echo (* 3 4) 5))
    >> 12
Out[]= 12
```

`echo-eval`:
```lisp
In[]:= (echo-eval (+ (* 3 4) 5))
    >> ((+ (* 3 4) 5))
    << 17
Out[]= 17
```

`print-env`:
```lisp
In[]:= (print-env)
(
	(echo-evaluation . <echo-evaluation>)
	(echo . <echo>)
	(print-env . <print-env>)
	(print-stack . <print-stack>)
	(print-heap . <print-heap>)
	(define . <define>)
	(lambda . <lambda>)
	(if . <if>)
	(and . <and>)
	(or . <or>)
	(not . <not>)
	(= . <=>)
	(> . <>>)
	(< . <<>)
	(/ . </>)
	(* . <*>)
	(- . <->)
	(+ . <+>)
	(int . <int>)
	(cdr . <cdr>)
	(car . <car>)
	(cons . <cons>)
	(quote . <quote>)
	(eval . <eval>)
	(#t . #t)
)
Out[]= ()
```

`print-heap`:
```lisp
In[]:= (print-heap)
------------------- HEAP -------------------
|  #  |  address |  symbol                 |
|-----|----------|-------------------------|
|   0 |  0x0000  |  ERR                    |
|   1 |  0x0004  |  #t                     |
|   2 |  0x0007  |  eval                   |
|   3 |  0x000C  |  quote                  |
|   4 |  0x0012  |  cons                   |
|   5 |  0x0017  |  car                    |
|   6 |  0x001B  |  cdr                    |
|   7 |  0x001F  |  int                    |
|   8 |  0x0023  |  +                      |
|   9 |  0x0025  |  -                      |
|  10 |  0x0027  |  *                      |
|  11 |  0x0029  |  /                      |
|  12 |  0x002B  |  <                      |
|  13 |  0x002D  |  >                      |
|  14 |  0x002F  |  =                      |
|  15 |  0x0031  |  not                    |
|  16 |  0x0035  |  or                     |
|  17 |  0x0038  |  and                    |
|  18 |  0x003C  |  if                     |
|  19 |  0x003F  |  lambda                 |
|  20 |  0x0046  |  define                 |
|  21 |  0x004D  |  print-heap             |
|  22 |  0x0058  |  print-stack            |
|  23 |  0x0064  |  print-env              |
|  24 |  0x006E  |  echo                   |
|  25 |  0x0073  |  echo-evaluation        |
|                    ...                   |
--------------------------------------------
Out[]= ()
```

`print-stack`:
```lisp
In[]:= (print-stack)
------------- STACK ------------
|  pointer |   tag  |  ordinal |     Expr
|----------|--------|----------|--------------
|     256  |  ATOM  |  0x0004  |  #t
|     255  |  ATOM  |  0x0004  |  #t
|     254  |  CONS  |     254  |
|     253  |  NIL   |       0  |  ()
|     252  |  ATOM  |  0x0007  |  eval
|     251  |  PRIM  |       0  |  <eval>
|     250  |  CONS  |     250  |
|     249  |  CONS  |     252  |
|     248  |  ATOM  |  0x000C  |  quote
|     247  |  PRIM  |       1  |  <quote>
|     246  |  CONS  |     246  |
|     245  |  CONS  |     248  |
|     244  |  ATOM  |  0x0012  |  cons
|     243  |  PRIM  |       2  |  <cons>
|     242  |  CONS  |     242  |
|     241  |  CONS  |     244  |
|     240  |  ATOM  |  0x0017  |  car
|     239  |  PRIM  |       3  |  <car>
|     238  |  CONS  |     238  |
|     237  |  CONS  |     240  |
|     236  |  ATOM  |  0x001B  |  cdr
|     235  |  PRIM  |       4  |  <cdr>
|     234  |  CONS  |     234  |
|     233  |  CONS  |     236  |
|     232  |  ATOM  |  0x001F  |  int
|     231  |  PRIM  |       5  |  <int>
|     230  |  CONS  |     230  |
|     229  |  CONS  |     232  |
|     228  |  ATOM  |  0x0023  |  +
|     227  |  PRIM  |       6  |  <+>
|     226  |  CONS  |     226  |
|     225  |  CONS  |     228  |
|     224  |  ATOM  |  0x0025  |  -
|     223  |  PRIM  |       7  |  <->
|     222  |  CONS  |     222  |
|     221  |  CONS  |     224  |
|     220  |  ATOM  |  0x0027  |  *
|     219  |  PRIM  |       8  |  <*>
|     218  |  CONS  |     218  |
|     217  |  CONS  |     220  |
|     216  |  ATOM  |  0x0029  |  /
|     215  |  PRIM  |       9  |  </>
|     214  |  CONS  |     214  |
|     213  |  CONS  |     216  |
|     212  |  ATOM  |  0x002B  |  <
|     211  |  PRIM  |      10  |  <<>
|     210  |  CONS  |     210  |
|     209  |  CONS  |     212  |
|     208  |  ATOM  |  0x002D  |  >
|     207  |  PRIM  |      11  |  <>>
|     206  |  CONS  |     206  |
|     205  |  CONS  |     208  |
|     204  |  ATOM  |  0x002F  |  =
|     203  |  PRIM  |      12  |  <=>
|     202  |  CONS  |     202  |
|     201  |  CONS  |     204  |
|     200  |  ATOM  |  0x0031  |  not
|     199  |  PRIM  |      13  |  <not>
|     198  |  CONS  |     198  |
|     197  |  CONS  |     200  |
|     196  |  ATOM  |  0x0035  |  or
|     195  |  PRIM  |      14  |  <or>
|     194  |  CONS  |     194  |
|     193  |  CONS  |     196  |
|     192  |  ATOM  |  0x0038  |  and
|     191  |  PRIM  |      15  |  <and>
|     190  |  CONS  |     190  |
|     189  |  CONS  |     192  |
|     188  |  ATOM  |  0x003C  |  if
|     187  |  PRIM  |      16  |  <if>
|     186  |  CONS  |     186  |
|     185  |  CONS  |     188  |
|     184  |  ATOM  |  0x003F  |  lambda
|     183  |  PRIM  |      17  |  <lambda>
|     182  |  CONS  |     182  |
|     181  |  CONS  |     184  |
|     180  |  ATOM  |  0x0046  |  define
|     179  |  PRIM  |      18  |  <define>
|     178  |  CONS  |     178  |
|     177  |  CONS  |     180  |
|     176  |  ATOM  |  0x004D  |  print-heap
|     175  |  PRIM  |      19  |  <print-heap>
|     174  |  CONS  |     174  |
|     173  |  CONS  |     176  |
|     172  |  ATOM  |  0x0058  |  print-stack
|     171  |  PRIM  |      20  |  <print-stack>
|     170  |  CONS  |     170  |
|     169  |  CONS  |     172  |
|     168  |  ATOM  |  0x0064  |  print-env
|     167  |  PRIM  |      21  |  <print-env>
|     166  |  CONS  |     166  |
|     165  |  CONS  |     168  |
|     164  |  ATOM  |  0x006E  |  echo
|     163  |  PRIM  |      22  |  <echo>
|     162  |  CONS  |     162  |
|     161  |  CONS  |     164  |
|     160  |  ATOM  |  0x0073  |  echo-evaluation
|     159  |  PRIM  |      23  |  <echo-evaluation>
|     158  |  CONS  |     158  |
|     157  |  CONS  |     160  |
|     156  |  ATOM  |  0x0058  |  print-stack
|     155  |  NIL   |       0  |  ()
|             ...              |
|------------------------------|
Out[]= ()
```

## Build

Compiled using zig version:
```shell
$ zig version
0.14.0
```

Build the executable using `zig build`:
```shell
$ zig build

$ ls zig-out/bin
tinylisp
```

Or run it directly using `zig build run`:
```shell
$ zig build run
In[]:=
```

## TODO:

- [ ] Compile to .wasm and add a javascript REPL
- [ ] Add more tests
- [ ] Expand documentation

## Resources
* [Lisp in 99 lines of C and how to write one yourself - Robert-van-Engelen](https://github.com/Robert-van-Engelen/tinylisp#lisp-in-99-lines-of-c-and-how-to-write-one-yourself)
