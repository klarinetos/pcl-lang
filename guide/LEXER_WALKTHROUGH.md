# Lexer Walkthrough

Explainer for what got built in Phase 1, step by step. This is a one-time reference for
understanding the code, not part of Claude's working context (that's SPEC.md/
IMPLEMENTATION.md/PROGRESS.md) — it won't get kept in sync automatically if the lexer
changes later.

## What a lexer actually does

Before anything can be parsed into a syntax tree, the raw text of a `.pcl` file has to be
chopped into meaningful chunks — "tokens" — and whitespace/comments have to be thrown away.
E.g. the text:

```pascal
x := 42 + y;
```

becomes the token sequence `ID(x) ASSIGN ICONST(42) PLUS ID(y) SEMI`. The lexer is a
function that reads characters one at a time and produces this token stream. It knows
nothing about grammar (is this a valid statement?) — that's the parser's job, next phase.
The lexer's only job is: given the next few characters, what's the next token, and what's
its value if it carries one (a name, a number, etc.)?

## Files involved

- **`src/lexer.mll`** — the lexer itself, written in `ocamllex`'s DSL (a mix of regex-style
  pattern rules and embedded OCaml code).
- **`src/parser.mly`** — normally this is the *parser* (Phase 2), but right now it only
  declares the **token type** — the list of all possible token names — because the lexer
  needs to know what values it's allowed to return. Think of it as a shared vocabulary file.
  The actual grammar rules (how tokens combine into valid programs) are a single placeholder
  rule for now.
- **`src/main.ml`** — a throwaway command-line driver: run `./pclc file.pcl` and it prints
  every token it finds, one per line. This isn't the real compiler CLI (that comes later,
  once parsing/codegen exist) — it exists purely so the lexer can be tested standalone.
- **`src/semantic.ml`, `src/codegen.ml`** — empty files. The build (`make`) links all five
  `.ml` files into one executable, so these have to exist even though nothing's in them yet.

## How `ocamllex` turns `lexer.mll` into a lexer

`ocamllex` reads `lexer.mll` and generates `lexer.ml` — an actual OCaml function. You never
edit `lexer.ml` by hand; it's regenerated every build (and it's gitignored). The `.mll` file
has three parts:

1. **Header** (the `{ ... }` block at the top) — plain OCaml code: helper functions, the
   keyword lookup table, the error type. This gets copied verbatim into the generated file.
2. **Named regex definitions** (`let digit = ['0'-'9']` etc.) — reusable building blocks for
   the rules below.
3. **Rules** (`rule token = parse | pattern1 { action1 } | pattern2 { action2 } ...`) — for
   each pattern, if the input matches, run the corresponding OCaml code and return its
   result.

The key thing to understand about how these pattern rules resolve ambiguity: **longest match
wins**. If two rules could both match starting at the current position, the one that
consumes more characters is chosen. If there's a tie in length, whichever rule is listed
first in the file wins. This is why, e.g., `<=` is correctly read as one `LE` token instead
of `<` followed by `=` — the two-character rule matches more text, so it wins automatically,
regardless of where I put it in the file.

## Walking through what each rule does

**Whitespace and comments** get consumed and thrown away (no token produced), then the lexer
just calls itself again to keep going:
```
| [' ' '\t' '\r']  { token lexbuf }
| '\n'             { incr line; token lexbuf }
| "(*"             { comment lexbuf; token lexbuf }
```
Comments are handled by a *second* rule, `comment`, which just eats characters until it sees
`*)`. Per the spec, PCL comments don't nest — so `comment` doesn't track a nesting depth, it
just stops at the very first `*)` it finds, even if there was an earlier `(*` inside it.

**Keywords vs. identifiers** are the same regex, disambiguated afterward:
```
| id as s
    { match Hashtbl.find_opt keyword_table s with
      | Some tok -> tok
      | None -> ID s }
```
Rather than writing 32 separate rules (one per keyword `and`, `array`, `begin`, ...), there's
one rule matching *any* valid identifier shape, and then a hashtable lookup decides whether
the matched text is actually a reserved keyword or a genuine identifier. This is also why
case sensitivity falls out for free: the table only has lowercase keys, so `AND` (uppercase)
never matches an entry and is correctly treated as an ordinary identifier, while `and`
(lowercase) is.

