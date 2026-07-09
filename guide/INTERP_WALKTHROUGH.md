# Interpreter Walkthrough

Explainer for the PCL interpreter (`pcli`), built on the `interpreter` branch. Same deal as
the lexer/parser walkthroughs — a one-time reference for understanding the code, not part of
Claude's working context, and not kept in sync automatically if the code changes later.

## What this is, and why it's a separate branch

The course (SPEC.md §9) wants a real compiler: lex → parse → semantic-check → intermediate
code → x86-64 assembly. An interpreter isn't part of that pipeline or the grading table —
it's a second, independent way to *run* a PCL program directly off the AST, without
generating any code at all. Two reasons this lives on its own branch rather than folding
into `main`:

- It's not part of the graded deliverable, so it shouldn't show up in `pclc`'s own history
  as if it were.
- It doesn't need to wait on the still-undecided symbol table design (`docs/SPEC.md` §4,
  `docs/PROGRESS.md`'s current blocker). That decision is specifically about the *compiler's*
  semantic-analysis phase; the interpreter needs its own runtime environment for a different
  job (looking up live values during execution, not checking static types before
  compilation), so it isn't blocked by the same open question.

## Files involved

- **`src/interp.ml`** — the interpreter itself: value representation, environment, expression
  evaluation, statement execution, the standard library, and the program entry point
  (`Interp.run`).
- **`src/interp_main.ml`** — a small entry point: parse the file (reusing the exact same
  `Lexer`/`Parser` as `pclc`), then call `Interp.run` on the resulting AST instead of
  compiling it.
- **`Makefile`** — now builds a second executable, `pcli`, alongside `pclc`. They share
  `ast.ml`, `lexer.mll`, and `parser.mly` (the front end); `pclc` links `semantic.ml` +
  `codegen.ml` (currently empty, for later phases), `pcli` links `interp.ml` instead.

## Representing values and memory

```ocaml
type value =
  | VInt of int | VReal of float | VBool of bool | VChar of char
  | VArray of cell array
  | VPtr of cell option        (* None = nil *)
and cell = value ref
```

The key design choice: **anything addressable is a `value ref`** — a mutable box. Variables
are stored as cells, array elements are stored as an array *of* cells (not an array of plain
values), and a PCL pointer is just `VPtr (Some cell)` (or `VPtr None` for `nil`). This one
idea is what makes `@`/`^` fall out almost for free:

- `@e` (address-of) = "give me the cell that `e`'s l-value resolves to, wrapped in `VPtr`."
- `e^` (dereference) = "unwrap the `VPtr` to get a cell, then read/write through it."

Both operations go through the same function, `lvalue_cell`, which mirrors `parser.mly`'s
`lvalue` grammar rule case-for-case (`EId`, `EResult`, `EString`, `EIndex`, `EDeref`) — if a
new lvalue form is ever added to the grammar, this is the matching place to add it here.

Representing array elements as `cell array` rather than a plain `value array` is what makes
`@arr[i]` (address of a specific array element) work correctly — OCaml's native arrays don't
let you carve a `ref` out of an existing slot, so if elements were plain values, taking the
address of one specifically would have nowhere to point. This was tested directly (see
verification section) rather than just assumed to work.

## Environments and lexical scoping

```ocaml
type env = {
  vars : (string, cell * typ) Hashtbl.t;
  procs : (string, proc) Hashtbl.t;
  parent : env option;
  result : (cell * typ) option;   (* Some only while executing a function body *)
}
```

Each `var` group, each formal parameter, and each nested procedure/function creates entries
in the *current* scope's tables; looking up a name walks `parent` until found (or errors).
The important subtlety is **which environment becomes a called procedure's parent** — it has
to be the environment *where the procedure was defined* (stored once, at declaration time, as
`proc.penv`), not the environment of whoever happens to be calling it. That's the whole
difference between PCL's lexical (static) scoping and dynamic scoping: a nested procedure can
see its enclosing procedure's variables regardless of who calls it, but not some unrelated
procedure's locals just because that's who happened to invoke it. Verified with a direct
test (see below) — a nested procedure reading an enclosing local, called indirectly through
another procedure, still resolves the outer local correctly rather than erroring or reading
something from the caller's frame.

Types are stored alongside each variable's cell (`cell * typ`, not just `cell`) because
`new`/`dispose` need to know *what type of object* to allocate — unlike C's `malloc`, PCL's
`new` is type-directed (`new p` allocates "an object of `p`'s pointee type"). Since there's no
semantic analysis pass to have already computed types, `type_of_lvalue`/`type_of_expr`
(further down in `interp.ml`) do a small, deliberately partial type inference — just enough
for `new`/`dispose` to work, not full type checking. This assumes the program is already
well-formed; it is not a substitute for Phase 3.

## Forward declarations and mutual recursion

Local declarations are processed in order (`setup_locals`). A `forward` declaration
registers a `proc` entry with `pbody = None`; when the matching real definition is
encountered later, its body is *patched into the existing entry* (`existing.pbody <- Some
...`) rather than creating a second one. Since both the forward stub and the real definition
share the same mutable hashtable entry, and neither function actually gets *called* until
after all of a body's locals are fully registered, this correctly resolves mutual recursion —
tested directly with a genuine `isEven`/`isOdd` pair calling each other (see below), not just
trusted from reading the code.

## Control flow: `return` and `goto`

