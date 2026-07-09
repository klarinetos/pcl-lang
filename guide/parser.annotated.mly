/* ============================================================================
   ANNOTATED REFERENCE COPY - NOT PART OF THE BUILD.

   This is src/parser.mly with heavy line-by-line explanation added, for
   learning/reference only. The Makefile never looks at this file - the real,
   authoritative, buildable grammar is src/parser.mly. If you change the real
   grammar, this copy will silently go stale; it is not kept in sync
   automatically. See also guide/PARSER_WALKTHROUGH.md for the narrative
   version of this same explanation, and guide/lexer.annotated.mll for the
   equivalent treatment of Phase 1.
   ============================================================================ */

/* A .mly file has four sections, in this order:
     1. A header in %{ %}: plain OCaml, copied verbatim into the generated
        parser.ml. Here it is just "open Ast", so the rule actions below can
        write EInt 5 instead of Ast.EInt 5.
     2. Declarations: %token (which tokens exist and what OCaml type, if any,
        each one carries), then %nonassoc/%left/%right precedence lines, then
        %start (which nonterminal is the entry point) and %type (what OCaml
        type that entry point produces).
     3. %% - separates declarations from the grammar rules below.
     4. Grammar rules: "name : alternative1 { action1 } | alternative2
        { action2 } | ..." - each names a nonterminal (a grammar symbol built
        from tokens and/or other nonterminals) and lists every sequence of
        symbols that can produce it, with an OCaml action to run when that
        sequence is fully matched. Inside an action, $1, $2, $3, ... refer to
        the already-built values of the 1st, 2nd, 3rd, ... symbol in that
        specific alternative (not the whole rule - each alternative numbers
        its own symbols starting from 1).
   ocamlyacc turns this into TWO files: parser.ml (the actual table-driven
   parsing logic) and parser.mli (its public interface - mostly just the
   token type and the entry-point function's type signature). Neither is
   hand-edited; both are regenerated every build, which is why they are
   gitignored, same as lexer.ml. */

%{
  open Ast
%}

/* Token declarations, identical to Phase 1 - the lexer already needed these,
   since it has to know what values it is allowed to return. Nothing here
   changed for Phase 2; only the grammar rules below (section 4) did. */
%token <string> ID
%token <int> ICONST
%token <float> RCONST
%token <char> CCONST
%token <string> SCONST

%token AND ARRAY BEGIN BOOLEAN CHAR DISPOSE DIV DO
%token ELSE END FALSE FORWARD FUNCTION GOTO IF INTEGER
%token LABEL MOD NEW NIL NOT OF OR PROCEDURE
%token PROGRAM REAL RESULT RETURN THEN TRUE VAR WHILE

%token EQ GT LT NE GE LE PLUS MINUS TIMES SLASH CARET AT
%token ASSIGN SEMI DOT LPAREN RPAREN COLON COMMA LBRACKET RBRACKET

%token EOF

/* --------------------------------------------------------------------------
   PRECEDENCE DECLARATIONS

   SPEC.md section 2 says outright that PCL's grammar is ambiguous - the same
   token sequence can be grouped more than one structurally different way -
   and that the precedence/associativity table in SPEC.md section 2.3 is
   what resolves it. Concretely: nothing in a bare rule like
   "expr : expr PLUS expr | expr TIMES expr | ..." says whether
   "2 + 3 * 4" should group as "2 + (3 * 4)" or "(2 + 3) * 4" - both are
   equally valid parses of that rule shape on their own. These declarations
   tell ocamlyacc which grouping to prefer.

   Lines are listed LOWEST to HIGHEST precedence - each line binds TIGHTER
   than the one above it. %left means left-associative (a - b - c groups as
   (a - b) - c); %nonassoc means the operator cannot be chained at all
   without parentheses (a = b = c is a hard parse error, not "compare
   left-to-right").
   -------------------------------------------------------------------------- */

/* THEN/ELSE resolve the classic "dangling else" ambiguity: for
   "if a then if b then x else y", does "else y" belong to the inner
   "if b" or the outer "if a"? Both are grammatically valid readings of
   "if E then S | if E then S else S" taken in isolation. Giving ELSE
   higher precedence than THEN makes the parser prefer to keep reading
   (shift) when it sees ELSE, rather than closing off the outer if early
   (reduce) - which means an else always attaches to the nearest still-open
   if, exactly what SPEC.md section 2.4 requires. Without this, ocamlyacc
   would report an unresolved shift/reduce conflict here and silently
   default to shift anyway - these two lines make that resolution
   intentional and documented instead of an unexplained default. */