**Numbers**: two rules, `rconst` (real) and `iconst` (integer). `rconst` requires a decimal
point followed by at least one digit (matching the spec: a bare trailing `.` — like the one
ending every PCL program — is never mistaken for the start of a number). Because of
longest-match, `42.0` is read as one `RCONST` token, not `ICONST(42)` followed by a `DOT` and
another number.

**Char and string literals**: both reuse the same idea — a "common character" is anything
printable except the two quote characters, backslash, and raw newlines, and an "escape" is a
backslash followed by one of `n t r 0 \ ' "`. A string is `"` followed by any mix of those,
followed by `"`. The raw text between the quotes gets captured, then a helper function
(`unescape`) walks through it converting `\n` into an actual newline character, `\t` into an
actual tab, etc. — the token carries the *resolved* value, not the literal source text.

**Errors**: three specific situations get a clear message instead of a confusing generic
failure — an unterminated string (quote opened, never closed before end of line), an
unterminated char constant, and an unterminated comment (`(*` with no matching `*)` before
end of file). Anything not matched by any rule (e.g. a stray `#` or `$`) falls through to a
catch-all that reports "unexpected character". All of these raise a `Lex_error` exception
carrying the current line number, which `main.ml` catches and turns into a clean one-line
error message plus exit code 1, rather than an OCaml stack trace.

## The Makefile bug I found while testing

`ocamlyacc` (which turns `parser.mly` into real OCaml) produces *two* files: `parser.ml`
(the implementation) and `parser.mli` (its public interface — basically just the list of
token names in this case, since there's no real grammar yet). Before OCaml can compile
`parser.ml` itself, it needs a pre-compiled version of `parser.mli` called `parser.cmi`. The
Makefile as originally written never had a rule to build that `.cmi` file — it went straight
from `parser.mli` existing on disk to trying to compile `parser.ml`, which failed with
`Could not find the .cmi file for interface src/parser.mli`. I added an explicit rule for it
and made everything that needs it (`parser.cmx`, `lexer.cmx`, `main.cmx`) depend on it.

## How I actually verified this works

There was no OCaml installed anywhere on this machine, so "the lexer compiles in my head" 
wasn't good enough. I installed OCaml 4.14.1 into your WSL Ubuntu distro (had to run as
root since the sudo password didn't work), built the project with `make`, and then:

- Ran all 6 files in `test/` through it — all tokenize cleanly through to `EOF` with no
  errors.
- Wrote small one-off `.pcl` snippets to specifically exercise: non-nesting comments (an
  inner `(* ... *)` correctly doesn't "protect" the outer comment — it ends at the first
  `*)`), all three error paths (invalid character, unterminated string, unterminated
  comment — each printed the right message, right line number, and exit code 1), real
  number exponents (`4.2e1`, `0.420e+2`, `42000.0e-3`), case-sensitive keyword-vs-identifier
  handling (`AND` as an identifier vs. `and` as the keyword), and the multi-character
  operators (`<>`, `>=`, `<=`).
- Cleaned up all generated build artifacts afterward (`make distclean`) so nothing
  compiler-generated got committed — that's what the new `.gitignore` entries are for.

## What's still fake / not done

- `src/parser.mly` only has token declarations, not real grammar rules. The `program` rule
  in there right now (`program: EOF { () }`) is a placeholder just so `ocamlyacc` has
  something to generate from — Phase 2 replaces it with the actual grammar.
- `src/main.ml` is a lexer test harness, not the real `pclc` CLI. It doesn't know about
  `-o`/`-O`/`-f`/`-i` yet (see SPEC.md §9) — that gets built once there's an actual
  compilation pipeline to drive.
- `src/semantic.ml` and `src/codegen.ml` are empty on purpose.
