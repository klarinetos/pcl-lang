# Semantic Analysis Walkthrough

Explainer for what got built in Phase 3, step by step. Same deal as `guide/LEXER_WALKTHROUGH.md`
and `guide/PARSER_WALKTHROUGH.md` — a one-time reference for understanding the code, not part
of Claude's working context (that's SPEC.md/IMPLEMENTATION.md/PROGRESS.md), and it won't stay
in sync automatically if semantic.ml changes later.

## What semantic analysis actually does

The parser (Phase 2) only checks *shape* — is this a syntactically valid PCL program? It has
no idea whether `x` was ever declared, whether `x := "hello"` makes sense, or whether a
`goto` targets a real label. Semantic analysis walks the AST a second time and checks
*meaning*: every name resolves to something, every operation is applied to operands of a
legal type, every declaration is well-formed, every `forward` gets completed, every declared
label gets defined exactly once. Per IMPLEMENTATION.md this is single-pass and, per
PROGRESS.md, collects every error it finds rather than stopping at the first — so one bad file
can report five real problems in one run instead of five separate runs.

## Files involved

- **`src/symtab.ml`** — new. The symbol table: a mutable stack of hash tables, one per open
  lexical scope.
- **`src/semantic.ml`** — new. Was a placeholder since Phase 1; now the actual type checker,
  built on top of `Symtab`.
- **`src/ast.ml`**, **`src/parser.mly`**, **`src/lexer.mll`** — all touched, for one reason:
  line tracking. More below, since it's the one piece of this phase that reaches backward into
  already-"done" Phase 1/2 files.
