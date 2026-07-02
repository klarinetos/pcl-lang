%{
(* Grammar rules are Phase 2 (Syntactic Analysis) work — see docs/PROGRESS.md.
   For now this file exists only to declare the token type lexer.mll needs;
   the placeholder "program" rule below will be replaced with the real
   grammar (docs/SPEC.md §2.2) in Phase 2. *)
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

%start program
%type <unit> program

%%

program:
  EOF { () }
;
