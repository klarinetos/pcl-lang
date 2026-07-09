# Parser Walkthrough

Explainer for what got built in Phase 2, step by step. Same deal as
`guide/LEXER_WALKTHROUGH.md` — this is a one-time reference for understanding the code, not
part of Claude's working context (that's SPEC.md/IMPLEMENTATION.md/PROGRESS.md), and it
won't stay in sync automatically if the parser changes later.

## What a parser actually does

The lexer (Phase 1) turns raw text into a flat stream of tokens: `PROGRAM ID(hello) SEMI
BEGIN ...`. A flat stream doesn't capture *structure* — it doesn't know that everything
between `BEGIN` and `END` is one unit, or that `2 + 3 * 4` means "multiply 3 and 4 first,
then add 2." The parser's job is to consume that token stream according to PCL's grammar
(SPEC.md §2) and build a tree — the **abstract syntax tree (AST)** — that does capture that
structure, so later phases can walk the tree instead of re-deriving it from tokens every
time.

## Files involved

- **`src/ast.ml`** — plain OCaml type definitions for the tree: `typ`, `expr`, `stmt`,
  `header`, `local`, `body`, `program`. No logic, just shapes. New in Phase 2 — didn't exist
  in Phase 1.
- **`src/parser.mly`** — the real grammar now (Phase 1 left this as a single placeholder
  rule). Written in `ocamlyacc`'s DSL: token declarations, precedence directives, then
  grammar rules with OCaml actions that build `Ast` values as they reduce.
- **`src/main.ml`** — rewritten from "print every token" (Phase 1) to "parse the file, then
  pretty-print the resulting AST." Still not the real `pclc` CLI (SPEC.md §9) — that's still
  waiting on semantic analysis and codegen to exist.

## How `ocamlyacc` turns `parser.mly` into a parser

