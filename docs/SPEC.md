# PCL Spec

Extracted and translated from `instructions.pdf` (NTUA Compilers 2026 assignment, Kostis
Sagonas). This is the canonical reference for day-to-day work — the PDF itself should not
need to be opened. If something here seems incomplete, ambiguous, or contradicted by the
PDF, re-check the PDF and fix this file.

This file is external and (mostly) frozen: it's what the course requires, not what we've
decided. For our own toolchain/pipeline choices, see [IMPLEMENTATION.md](IMPLEMENTATION.md).
For progress/status, see [PROGRESS.md](PROGRESS.md).

## Grading

| Part | Units | Bonus (no LLVM) |
|---|---|---|
| Lexer | 0.5 | – |
| Parser | 1.0 | – |
| Semantic analysis | 2.0 | – |
| Intermediate code | 2.0 | – |
| Optimization | 0.5 | +0.5 |
| Final code | – | +0.5 |
| **Total** | **6.0** | **+1.0** |

Implementation language: C/C++, Rust, Java, SML, OCaml, Haskell, or Python (others need
instructor sign-off). This project uses OCaml with ocamllex/ocamlyacc. Total is 6 units if
LLVM is used for the backend; using LLVM forfeits the "final code" and "no-LLVM" bonuses.
Using your own IR/optimizer instead of LLVM's earns an extra +1.0 bonus.

## 1. Lexical Units

**Keywords** (case-sensitive, always lowercase — 32 total):

```
and array begin boolean char dispose div do
else end false forward function goto if integer
label mod new nil not of or procedure
program real result return then true var while
```

**Identifiers**: ASCII letter, then any mix of letters/digits/underscore. Case-sensitive
(`foo`, `Foo`, `FOO` are distinct). Must not collide with a keyword.

**Integer constants**: unsigned, one or more decimal digits (`0`, `42`, `1284`, `00200`).

**Real constants**: integer part + `.` + fractional part, optional exponent (`E`/`e`,
optional sign, digits). Examples: `42.0`, `4.2e1`, `0.420e+2`, `42000.0e-3`.

