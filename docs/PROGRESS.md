# Compiler Progress

Track completion of each compiler phase and major milestones. Everything about the PCL
*language* (lexical rules, grammar, types, semantics, stdlib, CLI/build contract) is in
[SPEC.md](SPEC.md); our own toolchain/pipeline decisions are in
[IMPLEMENTATION.md](IMPLEMENTATION.md) — don't duplicate either here. This file is about
*status*: progress per phase, cross-cutting deliverables (CLI/build), known issues, and
TODOs.

## Phase 1: Lexical Analysis (0.5 units)

**Status:** Done (`src/lexer.mll`, `src/parser.mly` token declarations, `src/main.ml` as a
temporary token-printing driver). Built and tested via OCaml 4.14.1 in WSL Ubuntu — verified
all 6 `test/*.pcl` files tokenize cleanly to `EOF`, plus manual checks of non-nesting
comments, escape sequences (incl. `\0`), real-number exponents, case-sensitive
keywords-vs-identifiers, multi-char operators (`<>` `>=` `<=`), and error paths (invalid
character, unterminated string, unterminated comment — all report line number and exit 1).
Also fixed a real Makefile bug found in the process: no rule built `parser.cmi` from
`parser.mli` before it was needed, so nothing downstream of the parser could compile.

**Description:** 
Tokenize PCL source code into lexical units (keywords, identifiers, constants, operators, delimiters).

**Deliverables:**
- [x] Implement lexer using ocamllex (lexer.mll)
- [x] Recognize all token types:
  - [x] Keywords (and, array, begin, boolean, etc.)
  - [x] Identifiers
  - [x] Integer constants
  - [x] Real constants
  - [x] Character constants
  - [x] String literals
  - [x] Operators (=, >, <, :=, etc.)
  - [x] Delimiters ((, ), [, ], ;, :, etc.)
- [x] Handle comments `(* ... *)`
- [x] Handle whitespace correctly
- [x] Test with simple examples

**Test Files:**
- `hello.pcl` — simple string output

**Notes:**
- Case-sensitive identifiers
- String literals cannot span multiple lines
- Comments cannot be nested

---

## Phase 2: Syntactic Analysis (1.0 units)

**Status:** Done (`src/ast.ml`, real grammar in `src/parser.mly`, `src/main.ml` rewritten to
parse-and-print-the-AST). Built and tested via OCaml 4.14.1 in WSL Ubuntu — all 6
`test/*.pcl` files parse successfully; manually verified operator precedence/associativity
(`2 + 3 * 4`, explicit parens, array indexing binding tightest), dangling-else resolution
(nested `if`/`if`/`else` correctly attaches `else` to the inner `if`), forward declarations
with mutual recursion, both forms of `new`/`dispose`, `label`/`goto`, and syntax-error
reporting (line number + exit 1). One design decision made along the way: `lvalue` is a
grammar rule distinct from the general `expr` rule (matching SPEC.md §5's l-value/r-value
split) so invalid assignment targets are rejected at parse time, not deferred to semantic
analysis — except `@`'s operand, which had to be loosened to general `expr` to avoid an
unavoidable LALR(1) reduce/reduce conflict with the `expr : lvalue` passthrough; "the
operand of `@` must be an lvalue" is therefore one check Phase 3 has to make instead (see
the comment above the `lvalue` rule in `parser.mly`).

**Description:**
Parse token stream into an Abstract Syntax Tree (AST) according to PCL grammar.

**Deliverables:**
- [x] Define OCaml AST types:
  - [x] Expression types (IntConst, BinOp, FuncCall, etc.)
  - [x] Statement types (Assign, If, While, Block, etc.)
  - [x] Type definition types
  - [x] Program/body structures
