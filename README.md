# pcl-lang

A compiler for the PCL programming language, written in OCaml.

## About PCL

PCL is a statically-typed, procedural language with Pascal-like syntax. It features:
- Basic types: `integer`, `real`, `boolean`, `char`
- Arrays (fixed and dynamic size)
- Pointers and dynamic memory management
- Functions and procedures with recursion
- Standard I/O and math library functions

This compiler implements the PCL language specification for NTUA's Compilers course.

## Building

### Prerequisites

- OCaml 4.14+
- OPAM (OCaml Package Manager)
- Flex and Bison

### Setup (Linux/macOS)

```bash
opam switch create pcl-lang 4.14.0
opam install ocamlfind ocamllex ocamlyacc
```

### Compile

```bash
make
```

This produces the `pclc` executable.

### Clean

```bash
make clean      # Remove build artifacts
make distclean  # Remove everything including executable
```

## Usage

### Basic Usage

```bash
./pclc source.pcl
```

This produces:
- `source.imm` — Intermediate code
- `source.asm` — Final assembly code
- `a.out` — Executable

### With Options

```bash
./pclc -o myprogram source.pcl    # Specify output executable
./pclc -O source.pcl              # Enable optimization
./pclc -f < source.pcl            # Output final code to stdout
./pclc -i < source.pcl            # Output intermediate code to stdout
```

## Example

```pcl
program hello;
begin
  writeString("Hello, world!\n")
end.
```

Compile and run:

```bash
./pclc hello.pcl
./a.out
```

## Project Structure
