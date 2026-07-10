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

---

## Phase 3: Semantic Analysis (2.0 units)

**Status:** Not started

**Description:**
Validate semantic correctness: type checking, scope rules, symbol table management, declaration validation.

**Deliverables:**
- [ ] Design + implement symbol table — data structure and tracked fields are **not
  specified by the course** ([SPEC.md §4](SPEC.md#4-program-structure)); ask the user
  before settling on an approach
  - [ ] Support nested scopes (enter/exit scope)
  - [ ] Lookup with scope traversal
- [ ] Type checking:
  - [ ] Validate variable declarations (complete types only)
  - [ ] Check assignment compatibility
  - [ ] Validate operator operand types
  - [ ] Check function return types
  - [ ] Handle type coercion (integer → real)
  - [ ] Handle array type compatibility
  - [ ] Handle pointer type compatibility
- [ ] Function/procedure validation:
  - [ ] Check parameter count and types
  - [ ] Validate formal vs actual parameter compatibility
  - [ ] Check pass-by-value vs pass-by-reference
  - [ ] Validate forward declarations
  - [ ] Check for undefined functions
- [ ] Variable validation:
  - [ ] Detect undefined variable usage
  - [ ] Detect duplicate declarations in same scope
  - [ ] Validate array bounds (known size)
  - [ ] Check pointer dereference
- [ ] Scope validation:
  - [ ] Enforce Pascal scoping rules
  - [ ] Allow shadowing in nested scopes
  - [ ] Validate label declarations

**Test Files:**
- All previous files
- `reverse.pcl` — arrays, string manipulation
- `bsort.pcl` — array operations

**Notes:**
- Single-pass semantic analysis preferred
- Collect errors but continue analysis (report all errors at once)
- Assignment compatibility / coercion rules: [SPEC.md §7](SPEC.md#7-type-coercion--assignment-compatibility)

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

## Interpreter (side project, not a graded phase)

Beyond being useful on its own, this doubled as real-world verification that the Phase 1
lexer and Phase 2 parser actually work correctly on genuine PCL programs — running all 6
`test/*.pcl` files end-to-end and checking their *actual output* (not just "it parsed without
error") is a stronger check than anything Phase 1/2 testing did on their own, since a wrong
token or a misparsed precedence would very likely have shown up as wrong program behavior
here, not just a clean-looking parse tree.

**Status:** Done on the `interpreter` branch (not merged to `main`) — `src/interp.ml` +
`src/interp_main.ml`, a new `pcli` executable built alongside `pclc`. Runs the Phase 2 AST
directly: independent of semantic analysis and codegen, and independent of the
still-undecided symbol table design above (the interpreter's runtime environment serves a
different purpose — looking up live values during execution, not static type-checking).
Verified against all 6 `test/*.pcl` files with real output checking, not just exit codes
(e.g. `hanoi.pcl`'s move sequence hand-verified against the known-correct solution,
`primes.pcl`'s count cross-checked), plus synthetic tests for everything the course examples
don't exercise: forward declarations with genuine mutual recursion, `new`/`dispose` for
scalars and dynamic arrays, `label`/`goto`, address-of on a specific array element, by-value
vs. by-reference side by side, short-circuit `and`/`or`, lexical vs. dynamic scoping, and
three runtime error paths. Full writeup: `guide/INTERP_WALKTHROUGH.md`.

Also surfaced a real discrepancy in the course PDF itself while testing `mean.pcl`: the PDF
claims the printed mean should diverge further from the theoretical `(n-1)/2` as `k` grows,
but independently re-simulating the exact recurrence (outside the interpreter, as a
cross-check) shows the opposite — it converges *closer* to the theoretical value as `k`
increases. Not an interpreter bug; flagged as an open question about the PDF's own claim,
not resolved.

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

**Current Phase:** Phase 1-2 done, Phase 3 (Semantic Analysis) next

**Blockers:** Symbol table design still needs deciding with the user before Phase 3 starts
(see `docs/SPEC.md` §4 note and `CLAUDE.md`)

**Next Steps:**
1. Decide symbol table design (ask the user first — not specified by the course)
2. Implement semantic analysis: type checking, scope rules, symbol table (Phase 3)
3. Wire `main.ml` into the actual CLI contract (SPEC.md §9) once semantic analysis + codegen exist