- [x] Implement parser using ocamlyacc (parser.mly)
- [x] Handle operator precedence correctly (Table 2)
- [x] Handle operator associativity (left-associative by default)
- [x] Parse all statement types
- [x] Parse all expression types
- [x] Parse procedure/function declarations
- [x] Handle forward declarations for recursive functions
- [x] Generate AST from valid PCL programs
- [x] Produce useful error messages for syntax errors

**Test Files:**
- `hello.pcl`
- `primes.pcl` — functions, loops
- `hanoi.pcl` — recursion, string parameters

**Notes:**
- Operator precedence/associativity: [SPEC.md §2.3](SPEC.md#23-operator-precedence-and-associativity)
- If/then/else has shift/reduce ambiguity (prefer longest match) — resolved via
  `%nonassoc THEN` / `%nonassoc ELSE` precedence, not left as an unresolved conflict
- `and`/`or` bind *tighter* than relational operators in PCL (a real Pascal quirk, unlike
  C) — combining a comparison with `and`/`or` requires explicit parens around the
  comparison, e.g. `(a < b) and (c < d)`, which is exactly how the course's own test files
  (`primes.pcl`) already write it
- Extra verification beyond parsing alone: a tree-walking interpreter was built on a separate
  `interpreter` branch (not merged into `main` — it isn't part of the graded pipeline)
  specifically to run the Phase 1 lexer and Phase 2 parser's output end-to-end and check
  real program behavior, not just "it parsed." All 6 `test/*.pcl` files ran successfully and
  produced correct, independently-verified output (e.g. `hanoi.pcl`'s move sequence matched
  a known-correct solution, `primes.pcl`'s prime count was correct) — a stronger check than
  Phase 1/2 testing alone gave, since a wrong token or a misparsed precedence would likely
  have shown up as wrong program behavior there.

---

## Phase 3: Semantic Analysis (2.0 units)

**Status:** Done (`src/symtab.ml`, `src/semantic.ml`, plus line-number tracking retrofitted
into `src/ast.ml`/`src/parser.mly`/`src/lexer.mll` since the AST previously carried none).
Built and tested via OCaml 4.14.1 in WSL Ubuntu — all 6 `test/*.pcl` files type-check cleanly
(exit 0); scratch test files (written, verified, then deleted — not left in `test/`, which
SPEC.md §10 reserves for the course's mirrored examples) confirmed multi-error collection (7
distinct errors from one file, all correctly reported together), duplicate declarations,
unfulfilled `forward` declarations, label declared-but-undefined and defined-twice, undeclared
`goto` targets, mutual recursion via `forward`, both directions of `^array[n] of t` /
`^array of t` pointer widening (correct direction accepted, wrong direction rejected), and
`array [0] of t` / array-returning-function rejection. See `guide/SEMANTIC_WALKTHROUGH.md` for
the full walkthrough.

Two design decisions were asked of the user before implementing, per CLAUDE.md/SPEC.md §4's
explicit "ask first" note:
1. Symbol table: a mutable stack of hash tables (one per open scope), not a persistent/
   functional environment.
2. Symbol table entries carry only what Phase 3 itself needs (type, by-ref flag, forward/
   defined flag) — no storage/offset fields reserved for Phase 4/6 ahead of time.

A third question surfaced while reading the existing code (not originally about the symbol
table): the AST had no line numbers anywhere, so semantic errors would have had nowhere to
point. Asked whether to retrofit line tracking now; the answer was yes — `Ast.stmt` became a
`{ sline; sdesc }` record (statement-granularity, not per-expression), `header` gained an
`hline`, and `LVar`'s groups became `var_group` records with their own `vline`. Getting real
line numbers out of `ocamlyacc` needed one small fix in the already-"done" `lexer.mll`: it
tracked its own line counter in a plain `ref` but never called `Lexing.new_line`, which is what
`Parsing.symbol_start_pos()`'s line-number field actually depends on.

**Description:**
Validate semantic correctness: type checking, scope rules, symbol table management, declaration validation.

**Deliverables:**
- [x] Design + implement symbol table — data structure and tracked fields are **not
  specified by the course** ([SPEC.md §4](SPEC.md#4-program-structure)); ask the user
  before settling on an approach
  - [x] Support nested scopes (enter/exit scope)
  - [x] Lookup with scope traversal
- [x] Type checking:
  - [x] Validate variable declarations (complete types only)
  - [x] Check assignment compatibility
  - [x] Validate operator operand types
  - [x] Check function return types
  - [x] Handle type coercion (integer → real)
  - [x] Handle array type compatibility
  - [x] Handle pointer type compatibility
- [x] Function/procedure validation:
  - [x] Check parameter count and types
  - [x] Validate formal vs actual parameter compatibility
  - [x] Check pass-by-value vs pass-by-reference
  - [x] Validate forward declarations
  - [x] Check for undefined functions
- [x] Variable validation:
  - [x] Detect undefined variable usage
  - [x] Detect duplicate declarations in same scope
  - [x] Validate array bounds (known size)
  - [x] Check pointer dereference
- [x] Scope validation:
  - [x] Enforce Pascal scoping rules
  - [x] Allow shadowing in nested scopes
  - [x] Validate label declarations

**Test Files:**
- All previous files
- `reverse.pcl` — arrays, string manipulation
- `bsort.pcl` — array operations

**Notes:**
- Single-pass semantic analysis preferred
- Collect errors but continue analysis (report all errors at once)
- Assignment compatibility / coercion rules: [SPEC.md §7](SPEC.md#7-type-coercion--assignment-compatibility)
- "Validate array bounds (known size)" was implemented as a compile-time check that fixed
  array sizes are positive integer constants — not runtime index-bound checking (SPEC.md
  §5.1's "index must not exceed the array's real bound" is a dynamic property of a general
  index expression, which is a codegen-time concern, not a Phase 3 one).
- `result` used outside a function body, and a bare procedure name used where a value is
  expected, are both reported as ordinary type errors rather than special-cased.

---

## Phase 4: Intermediate Code Generation (2.0 units)

**Status:** Not started

**Description:**
Generate Three-Address Code (TAC) from the validated AST.

**Deliverables:**
- [ ] Design intermediate representation (TAC format)
  - [ ] Define instruction format (op, arg1, arg2, result)
  - [ ] Define temporary variable naming
  - [ ] Define label naming for jumps
- [ ] Implement TAC generation:
  - [ ] Expressions → TAC (handle operator precedence)
  - [ ] Assignments → TAC
  - [ ] Control flow (if/while/goto) → labels + conditional jumps
  - [ ] Function calls → TAC (argument evaluation, call instruction)
  - [ ] Function/procedure definitions → TAC blocks
  - [ ] Array access → TAC (index calculation)
  - [ ] Pointer operations (new, dispose, dereference) → TAC
- [ ] Generate intermediate code file (.imm)
- [ ] Implement basic optimizations (optional, for +0.5 bonus):
  - [ ] Constant folding
  - [ ] Dead code elimination
  - [ ] Common subexpression elimination

**Test Files:**
- All previous files
- `mean.pcl` — arithmetic, temporary variables

**Notes:**
- Required TAC output format: [SPEC.md §9](SPEC.md#9-cli--build--output-requirements) (`printf`-style quadruples)
- Temps are typically `t0, t1, t2, ...`
- Must handle nested expressions correctly

---

## Phase 5: Code Optimization (0.5 units - Bonus)

**Status:** Not started

**Description:**
Optimize intermediate code for better performance.

**Deliverables (choose at least one):**
- [ ] Constant folding (pre-compute constant expressions)
- [ ] Dead code elimination (remove unused assignments)
- [ ] Common subexpression elimination (avoid redundant computations)
- [ ] Peephole optimization (small sequence improvements)
- [ ] Loop optimizations (invariant hoisting, strength reduction)

**Impact:** +0.5 bonus units

---

## Phase 6: Final Code Generation (0.5 units - Bonus)

**Status:** Not started

**Description:**
Generate x86-64 assembly code from intermediate code (or LLVM IR).

**Deliverables:**
- [ ] Choose code generation strategy:
  - [ ] Option A: Generate x86-64 assembly directly from TAC
  - [ ] Option B: Use LLVM backend (easier, but no bonus)
- [ ] Implement (if not using LLVM):
  - [ ] Register allocation
  - [ ] Stack frame management (prologue/epilogue)
  - [ ] Function call conventions (x86-64 ABI)
  - [ ] Memory addressing for arrays/pointers
  - [ ] Label and jump instructions
  - [ ] Built-in function calls (writeInteger, readInteger, etc.)
- [ ] Generate assembly file (.asm)
- [ ] Compile to executable using `gcc`/`as`/`ld`

**Impact:** +0.5 bonus units (if not using LLVM)

**Notes:**
- x86-64 calling convention: rdi, rsi, rdx, rcx, r8, r9 for args
- Return value in rax
- Must preserve caller-saved registers
- Required final-code output format: [SPEC.md §9](SPEC.md#9-cli--build--output-requirements) (tab-indented `label: instr arg1, arg2`)

---

## CLI & Build Contract

Full detail: [SPEC.md §9](SPEC.md#9-cli--build--output-requirements). Not tied to one phase
above — argument parsing can be scaffolded early, but `-i` only works once Phase 4 exists
and `-f`/default `.asm` output only work once Phase 6 exists.

**Deliverables:**
- [ ] `pclc <file>` — default mode, writes `<basename>.imm` and `<basename>.asm` next to the source
- [ ] `-o file` — custom executable output path (default `./a.out`)
- [ ] `-O` — optimization flag (optional, accepted even before Phase 5 exists)
- [ ] `-f` — read source from stdin, write final code to stdout
- [ ] `-i` — read source from stdin, write intermediate code to stdout
- [ ] `pclc` exit code: 0 on success, non-zero on any compile failure
- [ ] Generated executable exit code: 0 on successful run (verify: `./a.out && ./a.out` on `hello.pcl` prints the greeting twice)
- [ ] `make` — builds `pclc`
- [ ] `make clean` — removes generated files (flex/bison output, `.o`), keeps `pclc`
- [ ] `make distclean` — `make clean` + removes `pclc`

---

## Known Issues

- `README.md` has stale/inaccurate setup instructions (references flex/bison, which this
  project doesn't use — it's ocamllex/ocamlyacc per IMPLEMENTATION.md). The build actually
  works now (Phases 1-2 done, `make && ./pclc test/hello.pcl` runs), so this is no longer
  low priority — the PDF (§4) requires README to have accurate install/usage instructions
  since that's what the instructor reads. Worth fixing for real soon, not just patching the
  current placeholder.

## TODOs

- Optimize tail recursion
- Better error messages

---

## Testing Progress

| Example | Status | Notes |
|---------|--------|-------|
| hello.pcl | Not started | Basic I/O |
| primes.pcl | Not started | Functions, loops, logic |
| hanoi.pcl | Not started | Recursion, strings |
| reverse.pcl | Not started | Arrays, strings |
| bsort.pcl | Not started | Array manipulation |
| mean.pcl | Not started | Reals, arithmetic |

---

## Overall Progress

**Current Phase:** Phase 1-3 done, Phase 4 (Intermediate Code Generation) next

**Blockers:** None currently.

**Next Steps:**
1. Design the TAC (three-address code) instruction format (op, arg1, arg2, result) — not
   specified by the course beyond the output format in SPEC.md §9; our own choice per
   IMPLEMENTATION.md.
2. Implement TAC generation from the now-checked AST (Phase 4).
3. Wire `main.ml` into the actual CLI contract (SPEC.md §9) once codegen exists — it currently
   still just parses, type-checks, and pretty-prints the AST on success.
