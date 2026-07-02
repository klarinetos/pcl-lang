(* Lexer for PCL. Token/lexical rules: docs/SPEC.md §1. *)
{
  open Parser

  exception Lex_error of string

  let line = ref 1

  let error msg = raise (Lex_error (Printf.sprintf "line %d: %s" !line msg))

  let keyword_table : (string, token) Hashtbl.t = Hashtbl.create 32
  let () =
    List.iter
      (fun (kw, tok) -> Hashtbl.add keyword_table kw tok)
      [ "and", AND; "array", ARRAY; "begin", BEGIN; "boolean", BOOLEAN;
        "char", CHAR; "dispose", DISPOSE; "div", DIV; "do", DO;
        "else", ELSE; "end", END; "false", FALSE; "forward", FORWARD;
        "function", FUNCTION; "goto", GOTO; "if", IF; "integer", INTEGER;
        "label", LABEL; "mod", MOD; "new", NEW; "nil", NIL; "not", NOT;
        "of", OF; "or", OR; "procedure", PROCEDURE; "program", PROGRAM;
        "real", REAL; "result", RESULT; "return", RETURN; "then", THEN;
        "true", TRUE; "var", VAR; "while", WHILE ]

  (* c is the character following the backslash in an escape sequence *)
  let escape_char c =
    match c with
    | 'n' -> '\n'
    | 't' -> '\t'
    | 'r' -> '\r'
    | '0' -> '\000'
    | '\\' -> '\\'
    | '\'' -> '\''
    | '"' -> '"'
    | c -> error (Printf.sprintf "invalid escape sequence '\\%c'" c)

  (* Resolve escape sequences in the raw text between a string literal's quotes *)
  let unescape s =
    let buf = Buffer.create (String.length s) in
    let n = String.length s in
    let i = ref 0 in
    while !i < n do
      (if s.[!i] = '\\' then begin
         incr i;
         Buffer.add_char buf (escape_char s.[!i])
       end else
         Buffer.add_char buf s.[!i]);
      incr i
    done;
    Buffer.contents buf

  let string_of_token = function
    | ID s -> Printf.sprintf "ID(%s)" s
    | ICONST n -> Printf.sprintf "ICONST(%d)" n
    | RCONST f -> Printf.sprintf "RCONST(%g)" f
    | CCONST c -> Printf.sprintf "CCONST(%C)" c
    | SCONST s -> Printf.sprintf "SCONST(%S)" s
    | AND -> "AND" | ARRAY -> "ARRAY" | BEGIN -> "BEGIN" | BOOLEAN -> "BOOLEAN"
    | CHAR -> "CHAR" | DISPOSE -> "DISPOSE" | DIV -> "DIV" | DO -> "DO"
    | ELSE -> "ELSE" | END -> "END" | FALSE -> "FALSE" | FORWARD -> "FORWARD"
    | FUNCTION -> "FUNCTION" | GOTO -> "GOTO" | IF -> "IF" | INTEGER -> "INTEGER"
    | LABEL -> "LABEL" | MOD -> "MOD" | NEW -> "NEW" | NIL -> "NIL" | NOT -> "NOT"
    | OF -> "OF" | OR -> "OR" | PROCEDURE -> "PROCEDURE" | PROGRAM -> "PROGRAM"
    | REAL -> "REAL" | RESULT -> "RESULT" | RETURN -> "RETURN" | THEN -> "THEN"
    | TRUE -> "TRUE" | VAR -> "VAR" | WHILE -> "WHILE"
    | EQ -> "EQ" | GT -> "GT" | LT -> "LT" | NE -> "NE" | GE -> "GE" | LE -> "LE"
    | PLUS -> "PLUS" | MINUS -> "MINUS" | TIMES -> "TIMES" | SLASH -> "SLASH"
    | CARET -> "CARET" | AT -> "AT"
    | ASSIGN -> "ASSIGN" | SEMI -> "SEMI" | DOT -> "DOT"
    | LPAREN -> "LPAREN" | RPAREN -> "RPAREN" | COLON -> "COLON"
    | COMMA -> "COMMA" | LBRACKET -> "LBRACKET" | RBRACKET -> "RBRACKET"
    | EOF -> "EOF"
}

let digit = ['0'-'9']
let letter = ['a'-'z' 'A'-'Z']
let id = letter (letter | digit | '_')*
let iconst = digit+
let rconst = digit+ '.' digit+ (['e' 'E'] ['+' '-']? digit+)?
(* common_char: printable characters other than single quote, double quote,
   backslash, and raw newlines. String/char literals cannot span lines, so
   newlines are excluded here rather than allowed through and rejected later *)
let common_char = [^ '\'' '"' '\\' '\n' '\r']
let escape = '\\' ('n' | 't' | 'r' | '0' | '\\' | '\'' | '"')

rule token = parse
  | [' ' '\t' '\r']                          { token lexbuf }
  | '\n'                                      { incr line; token lexbuf }
  | "(*"                                      { comment lexbuf; token lexbuf }
  | id as s
      { match Hashtbl.find_opt keyword_table s with
        | Some tok -> tok
        | None -> ID s }
  | rconst as s                               { RCONST (float_of_string s) }
  | iconst as s                               { ICONST (int_of_string s) }
  | '\'' (common_char as c) '\''              { CCONST c }
  | '\'' (escape as e) '\''                   { CCONST (escape_char e.[1]) }
  | '\'' (common_char | escape)               { error "unterminated character constant" }
  | '"' ((common_char | escape)* as s) '"'    { SCONST (unescape s) }
  | '"' (common_char | escape)*               { error "unterminated string literal" }
  | ":="                                      { ASSIGN }
  | "<>"                                      { NE }
  | ">="                                      { GE }
  | "<="                                      { LE }
  | ";"                                       { SEMI }
  | "."                                       { DOT }
  | "("                                       { LPAREN }
  | ")"                                       { RPAREN }
  | ":"                                       { COLON }
  | ","                                       { COMMA }
  | "["                                       { LBRACKET }
  | "]"                                       { RBRACKET }
  | "="                                       { EQ }
  | ">"                                       { GT }
  | "<"                                       { LT }
  | "+"                                       { PLUS }
  | "-"                                       { MINUS }
  | "*"                                       { TIMES }
  | "/"                                       { SLASH }
  | "^"                                       { CARET }
  | "@"                                       { AT }
  | eof                                       { EOF }
  | _ as c                                    { error (Printf.sprintf "unexpected character '%c'" c) }

and comment = parse
  | "*)"    { () }
  | '\n'    { incr line; comment lexbuf }
  | eof     { error "unterminated comment" }
  | _       { comment lexbuf }

{
  let current_line () = !line
}
