# PCL Compiler Design

## Architecture

- **Lexer:** ocamllex tokenizer
- **Parser:** ocamlyacc recursive descent with bison
- **Semantic:** Single-pass semantic analysis with symbol table
- **IR:** Three-address code (TAC)
- **Codegen:** Direct x86-64 assembly generation

## Symbol Table

- Scope stack for nested functions/blocks
- Tracks: name, type, scope_level, is_parameter, etc.

## Type Coercion Rules

(list your rules from the PCL spec)

## Current Phase

- [x] Lexer (complete)
- [ ] Parser (in progress)
- [ ] Semantic analysis
- [ ] Intermediate code
- [ ] Code generation

## Known Issues

- (none yet)

## TODOs

- Handle nested comments
- Optimize tail recursion
- Better error messages
