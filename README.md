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

### Setup (Windows)

The toolchain doesn't run natively on Windows, so everything is built and run inside **WSL2**
(Windows Subsystem for Linux), which gives you an Ubuntu environment that can see your Windows
files. The repo can be anywhere on your machine.

**1. Install WSL with Ubuntu (one-time).** Open PowerShell *as Administrator* and run:

```powershell
wsl --install -d Ubuntu
```

Reboot if asked. Then open the **Ubuntu** app from the Start menu once; it will ask you to
choose a Linux username and password (these are separate from your Windows login).

> If `wsl --list` already shows an Ubuntu distro, skip this step.

**2. Install the build tools (one-time).** In the Ubuntu app, run:

```bash
sudo apt update
sudo apt install ocaml make gcc
```

The `ocaml` package already includes `ocamlopt`, `ocamllex` and `ocamlyacc`. Check that
everything is there:

```bash
ocaml -version
which ocamllex ocamlyacc ocamlopt make gcc
```

Any recent version works; the code has been built with OCaml 4.14 (Ubuntu 24.04) and
OCaml 5.4 (Ubuntu 26.04).

**3. Build.** Open PowerShell or Command Prompt in the repo folder (wherever you cloned it, e.g.
via `cd`, or *Open in Terminal* from File Explorer) and prefix commands with `wsl`:

```powershell
wsl make
wsl ./pclc test/hello.pcl
```

`wsl <command>` runs the command in Ubuntu, starting from your current folder, so no paths
need to be typed. Alternatively, type `wsl` on its own to open a Linux shell in that folder and
use the commands in [Compile](#compile) and [Usage](#usage) as-is.

> `pclc` is a Linux program: always run it through `wsl` (or from a WSL shell), not directly
> from PowerShell. Your Windows drives appear inside WSL under `/mnt/` (`C:\` is `/mnt/c/`) if
> you ever need to `cd` there manually.

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

```
pcl-lang/
├── src/
│   ├── lexer.mll          # Lexical analyzer (ocamllex)
│   ├── parser.mly         # Syntax analyzer (ocamlyacc)
│   ├── semantic.ml        # Semantic analysis
│   ├── codegen.ml         # Code generation
│   └── main.ml            # Entry point
├── test/
│   ├── hello.pcl
│   ├── primes.pcl
│   └── ...
├── Makefile
└── README.md
```

## Authors

Anna Eirini Anagnostopoulou

Sotiris Gkiouleas

## Course

NTUA Electrical & Computer Engineering School
Compilers Course (2026)
Instructor: Kostis Sagonas