- **`src/main.ml`** — the driver now runs `Semantic.check_program` after parsing; on any
  errors it prints each as `file: line N: message`, sorted by line, and exits 1 before ever
  reaching codegen (which doesn't exist yet anyway).

## Two decisions asked of the user before writing any of this

CLAUDE.md and SPEC.md §4 flag the symbol table's design as something the course doesn't
specify — deliberately left for us to decide, with an explicit instruction not to pick
unilaterally. Asked, and got:

1. **A mutable stack of hash tables** (as opposed to an immutable environment threaded through
   every recursive call) — the standard imperative approach, and a natural fit for the
   single-pass design already committed to in IMPLEMENTATION.md.
2. **Minimal entry fields** — each symbol table entry carries only what Phase 3 itself needs
   to check (a type, a by-ref flag, a forward/defined flag). No storage offsets or anything
   codegen-shaped; those get added in Phase 4/6 when something actually reads them.

A third thing surfaced while reading the existing code, not originally part of the symbol
table question: **`ast.ml` had no line numbers on anything.** The lexer and parser both report
`line N: ...` on their own errors, but that information was thrown away the moment parsing
finished — a semantic error like "undefined variable" would have had nowhere to point. Asked
whether to retrofit line tracking onto the AST now (touching the already-"done" `ast.ml` and
`parser.mly`) or skip it; the answer was to add it now, which is why this phase's diff isn't
contained to new files.

## How line numbers actually got added

The obvious approach — give every single AST node its own line — would have meant wrapping
`expr` in a location record too, doubling the size of essentially every pattern match in
`main.ml`'s printer and `semantic.ml`'s checker for very little benefit (an error inside a
multi-line `if` condition is still useful to report at the `if`'s own line). So line tracking
landed at a coarser grain: **statements, variable-declaration groups, and subprogram headers**
each carry a `line: int` field; a plain `expr` still doesn't. Any error found while checking an
expression is blamed on the line of the statement (or declaration) it's nested inside.

Concretely, `Ast.stmt` changed from a bare variant type into a record wrapping one:
```ocaml
type stmt = { sline : int; sdesc : stmt_desc }
and stmt_desc = SEmpty | SAssign of expr * expr | ... (* unchanged otherwise *)
```
and similarly `header` gained an `hline` field, and `LVar`'s `(names, type)` pairs became a
`var_group` record (`{ vline; vnames; vtyp }`) so a duplicate-declaration or bad-array-size
error can point at the specific `name, name : type;` line rather than the whole `var` block.

Getting the actual line number at parse time turned out not to need any manual bookkeeping in
`parser.mly` beyond one helper. `ocamlyacc` (like `menhir`) automatically tracks the source
position of every token it shifts, exposed through `Parsing.symbol_start_pos ()` — but only the
*character offset* half of that position updates for free. The *line number* half
(`pos_lnum`) only advances when the lexer explicitly calls `Lexing.new_line lexbuf`, which
`lexer.mll` wasn't doing (it tracked its own line number in a plain `ref` for its own error
messages instead). Adding one call —
```ocaml
| '\n'    { incr line; Lexing.new_line lexbuf; token lexbuf }
```
(and the equivalent inside the comment-skipping rule) — was enough to make `Parsing.symbol_start_pos ()`
start returning real line numbers, with no per-rule marker actions needed. Every grammar
action that now stamps a line just calls a one-line helper:
```ocaml
let curline () = (Parsing.symbol_start_pos ()).Lexing.pos_lnum
```

## The symbol table (`src/symtab.ml`)

```ocaml
type entry =
  | EVar of Ast.typ
  | EParam of bool * Ast.typ            (* by_ref, type *)
  | ESub of Ast.header * bool ref       (* header; ref flips true once defined *)

type frame = {
  vars : (string, entry) Hashtbl.t;
  labels : (string, int * bool ref) Hashtbl.t;   (* declared-line, defined?  *)
}

type t = frame list ref
```

One `frame` = one open structural unit (the main program, or a procedure/function currently
being checked). `push_scope`/`pop_scope` enter and leave one; `lookup` walks the frame list
innermost-to-outermost, which is what gives Pascal-style shadowing for free — a nested
subprogram redeclaring a name from an enclosing one just adds a second `Hashtbl` entry that
shadows the first for as long as its own frame is on top of the stack.

**Labels got their own table inside the frame, deliberately not folded into the general
`entry` type.** SPEC.md §6 restricts `goto` to targets in the *same* structural unit — never an
enclosing one — which is the opposite of how every other name resolves (variables and
subprograms are visible from nested scopes; labels explicitly aren't reachable that way at
all). Rather than teach the general lookup path a special "don't walk outward for this one
case" rule, `check_goto`/`define_label` just look at `Symtab.current_labels`, i.e. only the
innermost frame, directly — the restriction falls out of *which table gets consulted*, not an
extra check.

## Walking through what `semantic.ml` actually checks

**Type well-formedness (SPEC.md §3)** — `well_formed`/`is_complete` are mutually recursive
because a pointer's own size (8 bytes, always) doesn't depend on whether what it points to is
complete, but forming *any* array (sized or not) requires its element type to be complete:
```ocaml
let rec well_formed t = match t with
  | TInteger | TReal | TBoolean | TChar -> true
  | TPointer inner -> well_formed inner
  | TArray (_, elem) -> well_formed elem && is_complete elem
and is_complete t = match t with
  | TInteger | TReal | TBoolean | TChar -> true
  | TPointer _ -> well_formed t
  | TArray (None, _) -> false
  | TArray (Some _, _) -> well_formed t
```
This is why `^array of real` (SPEC.md §4's `f3` example return type) type-checks fine even
though `array of real` alone never would as a variable's declared type — a pointer only needs
its target to be *well-formed*, not complete. Positive array-size checking (`array [0] of t` is
a syntactically valid but semantically illegal type) is a separate recursive walk
(`check_positive_sizes`), since it's an orthogonal concern from completeness — an array can be
simultaneously "complete" (sized) and still have an illegal size.

**`nil`'s "no unique type" (SPEC.md §5.2)** gets represented with a small internal type
`sem_typ = Typ of Ast.typ | Nil`, used as the return type of `type_of_expr` everywhere instead
of a made-up placeholder `Ast.typ`. Every consumer that cares (assignment, `=`/`<>`, by-value
argument passing) explicitly matches the `Nil` case and treats it as compatible with any
pointer type; everywhere else (arithmetic, array indexing, ...) `Nil` just falls into the "not
valid here" error case alongside any other type mismatch.

**The one place a semantic check substitutes for a grammar restriction**: `@`'s operand.
`parser.mly`'s own comment (and `guide/PARSER_WALKTHROUGH.md`) already flags that `@` had to
accept a general `expr` instead of `lvalue` to dodge an LALR(1) reduce/reduce conflict, leaving
"the operand of `@` must actually be an l-value" as Phase 3's job. `is_lvalue` is a flat
structural check —
```ocaml
let is_lvalue = function
  | EId _ | EResult | EString _ | EIndex _ | EDeref _ -> true
  | _ -> false
```
— and it's the *only* spot in `semantic.ml` that needs this kind of check, because every other
l-value-required position (`:=`'s left side, `new`/`dispose`'s target, a `var` argument) is
already syntactically restricted to the `lvalue` grammar rule, so the AST literally cannot
contain anything else there.

**Declarations are processed in one pass over `body.locals`, in source order**, which is what
makes recursion and `forward` work correctly without a separate pre-pass:
- A `procedure`/`function` gets declared into its *enclosing* scope **before** its own body is
  checked — so a subprogram calling itself (like `hanoi` calling `hanoi` in `test/hanoi.pcl`)
  resolves fine with no `forward` needed; `forward` is only required for *mutual* recursion,
  where the second name genuinely doesn't exist yet at the point the first one's body is
  checked.
- `forward procedure p (...)` declares `p` as an `ESub` with its `defined` flag set to `false`.
  When a later `procedure p (...)` with a matching signature appears in the same scope, that
  flips the flag to `true` instead of erroring as a duplicate declaration; a signature that
  doesn't match, or a `p` with no preceding forward at all colliding with an existing name,
  both report a real error. At the end of each unit's own declarations, any `ESub` still
  sitting at `defined = false` means a `forward` that was never completed — reported once, at
  the `forward` line.
- Labels follow the identical declared-then-defined-once shape, just in their own table:
  `label l;` declares `l` with `defined = false`; the first `l: stmt` flips it to `true` (a
  second one is a "defined more than once" error); anything still `false` when the unit's block
  finishes is a "declared but never defined" error.

**Formal parameters and a subprogram's own local declarations share one scope** (one
`push_scope` call, in `check_subprogram`, before either gets declared) — matching real Pascal,
where you can't have a parameter and a local variable with the same name, and both are visible
to each other for the entire body. A `var`-mode formal accepts an incomplete type (`array of
char`, the shape every `write*`/`read*` string parameter in SPEC.md §8 uses); a by-value formal
is flatly rejected if it's an array type *at all* (SPEC.md §4: "cannot be an array type" — no
exception for sized arrays, unlike the general completeness rule elsewhere).