%nonassoc THEN
%nonassoc ELSE

/* Relational operators: lowest of the "real" operators. Note %nonassoc, not
   %left - SPEC.md section 4.3 says these do not chain (a = b = c is invalid,
   not "compare left to right"). Also worth knowing: this tier sits BELOW
   the multiplicative/additive tiers just below, meaning "and"/"or" bind
   TIGHTER than comparisons in PCL - the opposite of C-family languages. See
   guide/PARSER_WALKTHROUGH.md for what this means in practice (short
   version: parenthesize every comparison before combining it with and/or). */
%nonassoc EQ NE LT LE GT GE

/* Additive tier: left-associative, so "a - b - c" groups as "(a - b) - c"
   rather than "a - (b - c)" (those give different results for subtraction,
   which is why associativity direction actually matters here, unlike for
   the nonassoc relational tier above). */
%left PLUS MINUS OR

/* Multiplicative tier: binds tighter than additive, so "2 + 3 * 4" groups
   the "3 * 4" first. */
%left TIMES SLASH DIV MOD AND

/* NOT, and the placeholder names UMINUS/UPLUS, are all unary prefix
   operators, listed here at a single precedence tier above the binary
   arithmetic operators. UMINUS and UPLUS do not correspond to any real
   token the lexer produces - PLUS and MINUS already exist as tokens, used
   for BOTH their unary (-x) and binary (x - y) meanings. Those two uses
   need DIFFERENT precedence (unary sign binds tighter than binary +/- per
   the table), so the grammar rules for the unary forms attach "%prec
   UMINUS" / "%prec UPLUS" to explicitly borrow precedence from these
   placeholder names instead of using PLUS/MINUS's own (binary) precedence.
   That is the entire purpose of %prec: overriding which precedence level
   applies to one specific rule, when the rule's last token is not a good
   enough signal on its own. */
%nonassoc NOT UMINUS UPLUS

/* Dereference (postfix ^) binds tighter than unary sign/not. */
%nonassoc CARET

/* Address-of (prefix @) is the tightest-binding of this group - e.g. @x^
   parses as (@x)^ rather than @(x^), matching SPEC.md's table where @ is
   listed above ^. */
%nonassoc AT

%start program
%type <Ast.program> program

%%

/* --------------------------------------------------------------------------
   GRAMMAR RULES

   Roughly follows the shape of the program, top to bottom: a whole program
   is a header plus a body; a body is local declarations plus a block; a
   block is a sequence of statements; statements contain expressions;
   expressions bottom out in constants, names, and operators.
   -------------------------------------------------------------------------- */

/* SPEC.md section 4: "program p; <body> ." The action builds the top-level
   Ast.program record directly from the pieces already parsed: $2 is the
   program's name (ID), $4 is the already-built Ast.body value. */
program:
  PROGRAM ID SEMI body DOT EOF   { { pname = $2; pbody = $4 } }
;

/* A body is its local declarations (possibly none) followed by exactly one
   compound statement (the block). */
body:
  locals block   { { locals = $1; block = $2 } }
;

/* Zero or more local declarations. This is the standard yacc idiom for "a
   list of things": an empty alternative for the base case, and a recursive
   alternative that peels off one item and recurses on the rest. Note this
   particular list is built RIGHT-recursively (local locals, not locals
   local) - for a fixed-size list like this it does not matter for
   correctness, it is just a style choice; it does mean OCaml builds the
   list from the last local declaration backwards via "::", finishing with
   the very first one, though the final list order comes out correct either
   way since "::" prepends. */
locals:
  /* empty */      { [] }
  | local locals   { $1 :: $2 }
;

/* SPEC.md section 4's four kinds of local declaration:
     - a var block (one or more name-list : type groups under one "var")
     - a label declaration (comma-separated label names)
     - a nested subprogram DEFINITION (header, then its own full body)
     - a forward DECLARATION (header only, body comes later, for mutual
       recursion - SPEC.md section 4's "Subprograms" note) */
