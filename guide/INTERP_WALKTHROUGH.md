# Interpreter Walkthrough (Phase 3 verification)

Explainer for the PCL interpreter (`pcli`) on this branch, `interpreter-phase3`. Same deal as
the other walkthroughs — a one-time reference for understanding the code, not part of Claude's
working context, and not kept in sync automatically if the code changes later.

## This is the second interpreter — how it relates to the first

There are now two interpreter branches:

- **`interpreter-phase1-2`** (formerly just `interpreter`, renamed to make room for this one) —
  built to verify Phases 1-2 (lexer + parser), before semantic analysis existed. Runs the raw
  AST straight off the parser, on faith that it's well-formed.
- **`interpreter-phase3`** (this branch) — same interpreter design, ported to the Phase 3 AST
  shape (statements/headers/var-groups now carry line numbers) and, critically, **wired to run
  `Semantic.check_program` first**. That was explicitly called out as *not done* in the first
  interpreter's own walkthrough ("No semantic analysis has run first, so a genuinely ill-typed
  program ... will either coerce unexpectedly or hit an internal `error` at runtime, rather
  than being rejected up front"). Closing that gap is the entire point of this branch: it turns
  "the interpreter ran without crashing" into "the exact AST `pclc` would go on to compile —
  the one that already passed the real Phase 3 type checker — actually behaves correctly."