## How I actually verified this works

Built with OCaml 4.14.1 in WSL Ubuntu (same environment as Phases 1-2) and:
- Ran all 6 `test/*.pcl` files through it — all type-check cleanly (exit 0), including the
  cases that most exercise this phase: `hanoi.pcl`'s direct self-recursion and by-reference
  `array of char` parameters, `primes.pcl`'s `result :=` assignments and early `return`,
  `bsort.pcl`'s nested `procedure swap` sharing its enclosing scope's array parameter, and
  `mean.pcl`/`reverse.pcl`'s integer→real coercion and string-literal l-value indexing.
- Wrote and ran (then deleted — these weren't left in `test/`, which SPEC.md §10 reserves for
  the course's own mirrored examples) scratch `.pcl` files targeting each error category, all
  confirming the errors fire on the right line *and* don't stop analysis early:
  - Type errors: `boolean := integer`-shaped assignments, an undefined identifier, indexing a
    non-array, calling a stdlib procedure with a wrong-typed argument — one file with 7
    separate bad statements produced exactly 7 errors, each on its own correct line, in one
    run.
  - Scope/declaration errors: a duplicate `var` in the same scope, a `label` declared but never
    defined, a `forward` never completed, two non-forward procedures with the same name, a
    label defined twice, a `goto` to an undeclared label, an undefined identifier — 7 files'
    worth of distinct problems, again all correctly reported together.
  - Positive control cases, to make sure none of the above checks are simply overzealous:
    mutual recursion via `forward` (`isOdd`/`isEven` calling each other), both forms of `new`/
    `dispose`, `^array [n] of t` → `^array of t` pointer widening in the *correct* direction —
    all type-check with zero errors.
  - The negative mirror of that last case (`^array of t` → `^array [n] of t`, the direction
    SPEC.md §7 explicitly does *not* allow) and a `real → integer` narrowing assignment both
    correctly fail.
  - A formal parameter's name colliding with the subprogram's own local `var` — caught as a
    duplicate declaration, confirming formals and locals really do share one scope.
  - `array [0] of integer` and a function declared to return an array type — each rejected
    with a distinct, specific message, not lumped into a generic "invalid type" catch-all.

## What's still fake / not done

- No dead code or unreachable-statement analysis — SPEC.md doesn't ask for it, and it's not in
  PROGRESS.md's Phase 3 deliverable list.
- `src/main.ml` still just pretty-prints the AST on success; there's nothing downstream yet to
  hand the checked AST to. That's Phase 4 (intermediate code generation), next.
- The symbol table carries no storage/offset information on purpose — that was one of the two
  explicit design decisions going in, deferred to whichever of Phase 4/6 first needs it.