local:
  VAR var_groups           { LVar $2 }
  | LABEL id_list SEMI     { LLabel $2 }
  | header SEMI body SEMI  { LSub { shdr = $1; sbody = $3 } }
  | FORWARD header SEMI    { LForward $2 }
;

/* One "var" keyword can introduce MULTIPLE "names : type ;" groups without
   repeating "var" - e.g. "var i : integer; x, y : real;" is one "local"
   (one LVar case) containing two groups. This list is what LVar actually
   stores: (string list * typ) list. */
var_groups:
  var_group              { [$1] }
  | var_group var_groups  { $1 :: $2 }
;

var_group:
  id_list COLON typ SEMI   { ($1, $3) }
;

/* Comma-separated identifiers, e.g. "a, b, c" - used both for variable
   groups (var_group above) and label lists. */
id_list:
  ID                 { [$1] }
  | ID COMMA id_list  { $1 :: $3 }
;

/* A subprogram's header: procedure (no return type) or function (return
   type required, cannot be an array type per SPEC.md section 4 - that
   restriction is not enforced here at the grammar level, since "typ" below
   allows array types unconditionally; it is a Phase 3 semantic check). */
header:
  PROCEDURE ID LPAREN formals RPAREN               { { hname = $2; hparams = $4; hret = None } }
  | FUNCTION ID LPAREN formals RPAREN COLON typ     { { hname = $2; hparams = $4; hret = Some $7 } }
;

/* Parentheses are mandatory even with zero parameters (SPEC.md section 4),
   which is exactly why "formals" has an empty alternative here rather than
   the parentheses themselves being optional. */
formals:
  /* empty */   { [] }
  | formal_list { $1 }
;

formal_list:
  formal                    { [$1] }
  | formal SEMI formal_list { $1 :: $3 }
;

/* A formal parameter group is by-value by default, or by-reference if
   prefixed with "var" - SPEC.md section 4's pass-by-value vs
   pass-by-reference distinction. Note by-value parameters are not
   prevented from being array types here (SPEC.md says they cannot be) -
   again, deferred to semantic analysis. */
formal:
  id_list COLON typ         { { by_ref = false; pnames = $1; ptyp = $3 } }
  | VAR id_list COLON typ   { { by_ref = true; pnames = $2; ptyp = $4 } }
;

/* Types, matching SPEC.md section 3's grammar for <type> directly:
   basic types, fixed-size arrays, unsized arrays, and pointers, with
   pointers/arrays able to nest arbitrarily (typ appears recursively on the
   right of ARRAY/CARET). */
typ:
  INTEGER                          { TInteger }
  | REAL                           { TReal }
  | BOOLEAN                        { TBoolean }
  | CHAR                           { TChar }
  | ARRAY LBRACKET ICONST RBRACKET OF typ  { TArray (Some $3, $6) }
  | ARRAY OF typ                   { TArray (None, $3) }
  | CARET typ                      { TPointer $2 }
;

/* A compound statement. Returns just the statement list ($2) - the
   BEGIN/END keywords themselves do not need to be remembered in the AST,
   they have already served their only purpose (telling the parser where
   the block starts and ends) by the time this rule's action runs. */
block:
  BEGIN stmts END   { $2 }
;

/* Semicolon-separated statements, at least one (SPEC.md's grammar:
   stmt (";" stmt)*). Since "stmt" itself has an empty/epsilon alternative
   (see below), a trailing semicolon before END still parses fine - it just
   means the last "stmt" in the list is an SEmpty node. */
stmts:
  stmt              { [$1] }
  | stmt SEMI stmts  { $1 :: $3 }
;

/* Every statement form from SPEC.md section 5, in the same order as that
   section lists them. The empty alternative first is deliberate: PCL's
   grammar explicitly allows a statement position to contain nothing (the
   epsilon case), which combined with stmts above is what makes e.g. two
   consecutive semicolons, or a semicolon right before END, legal syntax
   rather than an error. */
