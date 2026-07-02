# Compiler Progress

Track completion of each compiler phase and major milestones. Everything about the PCL
*language* (lexical rules, grammar, types, semantics, stdlib, CLI/build contract) is in
[SPEC.md](SPEC.md); our own toolchain/pipeline decisions are in
[IMPLEMENTATION.md](IMPLEMENTATION.md) — don't duplicate either here. This file is about
*status*: progress per phase, cross-cutting deliverables (CLI/build), known issues, and
TODOs.

## Phase 1: Lexical Analysis (0.5 units)

**Status:** Not started

**Description:** 
Tokenize PCL source code into lexical units (keywords, identifiers, constants, operators, delimiters).

**Deliverables:**
- [ ] Implement lexer using ocamllex (lexer.mll)
- [ ] Recognize all token types:
  - [ ] Keywords (and, array, begin, boolean, etc.)
  - [ ] Identifiers
  - [ ] Integer constants
  - [ ] Real constants
  - [ ] Character constants
  - [ ] String literals
  - [ ] Operators (=, >, <, :=, etc.)
  - [ ] Delimiters ((, ), [, ], ;, :, etc.)
- [ ] Handle comments `(* ... *)`
- [ ] Handle whitespace correctly
- [ ] Test with simple examples

**Test Files:**
- `hello.pcl` — simple string output

**Notes:**
- Case-sensitive identifiers
- String literals cannot span multiple lines
- Comments cannot be nested

---

## Phase 2: Syntactic Analysis (1.0 units)

**Status:** Not started

**Description:**
Parse token stream into an Abstract Syntax Tree (AST) according to PCL grammar.

**Deliverables:**
- [ ] Define OCaml AST types:
  - [ ] Expression types (IntConst, BinOp, FuncCall, etc.)
  - [ ] Statement types (Assign, If, While, Block, etc.)
  - [ ] Type definition types
  - [ ] Program/body structures
- [ ] Implement parser using ocamlyacc (parser.mly)
- [ ] Handle operator precedence correctly (Table 2)
- [ ] Handle operator associativity (left-associative by default)
- [ ] Parse all statement types
- [ ] Parse all expression types
- [ ] Parse procedure/function declarations
- [ ] Handle forward declarations for recursive functions
- [ ] Generate AST from valid PCL programs
- [ ] Produce useful error messages for syntax errors

**Test Files:**
- `hello.pcl`
- `primes.pcl` — functions, loops
- `hanoi.pcl` — recursion, string parameters

**Notes:**
- Operator precedence/associativity: [SPEC.md §2.3](SPEC.md#23-operator-precedence-and-associativity)
- If/then/else has shift/reduce ambiguity (prefer longest match)

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
  project doesn't use — it's ocamllex/ocamlyacc per IMPLEMENTATION.md). Low priority while
  there's no `src/` yet, but the PDF (§4) requires README to have accurate install/usage
  instructions since that's what the instructor reads — rewrite it for real once the build
  actually works, don't just patch the current placeholder.

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

**Current Phase:** Not started

**Blockers:** None yet

**Next Steps:**
1. Set up OCaml project structure
2. Write lexer (ocamllex)
3. Design and write parser (ocamlyacc)