Like `ocamllex`, `ocamlyacc` reads a `.mly` file and generates real OCaml — but it produces
*two* files: `parser.ml` (the actual parsing logic) and `parser.mli` (its interface, mostly
just the token type and the entry-point function's signature). Both are gitignored and
regenerated every build.

A `.mly` file has four parts:
1. **Header** (`%{ ... %}`) — plain OCaml, spliced in verbatim. Here it's just `open Ast`, so
   the rules below can write `EInt 5` instead of `Ast.EInt 5`.
2. **Token declarations** (`%token ...`) — already existed from Phase 1, since the lexer
   needed to know what to return. Unchanged here.
3. **Precedence declarations** (`%nonassoc`, `%left`, ...) — new. Explained below.
4. **Grammar rules** (`name: alternative1 { action1 } | alternative2 { action2 } | ...`) —
   each nonterminal (a named grammar symbol, like `stmt` or `expr`) lists the token/nonterminal
   sequences that can produce it, and an OCaml expression to run when that alternative
   matches, building the AST node for it. `$1`, `$2`, etc. refer to the values already built
   for the 1st, 2nd, ... symbol in that alternative.

## Why the grammar needs precedence declarations at all

SPEC.md §2 says outright that PCL's grammar is *ambiguous* — the same input can be parsed
more than one structurally different way — and that the precedence/associativity table
(§2.3) is what resolves it. Concretely: given `2 + 3 * 4`, nothing in the bare grammar rule
`expr : expr PLUS expr | expr TIMES expr | ...` says whether to group it as `2 + (3 * 4)` or
`(2 + 3) * 4` — both are equally valid parses of that rule shape. The `%left`/`%nonassoc`
declarations tell `ocamlyacc` which grouping to prefer, and in which direction to associate
when the same operator repeats (`a - b - c` — left-to-right, i.e. `(a - b) - c`, matching
`%left`).

The declarations are listed **lowest to highest** precedence — each successive line binds
tighter than the one above it:
```
%nonassoc THEN
%nonassoc ELSE
%nonassoc EQ NE LT LE GT GE
%left PLUS MINUS OR
%left TIMES SLASH DIV MOD AND
%nonassoc NOT UMINUS UPLUS
%nonassoc CARET
%nonassoc AT
```
This mirrors SPEC.md §2.3's table directly, with two additions worth flagging:

- **`UMINUS`/`UPLUS`** aren't real tokens — the lexer never produces them. They're
  precedence-only placeholder names. `PLUS` and `MINUS` are used for *both* unary (`-x`) and
  binary (`x - y`) meanings, but those need *different* precedence (unary sign binds tighter
  than binary `+`/`-` per the table). Writing `MINUS expr %prec UMINUS` tells `ocamlyacc`
  "treat this specific rule's precedence as UMINUS's, not MINUS's default" — that's the
  entire purpose of `%prec`: overriding which precedence level applies to one specific rule.
- **`THEN`/`ELSE`** resolve the classic "dangling else" problem: for `if a then if b then x
  else y`, does `else y` belong to the inner `if b` or the outer `if a`? Both are
  grammatically valid readings of `if E then S | if E then S else S`. Giving `ELSE` higher
  precedence than `THEN` makes the parser prefer *shifting* (consuming more input, i.e.
  reading the `else` as part of the innermost still-open `if`) over *reducing* (closing off
  the outer `if` early) whenever both are possible — which is exactly "attach to the nearest
  unmatched if," the behavior SPEC.md §2.4 requires.

## Two ways this grammar deliberately relaxes the spec, and why

**`lvalue` is a real, separate grammar rule** — not folded into `expr` — specifically so
that things which can never be assignment targets (constants, function-call results,
arithmetic expressions) are rejected by the *parser*, not silently accepted and caught later.
E.g. `1 + 2 := x` is a syntax error here, exactly as SPEC.md §5.1 requires, because
`ASSIGN`'s left-hand side is grammatically required to be an `lvalue`, and `1 + 2` can only
ever reduce to `expr`, never to `lvalue`.

**Except for `@` (address-of).** The obvious way to write it — `AT lvalue` — turns out to be
grammatically *impossible* to build cleanly with `ocamlyacc`, which only implements
LALR(1) parsing (1 token of lookahead, with some states merged to keep the table small).
Building the grammar with `AT lvalue` produced 15 reduce/reduce conflicts, all in one state,
all boiling down to the same root cause: once the parser finishes recognizing an `lvalue`,
it can't tell — from that state alone — whether it arrived there via plain `expr : lvalue`
or via `expr : AT lvalue`, because both completions are simultaneously "pending" at that
exact point. (The other unary operators — `not`, unary `+`/`-` — don't have this problem,
because their operand is a general `expr`, which is already fully collapsed to one symbol
by the time the operator's rule tries to complete; `lvalue` isn't collapsed the same way,
since it's *also* independently reducible straight to `expr` via the passthrough rule.) The
fix: `@` takes a general `expr` too, exactly like the other unary operators, which means
`@(1+2)` now parses fine even though it's nonsense (you can't take the address of an
arithmetic result). That specific check — "the operand of `@` must actually be an lvalue" —
is deferred to Phase 3 (semantic analysis) instead. This is called out with a comment
directly above the `lvalue` rule in `parser.mly`, so it isn't a silent gap.

## Reading the reduce/reduce conflict, if you want to follow the reasoning yourself

`ocamlyacc -v` (already in the Makefile) writes `src/parser.output`, a full dump of every
parser state and every conflict, when you build. Searching it for `reduce/reduce` pointed
at one state (`state 93`) containing exactly these two items simultaneously "ready to fire":
```
expr : lvalue .        (rule 52)
expr : AT lvalue .      (rule 61)
```
Both trying to reduce on the same lookahead tokens (`AND`, `PLUS`, `EQ`, ...) is the literal
definition of a reduce/reduce conflict: two different rules both say "I'm done, reduce me,"
and the parser has no principled way to pick. This file is regenerated every build and
gitignored — it's a debugging tool, not something to hand-maintain.

## The one remaining (harmless) conflict

After the `@` fix, exactly one shift/reduce conflict remains, reported on `RPAREN`. It's
*not* the dangling-else case (that one is fully resolved by the `THEN`/`ELSE` precedence
and doesn't show up as a conflict at all) — it's about parenthesization: for input `(x)`,
should the parser complete `lvalue : LPAREN lvalue RPAREN` first and then pass that through
to `expr`, or complete `expr : LPAREN expr RPAREN` directly (where the inner `expr` already
came from `lvalue` via the passthrough)? Both paths produce the exact same result (just
`$2`, the unwrapped inner value) — so which one `ocamlyacc` picks by default (shift, per
standard yacc conflict-resolution rules) doesn't matter; the AST comes out identical either
way. Confirmed this is genuinely inert by testing parenthesized expressions directly (see
verification section below) rather than just asserting it from the state dump.

## A quirk worth knowing if you're used to C-family languages

SPEC.md's precedence table puts `and`/`or` (rows 6-7, multiplicative/additive tier)
*tighter* than relational operators (`= <> < <= > >=`, row 8, the loosest). This is real
ISO Pascal behavior, not a bug — but it's the opposite of C, Java, Python, etc., where
comparisons normally bind tighter than logical `and`/`or`. Concretely, it means writing
`a < b and c < d` in PCL does *not* mean "compare, then and" the way it would in C — and
since relational operators are also `%nonassoc` (can't chain: `a = b = c` is a hard parse
error, not "compare left-to-right"), an unparenthesized `a < b and c < d` actually fails to
parse at all (it reads as trying to chain two comparisons through `and`, hitting the same
nonassoc restriction). The fix, and what the course's own `primes.pcl` already does, is
parenthesize each comparison individually: `(a < b) and (c < d)`. Found this the hard way —
an early manual test (`not a = b and c < 10 or a > 0`) hit exactly this and correctly failed
to parse; that was the grammar working as intended, not a bug, once I worked out why.

## How I actually verified this works

Built with OCaml 4.14.1 in WSL Ubuntu (same environment as Phase 1) and:
- Watched the conflict count in `ocamlyacc -v`'s output go from "1 shift/reduce, 15
  reduce/reduce" down to "1 shift/reduce" after the `@` fix, then confirmed via
  `parser.output` that the remaining one is the harmless parenthesization case, not a
  disguised dangling-else or precedence bug.
- Ran all 6 `test/*.pcl` files through the new parser — all parse successfully (exit 0).
- Read the actual printed ASTs for `hello.pcl`, `hanoi.pcl`, and `primes.pcl` to confirm
  real structure, not just "didn't crash": nested procedures and recursive calls come out
  right, `n mod 2 = 0` correctly groups as `(n mod 2) = 0`, unary minus in `prime(-n)` comes
  out as a proper `EUnop` node, `else`-`if` chains nest correctly (each `else` attaches to
  its own `if`), and trailing semicolons before `end` correctly produce empty-statement
  nodes (SPEC.md's `stmt ::= ε | ...` alternative) rather than erroring.
- Wrote a synthetic test file exercising things none of the 6 provided examples actually
  use: `2 + 3 * 4` vs. `(2 + 3) * 4` (precedence vs. explicit grouping), array indexing
  binding tighter than surrounding arithmetic, dereference/address-of, and nested
  `if`/`if`/`else` (confirmed the dangling-else resolution directly, not just by reading the
  grammar).
- Wrote a second synthetic test file for `forward` declarations with real mutual recursion
  (`isEven`/`isOdd` calling each other), both forms of `new`/`dispose` (with and without
  `[]`), and `label`/`goto` — none of the 6 course example programs use any of these, so they
  were otherwise completely unverified.
- Verified syntax-error reporting on a deliberately broken file (`x := ;`) — reports the
  correct line number and exits 1, same error-handling shape as Phase 1's lexer errors.
- Cleaned all generated build artifacts afterward (`make distclean`) and deleted the
  scratch `.pcl` test files from `/tmp` — nothing except real source got committed.

## What's still fake / not done

- `src/main.ml`'s pretty-printer doesn't parenthesize nested prefix/postfix operators
  distinctly — `EDeref (EAddr (EId "b"))` (i.e. `(@b)^`) and a hypothetical `EAddr (EDeref
  (EId "b"))` (i.e. `@(b^)`) would print identically as `@b^`. The underlying AST is correct
  either way (verified by construction, not just by trusting the printer) — this is a
  cosmetic limitation of the temporary debug printer, not a parsing bug, and not worth fixing
  since this whole printer gets replaced once semantic analysis exists.
- Labels aren't required to be declared before use at the *grammar* level — `loop: stmt` and
  `goto loop` parse fine with no preceding `label loop;`. SPEC.md §4 (Program Structure)
  requires every label to be declared in the unit's `label` section; enforcing that is a
  Phase 3 (semantic analysis) job, same category as the `@`-operand-must-be-lvalue check.
- `src/main.ml` is still a parse-and-dump test harness, not the real `pclc` CLI.