stmt:
  /* empty */                       { SEmpty }
  | lvalue ASSIGN expr              { SAssign ($1, $3) }
  | block                          { SBlock $1 }
  | call                          { let (f, args) = $1 in SCall (f, args) }

  /* Two separate rules for if, rather than one rule with an optional else,
     because that is what lets the THEN/ELSE precedence declarations above
     actually apply: "%prec THEN" on the single-branch form explicitly marks
     it as the LOWER-precedence alternative, so whenever both this rule and
     the two-branch rule below could apply to the same ELSE token, ocamlyacc
     prefers extending the two-branch form (shifting into it) over
     completing this one (reducing) - see the THEN/ELSE comment up in the
     precedence section for the full reasoning. */
  | IF expr THEN stmt %prec THEN   { SIf ($2, $4, None) }
  | IF expr THEN stmt ELSE stmt    { SIf ($2, $4, Some $6) }

  | WHILE expr DO stmt             { SWhile ($2, $4) }

  /* Labeled statement. Note this does not check that the label was
     actually declared in the unit's "label" section (SPEC.md section 4
     requires that) - the grammar only knows this is syntactically an
     identifier followed by a colon then a statement; whether that specific
     identifier was properly declared as a label is a Phase 3 concern. */
  | ID COLON stmt                  { SLabel ($1, $3) }
  | GOTO ID                        { SGoto $2 }
  | RETURN                         { SReturn }

  /* new/dispose, each in their two forms from SPEC.md section 5 - plain
     (single object) and bracketed (dynamic array, with a size expression
     for new specifically). */
  | NEW lvalue                     { SNew (None, $2) }
  | NEW LBRACKET expr RBRACKET lvalue  { SNew (Some $3, $5) }
  | DISPOSE lvalue                 { SDispose (false, $2) }
  | DISPOSE LBRACKET RBRACKET lvalue   { SDispose (true, $4) }
;

/* --------------------------------------------------------------------------
   LVALUE vs EXPR

   SPEC.md section 5.1 restricts what can appear as an assignment target, a
   by-reference argument, or a new/dispose target, to a specific short list
   of forms - everything else (constants, function calls, arithmetic
   results) can only ever be READ, never assigned to. This grammar encodes
   that restriction directly, by making "lvalue" its own nonterminal instead
   of folding all of its alternatives into the general "expr" rule below.
   Concretely, this means something like "1 + 2 := x" is rejected right here
   at parse time (a syntax error), rather than being accepted by the parser
   and only caught later during semantic analysis - because ASSIGN's
   left-hand side is required to BE an lvalue, and "1 + 2" can only ever
   reduce to "expr", never to "lvalue".
   -------------------------------------------------------------------------- */
lvalue:
  ID                        { EId $1 }
  | RESULT                  { EResult }
  | SCONST                  { EString $1 }

  /* Left-recursive on lvalue itself (not the general expr) - matches
     SPEC.md's grammar exactly: only an lvalue can be indexed, e.g. you
     cannot write "f()[0]" where f() is a function call (an expr, not an
     lvalue), only "a[0]" where a already is one. */
  | lvalue LBRACKET expr RBRACKET  { EIndex ($1, $3) }

  /* Dereference DOES take a general expr on its left (not lvalue
     specifically) - SPEC.md's own grammar agrees: "<expr> ^", not
     "<l-value> ^" - since you can dereference the result of, say, a
     function call that returns a pointer, not just a pointer-typed
     variable. */
  | expr CARET               { EDeref $1 }

  | LPAREN lvalue RPAREN     { $2 }
;

/* ONE EXCEPTION to the "lvalue is restricted, everything else is general
   expr" rule: address-of ("@"). The obviously-matching grammar rule would
   be "AT lvalue", mirroring how SPEC.md's own grammar states it - but that
   turns out to be impossible to build cleanly with ocamlyacc, which only
   implements LALR(1) (1 token of lookahead, with some parser states merged
   together to keep the parsing table small). Writing it as "AT lvalue"
   produced 15 reduce/reduce conflicts, every one boiling down to the same
   root cause: once the parser finishes recognizing an lvalue, it cannot
   tell - from the resulting state alone - whether it got there via the
   plain "expr : lvalue" passthrough two rules below, or via "expr : AT
   lvalue", because BOTH completions are simultaneously "ready to fire" at
   that exact point (unlike NOT/unary PLUS/MINUS just below, whose operand
   is a general expr, already fully collapsed to one symbol by the time
   THEIR rule tries to complete - lvalue is not collapsed the same way,
   since it is ALSO independently, directly reducible to expr).

   The fix applied here: give "@" a general expr operand too, exactly like
   the other unary operators. This does mean something like "@(1+2)" is now
   accepted by the PARSER, even though it is nonsense (you cannot take the
   address of an arithmetic result, only of an actual lvalue) - that
   specific check is deferred to Phase 3 (semantic analysis) instead, the
   same category of deferred check as "is this label actually declared" for
   the labeled-statement rule above. See guide/PARSER_WALKTHROUGH.md for the
   full trace of how this conflict was found and diagnosed via
   src/parser.output. */
