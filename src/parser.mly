%{
  open Ast
%}

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

/* Lowest to highest. THEN/ELSE resolves the dangling-else shift/reduce
   conflict: giving ELSE higher precedence than the plain "if-then" rule
   makes the parser shift on ELSE rather than reduce, so it always attaches
   to the nearest unmatched if (SPEC.md §2.4). The rest mirrors the operator
   table in SPEC.md §2.3. UPLUS/UMINUS are precedence-only placeholder names
   (never produced by the lexer) used via %prec to give unary +/- their own
   precedence separate from the same tokens' binary use. */
%nonassoc THEN
%nonassoc ELSE
%nonassoc EQ NE LT LE GT GE
%left PLUS MINUS OR
%left TIMES SLASH DIV MOD AND
%nonassoc NOT UMINUS UPLUS
%nonassoc CARET
%nonassoc AT

%start program
%type <Ast.program> program

%%

program:
  PROGRAM ID SEMI body DOT EOF   { { pname = $2; pbody = $4 } }
;

body:
  locals block   { { locals = $1; block = $2 } }
;

locals:
  /* empty */      { [] }
  | local locals   { $1 :: $2 }
;

local:
  VAR var_groups           { LVar $2 }
  | LABEL id_list SEMI     { LLabel $2 }
  | header SEMI body SEMI  { LSub { shdr = $1; sbody = $3 } }
  | FORWARD header SEMI    { LForward $2 }
;

var_groups:
  var_group              { [$1] }
  | var_group var_groups  { $1 :: $2 }
;

var_group:
  id_list COLON typ SEMI   { ($1, $3) }
;

id_list:
  ID                 { [$1] }
  | ID COMMA id_list  { $1 :: $3 }
;

header:
  PROCEDURE ID LPAREN formals RPAREN               { { hname = $2; hparams = $4; hret = None } }
  | FUNCTION ID LPAREN formals RPAREN COLON typ     { { hname = $2; hparams = $4; hret = Some $7 } }
;

formals:
  /* empty */   { [] }
  | formal_list { $1 }
;

formal_list:
  formal                    { [$1] }
  | formal SEMI formal_list { $1 :: $3 }
;

formal:
  id_list COLON typ         { { by_ref = false; pnames = $1; ptyp = $3 } }
  | VAR id_list COLON typ   { { by_ref = true; pnames = $2; ptyp = $4 } }
;

typ:
  INTEGER                          { TInteger }
  | REAL                           { TReal }
  | BOOLEAN                        { TBoolean }
  | CHAR                           { TChar }
  | ARRAY LBRACKET ICONST RBRACKET OF typ  { TArray (Some $3, $6) }
  | ARRAY OF typ                   { TArray (None, $3) }
  | CARET typ                      { TPointer $2 }
;

block:
  BEGIN stmts END   { $2 }
;

stmts:
  stmt              { [$1] }
  | stmt SEMI stmts  { $1 :: $3 }
;

stmt:
  /* empty */                       { SEmpty }
  | lvalue ASSIGN expr              { SAssign ($1, $3) }
  | block                          { SBlock $1 }
  | call                          { let (f, args) = $1 in SCall (f, args) }
  | IF expr THEN stmt %prec THEN   { SIf ($2, $4, None) }
  | IF expr THEN stmt ELSE stmt    { SIf ($2, $4, Some $6) }
  | WHILE expr DO stmt             { SWhile ($2, $4) }
  | ID COLON stmt                  { SLabel ($1, $3) }
  | GOTO ID                        { SGoto $2 }
  | RETURN                         { SReturn }
  | NEW lvalue                     { SNew (None, $2) }
  | NEW LBRACKET expr RBRACKET lvalue  { SNew (Some $3, $5) }
  | DISPOSE lvalue                 { SDispose (false, $2) }
  | DISPOSE LBRACKET RBRACKET lvalue   { SDispose (true, $4) }
;

/* Restricted per SPEC.md §5.1: only these forms may be assignment targets,
   by-reference arguments, or new/dispose targets. Everything else (constants,
   calls, unary/binary operator results) can only ever be read, never
   assigned to - kept as a separate rule (rather than folding into expr) so
   that restriction is enforced by the grammar itself, not left to semantic
   analysis to catch later. One exception: "@" (address-of, in expr below)
   takes a general expr rather than lvalue specifically - lvalue there causes
   an unavoidable LALR(1) reduce/reduce conflict with the "expr: lvalue"
   passthrough (ocamlyacc can't tell, at the point of finishing the operand,
   whether it is completing plain "expr: lvalue" or "expr: AT lvalue" without
   more lookahead than it has). So "the operand of @ must actually be an
   lvalue" is one restriction Phase 3 (semantic analysis) has to check instead. */
lvalue:
  ID                        { EId $1 }
  | RESULT                  { EResult }
  | SCONST                  { EString $1 }
  | lvalue LBRACKET expr RBRACKET  { EIndex ($1, $3) }
  | expr CARET               { EDeref $1 }
  | LPAREN lvalue RPAREN     { $2 }
;

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
  | PLUS expr %prec UPLUS    { EUnop (UPlus, $2) }
  | MINUS expr %prec UMINUS  { EUnop (UMinus, $2) }
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