**Character constants**: single char in `' '`. Either a printable char (not `'`, `"`, `\`)
or an escape sequence:

| Escape | Meaning |
|---|---|
| `\n` | line feed |
| `\t` | tab |
| `\r` | carriage return |
| `\0` | ASCII 0 |
| `\\` | backslash |
| `\'` | single quote |
| `\"` | double quote |

**String literals**: sequence of plain chars / escape sequences in `" "`. Cannot span
multiple source lines.

**Operators**: `= > < <> >= <= + - * / ^ @`

**Delimiters**: `:= ; . ( ) : , [ ]`

**Whitespace**: space, tab, line feed, carriage return — separates tokens, otherwise
ignored.

**Comments**: `(* ... *)`, terminated by the first following `*)`. **Not nestable.** Any
character allowed inside.

## 2. Grammar

### 2.1 Terminal Symbols

- `⟨id⟩` — Identifier (alphanumeric + underscore, case-sensitive)
- `⟨integer-const⟩` — Integer constant (unsigned)
- `⟨real-const⟩` — Real constant (with optional exponent)
- `⟨char-const⟩` — Character constant in single quotes
- `⟨string-literal⟩` — String literal in double quotes

### 2.2 EBNF

```
⟨program⟩ ::= "program" ⟨id⟩ ";" ⟨body⟩ "."

⟨body⟩ ::= (⟨local⟩)* ⟨block⟩

⟨local⟩ ::= "var" (⟨id⟩ ("," ⟨id⟩)* ":" ⟨type⟩ ";")+ 
           | "label" ⟨id⟩ ("," ⟨id⟩)* ";"
           | ⟨header⟩ ";" ⟨body⟩ ";"
           | "forward" ⟨header⟩ ";"

⟨header⟩ ::= "procedure" ⟨id⟩ "(" [⟨formal⟩ (";" ⟨formal⟩)*] ")"
            | "function" ⟨id⟩ "(" [⟨formal⟩ (";" ⟨formal⟩)*] ")" ":" ⟨type⟩

⟨formal⟩ ::= ["var"] ⟨id⟩ ("," ⟨id⟩)* ":" ⟨type⟩

⟨type⟩ ::= "integer" 
          | "real" 
          | "boolean" 
          | "char"
          | "array" ["[" ⟨integer-const⟩ "]"] "of" ⟨type⟩
          | "^" ⟨type⟩

⟨block⟩ ::= "begin" ⟨stmt⟩ (";" ⟨stmt⟩)* "end"

⟨stmt⟩ ::= ε                                    (empty statement)
          | ⟨l-value⟩ ":=" ⟨expr⟩
          | ⟨block⟩
          | ⟨call⟩
          | "if" ⟨expr⟩ "then" ⟨stmt⟩ ["else" ⟨stmt⟩]
          | "while" ⟨expr⟩ "do" ⟨stmt⟩
          | ⟨id⟩ ":" ⟨stmt⟩
          | "goto" ⟨id⟩
          | "return"
          | "new" ["[" ⟨expr⟩ "]"] ⟨l-value⟩
          | "dispose" ["[]"] ⟨l-value⟩

⟨expr⟩ ::= ⟨l-value⟩ | ⟨r-value⟩

⟨l-value⟩ ::= ⟨id⟩
             | "result"
             | ⟨string-literal⟩
             | ⟨l-value⟩ "[" ⟨expr⟩ "]"
             | ⟨expr⟩ "^"
             | "(" ⟨l-value⟩ ")"

⟨r-value⟩ ::= ⟨integer-const⟩
             | "true"
             | "false"
             | ⟨real-const⟩
             | ⟨char-const⟩
             | "(" ⟨r-value⟩ ")"
             | "nil"
             | ⟨call⟩
             | "@" ⟨l-value⟩
             | ⟨unop⟩ ⟨expr⟩
             | ⟨expr⟩ ⟨binop⟩ ⟨expr⟩

⟨call⟩ ::= ⟨id⟩ "(" [⟨expr⟩ ("," ⟨expr⟩)*] ")"

⟨unop⟩ ::= "not" | "+" | "-"

⟨binop⟩ ::= "+" | "-" | "*" | "/" | "div" | "mod" 
            | "or" | "and"
            | "=" | "<>" | "<" | "<=" | ">" | ">="
```

### 2.3 Operator Precedence and Associativity

From highest to lowest precedence:

| Operators | Description | Operands | Position | Associativity |
|-----------|-------------|----------|----------|---------------|
| `[]` | Array subscript | 2 | special | - |
| `@` | Address of | 1 | prefix | - |
| `^` | Dereference | 1 | postfix | - |
| `+` `-` | Sign (unary) | 1 | prefix | - |
| `not` | Logical negation | 1 | prefix | - |
| `*` `/` `div` `mod` `and` | Multiplicative | 2 | infix | left |
| `+` `-` `or` | Additive | 2 | infix | left |
| `=` `<>` `<` `<=` `>` `>=` | Relational | 2 | infix | none |

### 2.4 Notes

- **Ambiguity:** This grammar is ambiguous; the precedence/associativity table above
  resolves all ambiguities.
- **If/then/else:** shift/reduce ambiguity — resolved by longest match (`else` binds to the
  nearest unmatched `if`).
- **Comments:** not shown in the grammar; `(*` ... `*)` are lexical elements, ignored by the
  parser, and cannot nest (see §1).
- **Whitespace:** ignored by the lexer.
- **Case sensitivity:** identifiers are case-sensitive; keywords are lowercase only.

## 3. Data Types

**Basic types**: `integer`, `boolean`, `char`, `real`.

**Composite types**:
- `array [n] of t` — `n` elements of type `t`; `n` must be a positive integer constant,
  `t` a valid type.
- `array of t` — unknown-length array of `t`; `t` must be a valid type. Used for
  parameters/pointees, not for standalone variable declarations.
- `^t` — pointer to `t`; `t` must be a valid type.

`integer` and `real` are called **arithmetic types**. Basic types, fixed-size array types,
and pointer types are **complete types**. Unsized array types (`array of t`) are
**incomplete types**. When forming an array type (sized or not), the element type `t` must
be complete. Array indexing is 0-based, C-style: element indices run `0 .. n-1`.

**x86-64 size/representation assumptions** (implementation-defined per spec, but these are
the assumptions to build against):

| Type | Size | Representation |
|---|---|---|
| `integer` | ≥ 4 bytes | two's complement |
| `boolean` | 1 byte | `false = 0`, `true = 1` |
| `char` | 1 byte | ASCII |
| `real` | ≥ 8 bytes | IEEE 754 |
| `array [n] of t` | `n * sizeof(t)` | ascending address order |
| `^t` | 8 bytes | — |

## 4. Program Structure

Header: `program p;` where `p` is the program name. A program (and every subprogram) is a
**structural unit** consisting of a header and a body. A body optionally contains, in any
order/repetition: variable declarations, label declarations, subprogram definitions,
forward subprogram declarations — followed by a mandatory compound statement (the unit's
block). For the main program, execution starts at this block.

Scoping follows ISO Pascal rules (lexical scoping, nested scopes from nested subprograms,
shadowing allowed).

> **Not specified by the course:** how to actually implement this (symbol table data
> structure, what fields each entry tracks, lookup strategy). The PDF gives no design here —
> it's entirely on us to decide. **Before designing/implementing the symbol table, ask the
> user first** — don't pick an approach unilaterally.

**Variables**: declared with `var`, one or more names then `: type;`. Consecutive `var`
blocks can omit the repeated `var` keyword:
```pascal
var i : integer;
    x, y : real;
var s : array [80] of char;
```
Declared type must be complete.

**Subprograms**: `procedure` (no return value) or `function` (returns one value; return
type cannot be an array type). Parentheses are mandatory even with zero parameters. Each
formal parameter has a name, type, and passing mode:
- **by value** (default) — cannot be an array type.
- **by reference** — prefixed with `var` in the declaration.

```pascal
procedure p1 ();
procedure p2 (n : integer);
procedure p3 (a, b : integer; var b : boolean);
function f1 (x : real) : real;
function f2 (var s : array of char) : integer;
function f3 (n : integer; x : real) : ^array of real;
```

Mutually recursive subprograms require a `forward` declaration of the header (no body)
before the point where the name is first used, so scope rules aren't violated:
```pascal
forward procedure p2 (n : integer);
```

## 5. Expressions

Every expression has a unique type, evaluating to a value of that type — except `nil`
(§5.2), which has no unique type.

### 5.1 L-values

Objects that occupy memory and can hold values (variables, parameters, dynamically
allocated objects, function-result storage):

- A variable/parameter name — type is the object's type.
- A string literal constant — type `array [n] of char`, `n` = literal length + 1 (for the
  auto-appended `'\0'`, C-string convention). The **only** array-typed constant PCL allows.
- `l[e]` — if `l` is an l-value of type `array [n] of t` or `array of t`, and `e` is an
  `integer` expression, `l[e]` is an l-value of type `t`. Index must not exceed the array's
  real bound.
- `e^` — if `e` is an expression of type `^t`, `e^` is an l-value of type `t` (the pointee).
- `result` — inside a function body only; l-value of the function's return type, holding
  the return value. Temporary — must not be used after the function returns.
- `(l)` — parenthesized l-value, for grouping.

Using an l-value as an expression yields the value stored in the corresponding object.

### 5.2 Constants (r-values)

- Integer constants — type `integer`.
- `true` / `false` — type `boolean`.
- Real constants — type `real`.
- Character constants — type `char`.
- `nil` — type `^t` for **any** valid `t`; the only PCL expression without a unique type.
  Dereferencing the null pointer (`^`) is forbidden.

### 5.3 Operators

Unary ops are prefix or postfix; binary ops are always infix, left-to-right operand
evaluation. `[]` (array subscript, §5.1) and `^` (dereference, §5.1) are the only two
operators producing an l-value; everything below produces an r-value.

- `@l` — address-of. `l` must be an l-value of type `t`; result is r-value of type `^t`,
  the object's address, always non-null.
- Unary `+` `-` — operand must be arithmetic (`integer`/`real`); result is the same type.
- `not` — operand must be `boolean`; result `boolean`.
- Binary `+` `-` `*` — operands must be arithmetic. Both `integer` → result `integer`;
  otherwise → result `real`.
- Binary `/` — operands arithmetic; result is **always** `real`.
- `div` `mod` — both operands must be `integer`; result `integer`.
- `=` `<>` — operands either both arithmetic (compared by value) or the same non-array
  type (compared by bit representation); result `boolean`.
- `<` `>` `<=` `>=` — both operands arithmetic; result `boolean`.
- `and` `or` — both operands `boolean`; result `boolean`. **Short-circuit evaluation**: the
  second operand is not evaluated if the first alone determines the result.

Precedence/associativity table: §2.3.

### 5.4 Function Calls

`f(e1, ..., en)` is an r-value of type `t` (`f`'s return type). Argument count must match
`f`'s formal parameter count. Per-argument compatibility (see §7 for "assignment
compatible"):
- If the formal is **by value** of type `t`, the actual's type must be assignment-compatible
  with `t`.
- If the formal is **by reference** of type `t`, the actual must be an l-value of type `t'`,
  where `^t'` is assignment-compatible with `^t`.

Arguments are evaluated left to right.

## 6. Statements

- Empty statement — no-op.
- `l := e` — assignment; `e`'s type must be assignment-compatible with `l`'s type (§7, not
  symmetric).
- `begin s1; s2; ...; sn end` — compound statement; sequential execution unless a jump
  occurs.
- `if e then s1 [else s2]` — `e` must be `boolean`; `else` optional.
- `while e do s` — `e` must be `boolean`.
- `I : s` — labeled statement. `I` must be declared in the unit's `label` section and
  defined at most once in the unit's block.
- `goto I` — `I` must be a label in the **same** structural unit. No other placement
  restrictions.
- `return` — terminates execution of the current structural unit.
- Procedure call — same syntax/semantics as a function call, minus the result.
- `new l` — `l` must be an l-value of type `^t`, `t` complete. Allocates a new object of
  type `t`; `l` points to it afterward.
- `new [e] l` — `l` must be an l-value of type `^array of t`; `e` an `integer` expression
  evaluating to a positive `n`. Allocates `array [n] of t`; `l` points to it afterward.
- `dispose l` — `l` : `^t`, `t` complete, must currently point to a `new`-allocated object.
  After execution, `l` is `nil`.
- `dispose [] l` — `l` : `^array of t`, must currently point to a `new`-allocated object.
  After execution, `l` is `nil`.

## 7. Type Coercion / Assignment Compatibility

Governs `l := e`, by-value argument passing, and (via `^t`) by-reference argument passing.
**Not symmetric.**

- Every complete type is assignment-compatible with itself.
- `integer` is assignment-compatible with `real` (widening only — `real` is *not*
  assignment-compatible with `integer`).
- `^array [n] of t` is assignment-compatible with `^array of t` (sized pointer-to-array
  widens to unsized; not the reverse).

See §5.3 for the separate (non-assignment) arithmetic result-type rules (`+ - *` `/`
`div mod`).

## 8. Standard Library

Visible in every structural unit unless shadowed by a variable/parameter/subprogram of the
same name.

### 8.1 I/O

```pascal
procedure writeInteger (n : integer);
procedure writeBoolean (b : boolean);
procedure writeChar (c : char);
procedure writeReal (r : real);
procedure writeString (var s : array of char);

function  readInteger () : integer;
function  readBoolean () : boolean;
function  readChar () : char;
function  readReal () : real;
procedure readString (size : integer; var s : array of char);
```
`readString` reads up to the next newline (newline itself is discarded, not stored). `size`
caps the number of characters written into `s`, including the terminating `'\0'`. If the
buffer fills before a newline is seen, the rest of the line is consumed on a later read.

### 8.2 Math

```pascal
function abs    (n : integer) : integer;
function fabs   (r : real) : real;
function sqrt   (r : real) : real;
function sin    (r : real) : real;
function cos    (r : real) : real;
function tan    (r : real) : real;
function arctan (r : real) : real;
function exp    (r : real) : real;
function ln     (r : real) : real;
function pi     () : real;
```

### 8.3 Conversion

```pascal
function trunc (r : real) : integer;  (* truncate toward zero *)
function round (r : real) : integer;  (* nearest; ties favor larger absolute value *)
function ord   (c : char) : integer;  (* char -> ASCII code *)
function chr   (n : integer) : char;  (* ASCII code -> char *)
```

## 9. CLI / Build / Output Requirements

Executable name: `pclc`.

**Flags**:
- `-o file` — write the produced executable to `file` (default: `./a.out`, i.e. the
  current directory when `pclc` is invoked).
- `-O` — enable optimization (optional).
- `-f` — read source from stdin, write final (assembly) code to stdout.
- `-i` — read source from stdin, write intermediate code to stdout.
- Default (neither `-f` nor `-i`): source file is the sole positional argument (any
  extension, e.g. `*.pcl`). Produces `<basename>.imm` (intermediate code) and
  `<basename>.asm` (final code) alongside the source file. E.g. `/tmp/hello.pcl` →
  `/tmp/hello.imm`, `/tmp/hello.asm`.

**Exit codes**: `pclc` itself must return 0 on successful compilation, non-zero otherwise.
The **generated executable** must also return 0 on successful execution — verified by e.g.
`./a.out && ./a.out` printing `hello.pcl`'s output twice, not once.

**Makefile** targets required:
- `make` — builds the `pclc` executable.
- `make clean` — removes all auto-generated files (flex/bison outputs, `.o` files, etc.)
  but keeps the final executable.
- `make distclean` — `make clean` plus removes the final executable too.

**Intermediate code (TAC) format**: quadruples formatted equivalently to
`printf("%d: %s, %s, %s, %s\n", ...)`.

**Final assembly format**: tab-indented, following:
```
label:<TAB>instr<TAB>arg1, arg2
<TAB>instr<TAB>arg1, arg2
```

> **Caveat:** the PDF states both formats should follow "what's proposed in the book and in
> the lectures" — the templates above are its own gloss on that, not necessarily the full
> picture. If course textbook/lecture material is available and says something more
> specific, that takes precedence over this section.

## 10. Example Programs

Canonical examples from the spec, mirrored in `test/`:

| File | Demonstrates |
|---|---|
| `test/hello.pcl` | Minimal program, `writeString` |
| `test/hanoi.pcl` | Recursion, string parameters, nested procedures |
| `test/primes.pcl` | Functions, loops, `if`/`else if` chains, early `return` |
| `test/reverse.pcl` | Arrays, string manipulation, string-literal l-values |
| `test/bsort.pcl` | Array parameters, nested procedures, by-reference params |
| `test/mean.pcl` | `real` arithmetic, type coercion (`integer` → `real`) |
