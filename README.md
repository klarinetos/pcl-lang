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

The toolchain (`ocamlopt`, `ocamllex`, `ocamlyacc`, `make`, `gcc`) doesn't run natively on
Windows here — everything is built and run inside **WSL2** (Windows Subsystem for Linux). This
is what we actually did:

1. Install WSL2 with an Ubuntu distro (from an elevated PowerShell/Command Prompt):
   ```powershell
   wsl --install -d Ubuntu
   ```
   This installs Ubuntu 24.04 ("noble") in our setup; reboot if prompted, then open the
   "Ubuntu" app once to finish first-run setup (create a UNIX username/password).
2. Inside the WSL Ubuntu shell, install OCaml and the rest of the toolchain via `apt` (not
   opam — no opam switch is used on this setup):
   ```bash
   sudo apt update
   sudo apt install ocaml make gcc
   ```
   `ocaml` on Ubuntu pulls in `ocamllex`/`ocamlyacc`/`ocamlopt` as part of the same package;
   there's nothing further to install. Confirm with:
   ```bash
   ocaml -version        # 4.14.1
   which ocamllex ocamlyacc ocamlopt make gcc
   ```
3. From Windows, the repo lives under `/mnt/c/...` inside WSL (e.g.
   `/mnt/c/Users/<you>/Desktop/Projects/pcl-lang` for a repo checked out to
   `C:\Users\<you>\Desktop\Projects\pcl-lang`) — `cd` there inside the WSL shell and run `make`
   as in the Linux instructions above. No separate Windows build is set up; `pclc`/`pcli` are
   Linux ELF binaries meant to be run from inside WSL, not from PowerShell/cmd.exe directly.
4. One-liner from PowerShell/Command Prompt without opening a WSL shell first:
   ```powershell
   wsl -e bash -lc "cd /mnt/c/Users/<you>/Desktop/Projects/pcl-lang && make"
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
