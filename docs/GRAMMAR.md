# PCL Grammar

Complete EBNF grammar for the PCL programming language.

## Terminal Symbols

- `⟨id⟩` — Identifier (alphanumeric + underscore, case-sensitive)
- `⟨integer-const⟩` — Integer constant (unsigned)
- `⟨real-const⟩` — Real constant (with optional exponent)
- `⟨char-const⟩` — Character constant in single quotes
- `⟨string-literal⟩` — String literal in double quotes

## Grammar Rules

```
⟨program⟩ ::= "program" ⟨id⟩ ";" ⟨body⟩ "."

⟨body⟩ ::= (⟨local⟩)* ⟨block⟩

⟨local⟩ ::= "var" (⟨id⟩ ("," ⟨id⟩)* ":" ⟨type⟩ ";")+ 
           | "label" ⟨id⟩ ("," ⟨id⟩)* ";"
           | ⟨header⟩ ";" ⟨body⟩ ";"
           | "forward" ⟨header⟩ ";"

⟨header⟩ ::= "procedure" ⟨id⟩ "(" [⟨formal⟩ (";" ⟨formal⟩)*] ")"
            | "function" ⟨id⟩ "(" [⟨formal⟩ (";" ⟨formal⟩)*] ")" ":" ⟨type⟩

⟨formal⟩ ::= ["var"] ⟨id⟩ ("," ⟨id⟩)* ":" ⟨type⟩

⟨type⟩ ::= "integer" 
          | "real" 
          | "boolean" 
          | "char"
          | "array" ["[" ⟨integer-const⟩ "]"] "of" ⟨type⟩
          | "^" ⟨type⟩

⟨block⟩ ::= "begin" ⟨stmt⟩ (";" ⟨stmt⟩)* "end"

⟨stmt⟩ ::= ε                                    (empty statement)
          | ⟨l-value⟩ ":=" ⟨expr⟩
          | ⟨block⟩
          | ⟨call⟩
          | "if" ⟨expr⟩ "then" ⟨stmt⟩ ["else" ⟨stmt⟩]
          | "while" ⟨expr⟩ "do" ⟨stmt⟩
          | ⟨id⟩ ":" ⟨stmt⟩
          | "goto" ⟨id⟩
          | "return"
          | "new" ["[" ⟨expr⟩ "]"] ⟨l-value⟩
          | "dispose" ["[]"] ⟨l-value⟩

⟨expr⟩ ::= ⟨l-value⟩ | ⟨r-value⟩

⟨l-value⟩ ::= ⟨id⟩
             | "result"
             | ⟨string-literal⟩
             | ⟨l-value⟩ "[" ⟨expr⟩ "]"
             | ⟨expr⟩ "^"
             | "(" ⟨l-value⟩ ")"

⟨r-value⟩ ::= ⟨integer-const⟩
             | "true"
             | "false"
             | ⟨real-const⟩
             | ⟨char-const⟩
             | "(" ⟨r-value⟩ ")"
             | "nil"
             | ⟨call⟩
             | "@" ⟨l-value⟩
             | ⟨unop⟩ ⟨expr⟩
             | ⟨expr⟩ ⟨binop⟩ ⟨expr⟩

⟨call⟩ ::= ⟨id⟩ "(" [⟨expr⟩ ("," ⟨expr⟩)*] ")"

⟨unop⟩ ::= "not" | "+" | "-"

⟨binop⟩ ::= "+" | "-" | "*" | "/" | "div" | "mod" 
            | "or" | "and"
            | "=" | "<>" | "<" | "<=" | ">" | ">="
```

## Operator Precedence and Associativity

From highest to lowest precedence:

| Operators | Description | Operands | Position | Associativity |
|-----------|-------------|----------|----------|---------------|
| `[]` | Array subscript | 2 | special | - |
| `@` | Address of | 1 | prefix | - |
| `^` | Dereference | 1 | postfix | - |
| `+` `-` | Sign (unary) | 1 | prefix | - |
| `not` | Logical negation | 1 | prefix | - |
| `*` `/` `div` `mod` `and` | Multiplicative | 2 | infix | left |
| `+` `-` `or` | Additive | 2 | infix | left |
| `=` `<>` `<` `<=` `>` `>=` | Relational | 2 | infix | none |

## Notes

### Grammar Properties

- **Ambiguity:** This grammar is ambiguous; operator precedence (above) resolves all ambiguities
- **Comments:** Not shown in grammar; `(*` ... `*)` are lexical elements, ignored by parser
- **Whitespace:** Ignored by lexer
- **Case Sensitivity:** Identifiers are case-sensitive; keywords are lowercase

### Key Language Features

**Variables and Types:**
- Basic types: `integer`, `real`, `boolean`, `char`
- Array types: `array[n] of T` (fixed) or `array of T` (dynamic)
- Pointer types: `^T`
- Nested type constructors allowed

**Procedures and Functions:**
- Procedures: no return value
- Functions: return a single value (not array type)
- Parameters: pass by value (default) or by reference (`var` keyword)
- Forward declarations: required for mutual recursion

**Scope Rules:**
- Lexically scoped (Pascal-style)
- Functions/procedures create new scopes
- Labels are procedure-local

**Statements:**
- Assignment to l-values (variables, array elements, dereferenced pointers)
- Control flow: `if`/`then`/`else`, `while` loops, `goto` (with labels)
- Procedure/function calls
- Memory: `new` (allocate), `dispose` (deallocate)
- Return from procedures/functions

### L-values vs R-values

**L-values** (can appear on left side of `:=`):
- Variables, parameters
- Array elements: `a[i]`
- Dereferenced pointers: `p^`
- String literals (treated as arrays)
- `result` keyword (inside functions)

**R-values** (evaluate to values):
- Constants (int, real, char, boolean, nil)
- L-values used as expressions
- Function calls
- Address operator: `@x`
- Operators: unary/binary expressions

## Examples

### Simple Variable Declaration and Assignment
```
var x : integer;
var y, z : real;
x := 42;
y := 3.14
```

### Function Definition
```
function factorial (n : integer) : integer;
begin
  if n <= 1 then
    result := 1
  else
    result := n * factorial(n - 1)
end;
```

### Array and Pointer Usage
```
var arr : array [10] of integer;
var ptr : ^integer;

arr[0] := 5;
new ptr;
ptr^ := 10;
dispose ptr
```

### Procedure with Parameters
```
procedure swap (var a, b : integer);
var tmp : integer;
begin
  tmp := a;
  a := b;
  b := tmp
end;
```
