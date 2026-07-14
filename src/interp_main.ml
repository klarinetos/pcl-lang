(* pcli - PCL interpreter entry point. Parses a file with the same
   lexer/parser as pclc, runs it through Semantic.check_program (the real
   Phase 3 checker - the same one pclc itself uses), and only then runs
   the AST directly instead of compiling it. Separate executable from
   pclc (see docs/PROGRESS.md / guide/INTERP_WALKTHROUGH.md) - not part of
   the graded submission pipeline described in SPEC.md §9.

   Running the semantic check first, unlike the first interpreter on
   interpreter-phase1-2, is the whole point of this branch: it turns
   "the interpreter ran without crashing" into "the checked AST, the one
   pclc would go on to compile, actually behaves correctly" - real
   end-to-end verification of Phase 3, not just Phases 1-2. *)

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
    let errors = Semantic.check_program ast in
    let errors = List.sort (fun a b -> compare a.Semantic.line b.Semantic.line) errors in
    if errors <> [] then begin
      List.iter
        (fun (e : Semantic.error) -> Printf.eprintf "%s: line %d: %s\n" filename e.line e.msg)
        errors;
      exit 1
    end;
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
