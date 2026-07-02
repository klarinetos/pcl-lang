(* Phase 1 driver: tokenizes a file and prints the token stream.
   Not the final pclc CLI (docs/SPEC.md §9) — that lands once parsing,
   semantic analysis, and codegen exist. *)

let () =
  if Array.length Sys.argv < 2 then begin
    prerr_endline "usage: pclc <file.pcl>";
    exit 1
  end;
  let filename = Sys.argv.(1) in
  let ic = open_in filename in
  let lexbuf = Lexing.from_channel ic in
  (try
     let rec loop () =
       let tok = Lexer.token lexbuf in
       print_endline (Lexer.string_of_token tok);
       if tok <> Parser.EOF then loop ()
     in
     loop ();
     close_in ic
   with Lexer.Lex_error msg ->
     close_in ic;
     Printf.eprintf "%s: %s\n" filename msg;
     exit 1)
