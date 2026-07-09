(* pcli - PCL interpreter entry point. Parses a file with the same
   lexer/parser as pclc, then runs the AST directly instead of compiling
   it. Separate executable from pclc (see docs/PROGRESS.md /
   guide/INTERP_WALKTHROUGH.md) - not part of the graded submission
   pipeline described in SPEC.md §9. *)

let () =
  if Array.length Sys.argv < 2 then begin
    prerr_endline "usage: pcli <file.pcl>";
    exit 1
  end;
  let filename = Sys.argv.(1) in
  let ic = open_in filename in
  let lexbuf = Lexing.from_channel ic in
  try
    let ast = Parser.program Lexer.token lexbuf in
    close_in ic;
    Interp.run ast
  with
  | Lexer.Lex_error msg ->
      close_in ic;
      Printf.eprintf "%s: %s\n" filename msg;
      exit 1
  | Parsing.Parse_error ->
      close_in ic;
      Printf.eprintf "%s: line %d: syntax error\n" filename (Lexer.current_line ());
      exit 1
  | Interp.Runtime_error msg ->
      Printf.eprintf "%s: runtime error: %s\n" filename msg;
      exit 1