Both stay off `main`, same reasoning as before: neither is part of the graded pipeline
(SPEC.md §9's lex → parse → semantic-check → intermediate code → assembly), so neither should
show up in `pclc`'s own history as if it were.

## Files involved

- **`src/interp.ml`** — the interpreter itself, ported from `interpreter-phase1-2` with exactly
  three mechanical changes for the new AST (see below) and otherwise unchanged: value
  representation, environment, expression evaluation, statement execution, and the standard
  library are all the same design.
- **`src/interp_main.ml`** — the entry point, and the one file with a real behavioral change:
  parse, run `Semantic.check_program`, print and exit 1 on any errors (same error format as
  `pclc`'s own `main.ml`), and only call `Interp.run` if the program actually checked out.
- **`Makefile`** — `pcli` now links `symtab.cmx` and `semantic.cmx` too (previously it only
  needed `ast`/`parser`/`lexer`, since it didn't use semantic analysis at all).

## Porting `interp.ml` to the Phase 3 AST: three mechanical changes

Phase 3 added line-number tracking to the AST (see `guide/SEMANTIC_WALKTHROUGH.md`), which
changed the *shape* of three constructors the interpreter pattern-matches on. None of this
touched the interpreter's actual logic — only where a line number now sits alongside the data
it already had:

1. `stmt` became `{ sline : int; sdesc : stmt_desc }` instead of a bare variant, so every
   `match s with SAssign (...) -> ...` in `interp.ml` became `match s.sdesc with SAssign (...)
   -> ...`. `exec_stmts`'s label search (`find_label`) needed the same fix, matching on
   `arr.(i).sdesc` instead of `arr.(i)` directly.
2. `LVar`'s declaration groups became `var_group` records (`{ vline; vnames; vtyp }`) instead
   of bare `(names, typ)` tuples, so `setup_locals`'s `LVar` case now reads `g.vnames`/`g.vtyp`
   off the record.
3. `LLabel` gained a line number (`LLabel of int * string list`), so `setup_locals`'s
   (no-op — see below) label case became `LLabel (_, _) -> ()`.

Everything else — `header` gaining an `hline` field, for instance — didn't need any interpreter
changes at all, since the interpreter only ever reads `hdr.hname`/`hdr.hparams`/`hdr.hret` by
field name, and adding a field nobody was pattern-matching positionally on is invisible to
existing code.

## Why semantic-checking first actually matters here, concretely

It's not just a formality. Consider a program with `x := true` where `x : integer` — the first
interpreter, with no type checker in front of it, would hit whatever `coerce_to`/`eval_expr`
happen to do with a `VBool` where an `VInt` was expected (an internal `error "expected a
number"` or similar, at whatever point the mistyped value's misuse first has an observable
effect — not necessarily the assignment itself). This interpreter instead reports the real
problem, with the real line number, before executing a single statement:
```
$ ./pcli semantic_gate.pcl
semantic_gate.pcl: line 5: right-hand side is not assignment-compatible with the left-hand side
semantic_gate.pcl: line 6: undefined identifier 'undeclaredVar'
```
— note *both* errors, not just the first one hit at runtime; `Semantic.check_program`'s
single-pass, collect-everything design (`docs/IMPLEMENTATION.md`) means a badly broken program
gets a full report in one run here too, exactly like it does through `pclc` itself.

## What didn't need to change, and why

The interpreter's runtime environment (`env`, `value`, `cell`) is still a completely separate
thing from `Symtab`'s compile-time scope stack, on purpose — they answer different questions
("what live value does this name hold right now, during execution" vs. "is this name declared,
and with what static type, before we ever run anything") and always will, even now that both
exist side by side. Running semantic analysis first doesn't collapse that distinction; it just
means the interpreter's own `type_of_expr`/`type_of_lvalue` (a small, deliberately partial
runtime type lookup, only as much as `new`/`dispose` need — see the code comments) can now
genuinely assume the program is well-typed, instead of merely hoping so.

## How I actually verified this works

Built with the same OCaml 4.14.1 WSL Ubuntu setup as every previous phase. `make` now produces
both `pclc` and `pcli` cleanly, no warnings.

**All 6 `test/*.pcl` files through `pcli`, checking real output against hand-verified
expectations, not just exit codes:**
- `hello.pcl` — prints the greeting.
- `hanoi.pcl` (piped `3`) — the exact 7-move Tower-of-Hanoi sequence for 3 rings
  (left→right, left→middle, right→middle, left→right, middle→left, middle→right, left→right),
  matching the known-correct solution.
- `primes.pcl` (piped `50`) — correctly finds all 15 primes below 50 (2, 3, 5, 7, 11, ..., 47).
- `reverse.pcl` — its embedded string `"\n!dlrow olleH"` reverses to `"Hello world!\n"`,
  confirmed character-by-character, not just "looked right."
- `bsort.pcl` — output array is ascending and is exactly the same multiset as the (seeded
  pseudo-random) input array, checked element-by-element including the repeated values (two
  36s, two 7s, two 79s in this run).
- `mean.pcl` (`n=10 k=1`) — hand-computed from the seed recurrence (`seed := (65*137+221+0)
  mod 10 = 6`, one sample, mean = 6.0) and confirmed the interpreter prints exactly `6.`.

**Synthetic tests for everything the 6 examples don't exercise** (written to a scratch
directory, run, checked, then deleted — same convention as every previous phase; not left in
`test/`, which SPEC.md §10 reserves for the course's own mirrored examples):
- Mutual recursion via `forward` (`isEven`/`isOdd`, genuinely calling each other) — correct for
  `isEven(10) = true`, `isOdd(10) = false`, `isEven(7) = false`.
- `new`/`dispose` for both a scalar pointer and a dynamically-sized array (`new [5] q`, then
  `q^[i] := i*i` for each `i`, reading back `0 1 4 9 16`).
- `label`/`goto` implementing a counted loop (`0 1 2 3 4`).
- `@`/`^` aliasing through a plain variable *and* through a specific array element
  (`@arr[2]`), confirming a write through the pointer is visible back at the original storage —
  not just that the pointer held the right address.
- By-value vs. by-reference side by side: a value parameter's `+100` mutation is invisible to
  the caller (`a` stays `5`); a `var` parameter's is not (`b` becomes `105`).
- Short-circuit `and`/`or`, using a function with an observable side effect (setting a `var`
  boolean flag) as the operand that must *not* run — confirmed the flag stays `false` in both
  the `false and f(...)` and `true or f(...)` cases, i.e. `f` genuinely never executes, not
  just that the boolean result happened to be right regardless.
- Runtime error paths — division by zero, array-index-out-of-bounds, and nil-pointer
  dereference — each producing a clean one-line `runtime error: ...` message and exit code 1,
  no raw OCaml exception trace.
- The semantic-gating case above (an ill-typed assignment plus an undefined identifier in one
  file) — confirmed `pcli` reports both errors and never calls `Interp.run` at all, rather than
  attempting to execute a program that failed its type check.

## What's still fake / not done

Same residual gaps as `interpreter-phase1-2`, since none of this branch's changes touched
these:
- Builtins are still checked before user-defined procedures in `call`, the opposite priority
  order from SPEC.md §8's "visible ... unless shadowed." Not hit by any test here either.
- `goto` still cannot jump *into* a nested block from an enclosing one, only out of one.
- `readString`/`readChar`/`readBoolean`/`readReal` remain far less tested than `readInteger`,
  since no course example calls them and none of this round's synthetic tests happened to
  either.
