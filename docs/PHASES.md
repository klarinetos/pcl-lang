# Compiler Phases Progress

Track completion of each compiler phase and major milestones.

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
- Operator precedence is critical (@ > ^ > +/- > * / div mod > + - > comparisons)
- If/then/else has shift/reduce ambiguity (prefer longest match)

---

## Phase 3: Semantic Analysis (2.0 units)

**Status:** Not started

**Description:**
Validate semantic correctness: type checking, scope rules, symbol table management, declaration validation.

**Deliverables:**
- [ ] Implement symbol table:
  - [ ] Track symbol: name, type, scope_level, is_parameter, etc.
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
- `bubble_sort.pcl` — array operations

**Notes:**
- Single-pass semantic analysis preferred
- Collect errors but continue analysis (report all errors at once)

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
- TAC format: `label: op arg1, arg2, result`
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

---

## Testing Progress

| Example | Status | Notes |
|---------|--------|-------|
| hello.pcl | Not started | Basic I/O |
| primes.pcl | Not started | Functions, loops, logic |
| hanoi.pcl | Not started | Recursion, strings |
| reverse.pcl | Not started | Arrays, strings |
| bubble_sort.pcl | Not started | Array manipulation |
| mean.pcl | Not started | Reals, arithmetic |

---

## Overall Progress

**Current Phase:** Not started

**Estimated Completion:**
- Lexer: Week 2
- Parser: Week 3
- Semantic: Week 4
- Intermediate Code: Week 5
- Code Generation: Week 6
- Testing/Polish: Week 7+

**Blockers:** None yet

**Next Steps:**
1. Set up OCaml project structure
2. Write lexer (ocamllex)
3. Design and write parser (ocamlyacc)