expr:
  lvalue                    { $1 }
  | ICONST                  { EInt $1 }
  | TRUE                    { EBool true }
  | FALSE                   { EBool false }
  | RCONST                  { EReal $1 }
  | CCONST                  { EChar $1 }
  | LPAREN expr RPAREN      { $2 }
  | NIL                     { ENil }
  | call                    { let (f, args) = $1 in ECall (f, args) }
  | AT expr %prec AT         { EAddr $2 }
  | NOT expr                 { EUnop (UNot, $2) }

  /* %prec UPLUS / %prec UMINUS: without these, ocamlyacc would use PLUS's
     and MINUS's own (binary) precedence for these unary rules too, which
     is wrong per SPEC.md's table (unary sign binds tighter than binary
     +/-). This is the concrete mechanism behind the general explanation up
     in the precedence-declarations section. */
  | PLUS expr %prec UPLUS    { EUnop (UPlus, $2) }
  | MINUS expr %prec UMINUS  { EUnop (UMinus, $2) }

  /* Binary arithmetic/logical/relational operators. Each is its own
     alternative rather than one generic "expr binop expr" rule, because
     ocamlyacc's precedence resolution keys off the SPECIFIC token in the
     rule (PLUS, TIMES, EQ, ...) via the %left/%nonassoc declarations above
     - there is no way to write one generic rule parameterized over "which
     operator" and still have per-operator precedence apply automatically. */
  | expr PLUS expr    { EBinop (Add, $1, $3) }
  | expr MINUS expr   { EBinop (Sub, $1, $3) }
  | expr TIMES expr   { EBinop (Mul, $1, $3) }
  | expr SLASH expr   { EBinop (Div, $1, $3) }
  | expr DIV expr     { EBinop (DivInt, $1, $3) }
  | expr MOD expr     { EBinop (Mod, $1, $3) }
  | expr OR expr      { EBinop (Or, $1, $3) }
  | expr AND expr     { EBinop (And, $1, $3) }
  | expr EQ expr      { EBinop (Eq, $1, $3) }
  | expr NE expr      { EBinop (Neq, $1, $3) }
  | expr LT expr      { EBinop (Lt, $1, $3) }
  | expr LE expr      { EBinop (Le, $1, $3) }
  | expr GT expr      { EBinop (Gt, $1, $3) }
  | expr GE expr      { EBinop (Ge, $1, $3) }
;

/* Function/procedure call syntax is identical either way (SPEC.md section
   4.4) - the difference (does it return a value or not) is what the
   CALLER context does with this same "call" nonterminal: "stmt" wraps it in
   SCall and discards any result, "expr" wraps it in ECall and keeps the
   value. The grammar itself does not need to know, at this point, whether
   the named function is actually a procedure or a function - that is a
   symbol-table lookup, which is Phase 3's job. */
call:
  ID LPAREN args RPAREN   { ($1, $3) }
;

args:
  /* empty */  { [] }
  | expr_list  { $1 }
;

expr_list:
  expr                  { [$1] }
  | expr COMMA expr_list { $1 :: $3 }
;

/* ----------------------------------------------------------------------
   ON THE REDUCE/REDUCE CONFLICT MENTIONED ABOVE, IF YOU WANT TO SEE IT
   YOURSELF:
   The Makefile already passes -v to ocamlyacc, which writes
   src/parser.output alongside the generated parser.ml/parser.mli - a full
   dump of every parser state and every conflict. Searching that file for
   "reduce/reduce" (before the @ fix was applied) pointed at one specific
   state containing exactly two items simultaneously ready to fire:
   "expr : lvalue ." and "expr : AT lvalue .", both trying to reduce on the
   same lookahead tokens. Two different rules both saying "I am done,
   reduce me now" at the same point, with no principled way to choose, is
   the literal definition of a reduce/reduce conflict. This output file is
   regenerated every build and gitignored - useful for debugging, not
   something to hand-maintain.
   ---------------------------------------------------------------------- */
