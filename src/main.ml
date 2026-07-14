(* Phase 2 driver: parses a file and prints the resulting AST.
   Not the final pclc CLI (docs/SPEC.md §9) — that lands once semantic
   analysis and codegen exist. *)

open Ast

let string_of_typ t =
  let rec go = function
    | TInteger -> "integer"
    | TReal -> "real"
    | TBoolean -> "boolean"
    | TChar -> "char"
    | TArray (None, t) -> "array of " ^ go t
    | TArray (Some n, t) -> Printf.sprintf "array [%d] of %s" n (go t)
    | TPointer t -> "^" ^ go t
  in
  go t

let string_of_unop = function
  | UPlus -> "+"
  | UMinus -> "-"
  | UNot -> "not"

let string_of_binop = function
  | Add -> "+" | Sub -> "-" | Mul -> "*" | Div -> "/" | DivInt -> "div" | Mod -> "mod"
  | Or -> "or" | And -> "and"
  | Eq -> "=" | Neq -> "<>" | Lt -> "<" | Le -> "<=" | Gt -> ">" | Ge -> ">="

let rec string_of_expr = function
  | EInt n -> string_of_int n
  | EReal f -> string_of_float f
  | EChar c -> Printf.sprintf "%C" c
  | EString s -> Printf.sprintf "%S" s
  | EBool b -> string_of_bool b
  | ENil -> "nil"
  | EId s -> s
  | EResult -> "result"
  | EIndex (l, e) -> Printf.sprintf "%s[%s]" (string_of_expr l) (string_of_expr e)
  | EDeref e -> string_of_expr e ^ "^"
  | EAddr e -> "@" ^ string_of_expr e
  | ECall (f, args) ->
      Printf.sprintf "%s(%s)" f (String.concat ", " (List.map string_of_expr args))
  | EUnop (op, e) -> Printf.sprintf "(%s %s)" (string_of_unop op) (string_of_expr e)
  | EBinop (op, a, b) ->
      Printf.sprintf "(%s %s %s)" (string_of_expr a) (string_of_binop op) (string_of_expr b)

let string_of_param p =
  Printf.sprintf "%s%s : %s"
    (if p.by_ref then "var " else "")
    (String.concat ", " p.pnames)
    (string_of_typ p.ptyp)

let string_of_header h =
  let params = String.concat "; " (List.map string_of_param h.hparams) in
  match h.hret with
  | None -> Printf.sprintf "procedure %s (%s)" h.hname params
  | Some t -> Printf.sprintf "function %s (%s) : %s" h.hname params (string_of_typ t)

let rec print_stmt indent s =
  let pad = String.make indent ' ' in
  match s.sdesc with
  | SEmpty -> Printf.printf "%s<empty>\n" pad
  | SAssign (l, e) -> Printf.printf "%s%s := %s\n" pad (string_of_expr l) (string_of_expr e)
  | SBlock stmts ->
      Printf.printf "%sbegin\n" pad;
      List.iter (print_stmt (indent + 2)) stmts;
      Printf.printf "%send\n" pad
  | SCall (f, args) ->
      Printf.printf "%s%s(%s)\n" pad f (String.concat ", " (List.map string_of_expr args))
  | SIf (c, t, e) -> (
      Printf.printf "%sif %s then\n" pad (string_of_expr c);
      print_stmt (indent + 2) t;
      match e with
      | None -> ()
      | Some s ->
          Printf.printf "%selse\n" pad;
          print_stmt (indent + 2) s)
  | SWhile (c, s) ->
      Printf.printf "%swhile %s do\n" pad (string_of_expr c);
      print_stmt (indent + 2) s
  | SLabel (l, s) ->
      Printf.printf "%s%s:\n" pad l;
      print_stmt indent s
  | SGoto l -> Printf.printf "%sgoto %s\n" pad l
  | SReturn -> Printf.printf "%sreturn\n" pad
  | SNew (sz, l) -> (
      match sz with
      | None -> Printf.printf "%snew %s\n" pad (string_of_expr l)
      | Some e -> Printf.printf "%snew [%s] %s\n" pad (string_of_expr e) (string_of_expr l))
  | SDispose (arr, l) ->
      Printf.printf "%sdispose%s %s\n" pad (if arr then " []" else "") (string_of_expr l)

let rec print_local indent l =
  let pad = String.make indent ' ' in
  match l with
  | LVar groups ->
      List.iter
        (fun g ->
          Printf.printf "%svar %s : %s\n" pad (String.concat ", " g.vnames) (string_of_typ g.vtyp))
        groups
  | LLabel (_, names) -> Printf.printf "%slabel %s\n" pad (String.concat ", " names)
  | LForward h -> Printf.printf "%sforward %s\n" pad (string_of_header h)
  | LSub sub ->
      Printf.printf "%s%s\n" pad (string_of_header sub.shdr);
      print_body (indent + 2) sub.sbody

and print_body indent b =
  let pad = String.make indent ' ' in
  List.iter (print_local indent) b.locals;
  Printf.printf "%sbegin\n" pad;
  List.iter (print_stmt (indent + 2)) b.block;
  Printf.printf "%send\n" pad

let print_program p =
  Printf.printf "program %s;\n" p.pname;
  print_body 0 p.pbody

let () =
  if Array.length Sys.argv < 2 then begin
    prerr_endline "usage: pclc <file.pcl>";
    exit 1
  end;
  let filename = Sys.argv.(1) in
  let ic = open_in filename in
  let lexbuf = Lexing.from_channel ic in
  try
    let ast = Parser.program Lexer.token lexbuf in
    close_in ic;
    let errors = Semantic.check_program ast in
    let errors = List.sort (fun a b -> compare a.Semantic.line b.Semantic.line) errors in
    if errors <> [] then begin
      List.iter
        (fun (e : Semantic.error) -> Printf.eprintf "%s: line %d: %s\n" filename e.line e.msg)
        errors;
      exit 1
    end;
    print_program ast
  with
  | Lexer.Lex_error msg ->
      close_in ic;
      Printf.eprintf "%s: %s\n" filename msg;
      exit 1
  | Parsing.Parse_error ->
      close_in ic;
      Printf.eprintf "%s: line %d: syntax error\n" filename (Lexer.current_line ());
      exit 1