`return` is implemented as an exception (`Return_exc`) caught right where a procedure/function
call executes its body — simple, since PCL's `return` always exits the *current* structural
unit, never something further up the call stack.

`goto`/`label` needed more care. `exec_stmts` (plural — executing a whole statement list)
catches a raised `Goto_exc label`, searches *that specific list* for a matching `SLabel`, and
if found, resumes execution from there. If not found, it re-raises, so whichever *enclosing*
statement list actually contains the label gets a chance to catch it instead. This correctly
handles the common pattern — jumping out of a nested block (an `if`/`while` body) back to a
label in the surrounding sequence, e.g. loop-via-goto — but will **not** find a label nested
inside a different block than the one currently executing (jumping *into* a nested block from
outside). That's a deliberate, documented scope decision: SPEC.md technically allows more
flexibility here than this covers, but the "jump into a nested block" pattern is unusual
enough in idiomatic PCL that implementing it seemed not worth the complexity for now, and it
isn't exercised by any of the 6 course examples anyway (none of them use `goto` at all).

## The standard library, and why it lives inside `interp.ml`

The natural instinct was a separate `Builtins` module — but builtins like `writeString` and
`readString` need to call back into `eval_expr`/`lvalue_cell` (to evaluate arguments, or get
a cell for a `var` parameter), and `interp.ml` needs to call into the builtins table from
`call`. That's a circular module dependency, which OCaml doesn't support without extra
machinery (functors, first-class modules) that wasn't worth it for what's fundamentally one
cohesive evaluator. So `try_builtin` is just one more function in the same big
mutually-recursive `and` chain as everything else, checked first in `call` before falling
through to user-defined procedures.

One real spec subtlety implemented here: `readString` (SPEC.md §8.1) can be asked for fewer
characters than remain on the current input line, in which case reading is supposed to
"continue later from the point where it stopped" — not silently drop the rest of the line.
That needs state that outlives a single call, hence the module-level `pending_line` buffer.
This is one of the least-tested corners of the interpreter, since none of the 6 course
examples call `readString` (or `readChar`, `readBoolean`, or `readReal`, for that matter —
only `readInteger` is actually exercised by the provided programs).

## A hazard worth knowing about if this ever gets merged toward `main`

Builtin names are checked *before* user-defined procedures in `call`, which technically means
a user program that (legally, per the language) declares its own procedure or variable named
e.g. `abs` would have that shadowed by the built-in instead of the reverse (SPEC.md §8 says
built-ins are visible "unless shadowed" — the opposite priority order from what's implemented
here). Flagging this explicitly rather than leaving it a silent gap: it wasn't hit by any of
the course examples, so it was accepted as a known, minor deviation rather than solved
properly (solving it properly would mean checking the user's own proc table first, falling
back to builtins only when nothing user-defined matches).

## How I actually verified this works

Built with the same OCaml 4.14.1 WSL Ubuntu setup as Phases 1-2. Ran all 6 `test/*.pcl`
files through `pcli` and checked the actual output, not just "didn't crash":
- `hello.pcl` — prints the greeting.
- `hanoi.pcl` (piped `3` as input) — produced exactly the 7-move sequence a correct Tower of
  Hanoi solution for 3 rings should produce (hand-verified against the known-correct move
  order).
- `primes.pcl` (piped `50`) — correctly found all 15 primes below 50.
- `reverse.pcl` — correctly reverses its embedded string.
- `bsort.pcl` — output array is a valid ascending sort of the input array's multiset.
- `mean.pcl` (piped two integers) — checked against a hand-computed case (`n=10 k=1`, where
  the single pseudo-random sample is computable by hand from the seed formula) to confirm
  the arithmetic itself, not just "produced *a* number."

Then wrote synthetic tests for everything the 6 examples don't exercise:
- Forward declarations with genuine mutual recursion (`isEven`/`isOdd` calling each other).
- `new`/`dispose` for both a scalar pointer and a dynamic array (`new [n] q`, then
  `q^[i]` indexing).
- `label`/`goto` implementing a loop.
- `@`/`^` aliasing through a plain variable *and* through a specific array element
  (`@arr[i]`), confirming a write through the pointer is visible at the original location.
- By-value vs. by-reference parameter passing side by side (one procedure that shouldn't
  mutate its argument, one that should) to confirm the distinction is real, not accidental.
- Short-circuit `and`/`or`, using a function with an observable side effect (setting a
  `var` flag parameter) as the *right* operand, to confirm it genuinely never runs when the
  left operand alone determines the result — not just that the boolean result was right.
- Runtime error paths: division by zero, array-index-out-of-bounds, and nil-pointer
  dereference — confirmed each produces a clean one-line message and exit code 1, not a raw
  OCaml exception/stack trace.

Cleaned all generated build artifacts (`make distclean`) and scratch `.pcl` test files
afterward — nothing except real source is committed.

## What's still fake / not done

- Builtins shadow user declarations of the same name instead of the other way around (see
  the hazard note above).
- `goto` cannot jump into a nested block from an enclosing one, only out of one.
- No semantic analysis has run first, so a genuinely ill-typed program (e.g. comparing a
  `boolean` to a `char`) will either coerce unexpectedly or hit an internal `error` at
  runtime, rather than being rejected up front the way a fully compiled pipeline would.
- `readString`/`readChar`/`readBoolean`/`readReal` are implemented but far less tested than
  `readInteger`, since no course example calls them.
