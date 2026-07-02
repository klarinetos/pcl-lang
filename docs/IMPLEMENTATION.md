# Compiler Implementation

Our own decisions about how to build the `pclc` compiler — not dictated by the course, ours
to change. For what PCL itself requires, see [SPEC.md](SPEC.md). For status/progress, see
[PROGRESS.md](PROGRESS.md).

## Toolchain

- Implementation language: OCaml
- Lexer: ocamllex
- Parser: ocamlyacc

## Pipeline

- Semantic analysis: single-pass, collecting and reporting all errors rather than stopping
  at the first
- IR: three-address code (TAC)
- Codegen: direct x86-64 assembly generation (no LLVM) — this is what makes the "final code"
  and "no-LLVM" bonus units in [SPEC.md's grading table](SPEC.md#grading) available
