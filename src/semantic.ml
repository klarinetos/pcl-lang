(* Phase 3: Semantic Analysis. Single-pass over the AST (docs/IMPLEMENTATION.md),
   collecting every error it finds rather than stopping at the first
   (docs/PROGRESS.md). Rules implemented here are cross-referenced to
   docs/SPEC.md section by section below. *)

open Ast

type error = { line : int; msg : string }

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

(* --- Type well-formedness (SPEC.md §3) ------------------------------- *)

(* well_formed: a legally constructible type, regardless of whether it is
   itself complete (e.g. "array of char" is well-formed but incomplete).
   is_complete: well-formed AND not an unsized array at the top level.
   Mutually recursive because "array element type must be complete" (§3)
   while "pointer target type merely has to be well-formed" (a pointer's
   own size is always 8 bytes regardless of what it points to - §3's size
   table - so ^t is complete as long as t is well-formed, even if t itself
   is incomplete, e.g. ^array of real in SPEC.md §4's f3 example). *)
let rec well_formed t =
  match t with
  | TInteger | TReal | TBoolean | TChar -> true
  | TPointer inner -> well_formed inner
  | TArray (_, elem) -> well_formed elem && is_complete elem

and is_complete t =
  match t with
  | TInteger | TReal | TBoolean | TChar -> true
  | TPointer _ -> well_formed t
  | TArray (None, _) -> false
  | TArray (Some _, _) -> well_formed t

let is_array_typ = function TArray _ -> true | _ -> false

(* --- Assignment compatibility (SPEC.md §7) ---------------------------- *)

(* Not symmetric: every complete type is compatible with itself; integer
   widens to real (not the reverse); ^array [n] of t widens to ^array of t
   (not the reverse). Also doubles as the "^t' compatible with ^t" check
   for by-reference arguments (§5.4) - callers just wrap both sides in
   TPointer first. *)
let assignment_compatible actual formal =
  if actual = formal then true
  else
    match (actual, formal) with
    | TInteger, TReal -> true
    | TPointer (TArray (Some _, t1)), TPointer (TArray (None, t2)) -> t1 = t2
    | _ -> false

(* nil (SPEC.md §5.2) has no fixed type of its own; represent that
   possibility alongside a real Ast.typ everywhere a checked expression's
   type is needed, rather than picking an arbitrary stand-in Ast.typ for it. *)
type sem_typ = Typ of Ast.typ | Nil

let assignment_compatible_sem actual formal =
  match actual with
  | Nil -> ( match formal with TPointer _ -> true | _ -> false)
  | Typ t -> assignment_compatible t formal

(* --- L-value shape (SPEC.md §5.1, parser.mly's note on "@") ----------- *)

(* Everywhere else in the grammar an l-value-only *position* is enforced
   syntactically (the parser's separate "lvalue" rule); "@"'s operand is the
   sole exception, loosened to a general expr to avoid an LALR(1)
   reduce/reduce conflict (see the comment above the lvalue rule in
   parser.mly), so it alone needs a semantic check that its operand is
   actually one of the l-value-shaped constructors. *)
let is_lvalue = function
  | EId _ | EResult | EString _ | EIndex _ | EDeref _ -> true
  | EInt _ | EReal _ | EChar _ | EBool _ | ENil | ECall _ | EUnop _ | EBinop _ | EAddr _ -> false

(* --- Standard library (SPEC.md §8) ------------------------------------ *)

let mk_header name params ret = { hline = 0; hname = name; hparams = params; hret = ret }
let p ?(by_ref = false) names typ = { by_ref; pnames = names; ptyp = typ }

let stdlib_sigs =
  [
    mk_header "writeInteger" [ p [ "n" ] TInteger ] None;
    mk_header "writeBoolean" [ p [ "b" ] TBoolean ] None;
    mk_header "writeChar" [ p [ "c" ] TChar ] None;
    mk_header "writeReal" [ p [ "r" ] TReal ] None;
    mk_header "writeString" [ p ~by_ref:true [ "s" ] (TArray (None, TChar)) ] None;
    mk_header "readInteger" [] (Some TInteger);
    mk_header "readBoolean" [] (Some TBoolean);
    mk_header "readChar" [] (Some TChar);
    mk_header "readReal" [] (Some TReal);
    mk_header "readString"
      [ p [ "size" ] TInteger; p ~by_ref:true [ "s" ] (TArray (None, TChar)) ]
      None;
    mk_header "abs" [ p [ "n" ] TInteger ] (Some TInteger);
    mk_header "fabs" [ p [ "r" ] TReal ] (Some TReal);
    mk_header "sqrt" [ p [ "r" ] TReal ] (Some TReal);
    mk_header "sin" [ p [ "r" ] TReal ] (Some TReal);
    mk_header "cos" [ p [ "r" ] TReal ] (Some TReal);
    mk_header "tan" [ p [ "r" ] TReal ] (Some TReal);
    mk_header "arctan" [ p [ "r" ] TReal ] (Some TReal);
    mk_header "exp" [ p [ "r" ] TReal ] (Some TReal);
    mk_header "ln" [ p [ "r" ] TReal ] (Some TReal);
    mk_header "pi" [] (Some TReal);
    mk_header "trunc" [ p [ "r" ] TReal ] (Some TInteger);
    mk_header "round" [ p [ "r" ] TReal ] (Some TInteger);
    mk_header "ord" [ p [ "c" ] TChar ] (Some TInteger);
    mk_header "chr" [ p [ "n" ] TInteger ] (Some TChar);
  ]

(* --- Main pass ---------------------------------------------------------- *)

let check_program (prog : Ast.program) : error list =
  let errors = ref [] in
  let report line msg = errors := { line; msg } :: !errors in

  let st = Symtab.create () in

  (* flatten a header's ((names, by_ref, type) list) grouped-by-comma
     parameter list into one entry per formal, in declaration order *)
  let flat_params hdr =
    List.concat_map (fun pm -> List.map (fun n -> (n, pm.by_ref, pm.ptyp)) pm.pnames) hdr.hparams
  in

  let headers_match h1 h2 =
    h1.hret = h2.hret
    &&
    let f1 = flat_params h1 and f2 = flat_params h2 in
    List.length f1 = List.length f2
    && List.for_all2 (fun (_, br1, t1) (_, br2, t2) -> br1 = br2 && t1 = t2) f1 f2
  in

  let rec check_positive_sizes line t =
    match t with
    | TArray (sz, elem) ->
        (match sz with
        | Some n when n <= 0 -> report line "array size must be a positive integer constant"
        | _ -> ());
        check_positive_sizes line elem
    | TPointer inner -> check_positive_sizes line inner
    | TInteger | TReal | TBoolean | TChar -> ()
  in

  (* Validates one already-parsed typ occurring in a declaration (var group,
     formal parameter, or return type) and reports every problem found in
     it (bad array sizes, incomplete element types, etc.) - SPEC.md §3. *)
  let check_var_type line t =
    check_positive_sizes line t;
    if not (is_complete t) then
      report line (Printf.sprintf "variable type must be complete, got '%s'" (string_of_typ t))
  in

  let check_header_types hdr =
    List.iter
      (fun pm ->
        check_positive_sizes hdr.hline pm.ptyp;
        if pm.by_ref then begin
          if not (well_formed pm.ptyp) then
            report hdr.hline
              (Printf.sprintf "parameter type '%s' is not a valid type" (string_of_typ pm.ptyp))
        end
        else begin
          match pm.ptyp with
          | TArray _ ->
              report hdr.hline
                (Printf.sprintf
                   "by-value parameter '%s' cannot have an array type (pass by 'var' instead)"
                   (String.concat ", " pm.pnames))
          | t ->
              if not (is_complete t) then
                report hdr.hline
                  (Printf.sprintf "by-value parameter type '%s' must be complete"
                     (string_of_typ t))
        end)
      hdr.hparams;
    match hdr.hret with
    | None -> ()
    | Some (TArray _ as t) ->
        report hdr.hline
          (Printf.sprintf "function '%s' cannot return an array type (got '%s')" hdr.hname
             (string_of_typ t))
    | Some t ->
        check_positive_sizes hdr.hline t;
        if not (is_complete t) then
          report hdr.hline
            (Printf.sprintf "return type '%s' of function '%s' must be complete"
               (string_of_typ t) hdr.hname)
  in

  let require_typ line ctx = function
    | Typ t -> t
    | Nil ->
        report line (Printf.sprintf "%s: 'nil' is not valid here" ctx);
        TInteger
  in

  let arith_result ta tb =
    match (ta, tb) with
    | Typ TInteger, Typ TInteger -> Some TInteger
    | Typ (TInteger | TReal), Typ (TInteger | TReal) -> Some TReal
    | _ -> None
  in

  let comparable_eq ta tb =
    match (ta, tb) with
    | Typ (TInteger | TReal), Typ (TInteger | TReal) -> true
    | Nil, Nil -> true
    | Nil, Typ (TPointer _) | Typ (TPointer _), Nil -> true
    | Typ t1, Typ t2 -> t1 = t2 && not (is_array_typ t1)
    | _ -> false
  in

  let rec type_of_expr line cur_ret (e : expr) : sem_typ =
    match e with
    | EInt _ -> Typ TInteger
    | EReal _ -> Typ TReal
    | EChar _ -> Typ TChar
    | EBool _ -> Typ TBoolean
    | EString s -> Typ (TArray (Some (String.length s + 1), TChar))
    | ENil -> Nil
    | EId name -> (
        match Symtab.lookup st name with
        | Some (Symtab.EVar t) | Some (Symtab.EParam (_, t)) -> Typ t
        | Some (Symtab.ESub _) ->
            report line
              (Printf.sprintf "'%s' is a procedure/function, not a value" name);
            Typ TInteger
        | None ->
            report line (Printf.sprintf "undefined identifier '%s'" name);
            Typ TInteger)
    | EResult -> (
        match cur_ret with
        | Some t -> Typ t
        | None ->
            report line "'result' used outside a function body";
            Typ TInteger)
    | EIndex (l, idx) ->
        let lt = type_of_expr line cur_ret l in
        let it = type_of_expr line cur_ret idx in
        (match it with
        | Typ TInteger -> ()
        | _ -> report line "array index must be of type integer");
        (match lt with
        | Typ (TArray (_, elem)) -> Typ elem
        | Typ other ->
            report line
              (Printf.sprintf "cannot index into non-array type '%s'" (string_of_typ other));
            Typ TInteger
        | Nil ->
            report line "cannot index into 'nil'";
            Typ TInteger)
    | EDeref e' -> (
        match type_of_expr line cur_ret e' with
        | Typ (TPointer inner) -> Typ inner
        | Typ other ->
            report line
              (Printf.sprintf "cannot dereference non-pointer type '%s'" (string_of_typ other));
            Typ TInteger
        | Nil ->
            report line "cannot dereference 'nil'";
            Typ TInteger)
    | EAddr e' ->
        if not (is_lvalue e') then report line "operand of '@' must be an l-value";
        let t = type_of_expr line cur_ret e' in
        (match t with
        | Typ inner -> Typ (TPointer inner)
        | Nil ->
            report line "cannot take the address of 'nil'";
            Typ (TPointer TInteger))
    | ECall (name, args) -> check_call line cur_ret name args ~want_value:true
    | EUnop (UNot, a) ->
        let ta = require_typ line "operand of 'not'" (type_of_expr line cur_ret a) in
        if ta <> TBoolean then report line "operand of 'not' must be boolean";
        Typ TBoolean
    | EUnop ((UPlus | UMinus), a) -> (
        let ta = require_typ line "operand of unary +/-" (type_of_expr line cur_ret a) in
        match ta with
        | TInteger | TReal -> Typ ta
        | _ ->
            report line "operand of unary +/- must be arithmetic (integer/real)";
            Typ TInteger)
    | EBinop (op, a, b) -> type_of_binop line cur_ret op a b

  and type_of_binop line cur_ret op a b =
    let ta = type_of_expr line cur_ret a in
    let tb = type_of_expr line cur_ret b in
    match op with
    | Add | Sub | Mul -> (
        match arith_result ta tb with
        | Some t -> Typ t
        | None ->
            report line "operands must be arithmetic (integer/real)";
            Typ TInteger)
    | Div -> (
        match (ta, tb) with
        | Typ (TInteger | TReal), Typ (TInteger | TReal) -> Typ TReal
        | _ ->
            report line "operands of '/' must be arithmetic (integer/real)";
            Typ TReal)
    | DivInt | Mod -> (
        match (ta, tb) with
        | Typ TInteger, Typ TInteger -> Typ TInteger
        | _ ->
            report line "operands of 'div'/'mod' must both be integer";
            Typ TInteger)
    | Or | And -> (
        match (ta, tb) with
        | Typ TBoolean, Typ TBoolean -> Typ TBoolean
        | _ ->
            report line "operands of 'and'/'or' must both be boolean";
            Typ TBoolean)
    | Eq | Neq ->
        if comparable_eq ta tb then Typ TBoolean
        else begin
          report line "operands of '=' / '<>' must be arithmetic, or the same non-array type";
          Typ TBoolean
        end
    | Lt | Le | Gt | Ge -> (
        match (ta, tb) with
        | Typ (TInteger | TReal), Typ (TInteger | TReal) -> Typ TBoolean
        | _ ->
            report line "operands of a relational operator must be arithmetic (integer/real)";
            Typ TBoolean)

  (* Shared between a call used as a statement (SCall, want_value = false)
     and a call used as an expression (ECall, want_value = true) - SPEC.md
     §5.4. *)
  and check_call line cur_ret name args ~want_value : sem_typ =
    match Symtab.lookup st name with
    | None ->
        report line (Printf.sprintf "undefined procedure/function '%s'" name);
        List.iter (fun a -> ignore (type_of_expr line cur_ret a)) args;
        Typ TInteger
    | Some (Symtab.EVar _ | Symtab.EParam _) ->
        report line (Printf.sprintf "'%s' is a variable, not a procedure/function" name);
        List.iter (fun a -> ignore (type_of_expr line cur_ret a)) args;
        Typ TInteger
    | Some (Symtab.ESub (hdr, _)) ->
        if want_value && hdr.hret = None then
          report line (Printf.sprintf "'%s' is a procedure and does not return a value" name);
        let formals = flat_params hdr in
        let nf = List.length formals and na = List.length args in
        if nf <> na then
          report line
            (Printf.sprintf "'%s' expects %d argument%s, got %d" name nf
               (if nf = 1 then "" else "s")
               na);
        List.iteri
          (fun i a ->
            if i < nf then begin
              let _, by_ref, ftyp = List.nth formals i in
              let at = type_of_expr line cur_ret a in
              if by_ref then begin
                if not (is_lvalue a) then
                  report line
                    (Printf.sprintf "argument %d of '%s' must be an l-value (passed by 'var')"
                       (i + 1) name)
                else
                  let at_t = match at with Typ t -> t | Nil -> TInteger in
                  if not (assignment_compatible (TPointer at_t) (TPointer ftyp)) then
                    report line
                      (Printf.sprintf "argument %d of '%s': type '%s' is not compatible with 'var %s'"
                         (i + 1) name (string_of_typ at_t) (string_of_typ ftyp))
              end
              else if not (assignment_compatible_sem at ftyp) then
                report line
                  (Printf.sprintf "argument %d of '%s': type mismatch (expected '%s')" (i + 1)
                     name (string_of_typ ftyp))
            end
            else ignore (type_of_expr line cur_ret a))
          args;
        (match hdr.hret with Some t -> Typ t | None -> Typ TInteger)
  in

  let declare_label line name =
    let labels = Symtab.current_labels st in
    if Hashtbl.mem labels name then
      report line (Printf.sprintf "duplicate label declaration '%s'" name)
    else Hashtbl.add labels name (line, ref false)
  in

  let define_label line name =
    match Hashtbl.find_opt (Symtab.current_labels st) name with
    | None ->
        report line
          (Printf.sprintf "label '%s' is not declared in this unit's label section" name)
    | Some (_, defined) ->
        if !defined then report line (Printf.sprintf "label '%s' is defined more than once" name)
        else defined := true
  in

  let check_goto line name =
    if not (Hashtbl.mem (Symtab.current_labels st) name) then
      report line
        (Printf.sprintf
           "goto references undeclared label '%s' (a label is only visible in its own structural unit)"
           name)
  in

  let check_labels_defined () =
    Hashtbl.iter
      (fun name (decl_line, defined) ->
        if not !defined then
          report decl_line (Printf.sprintf "label '%s' is declared but never defined" name))
      (Symtab.current_labels st)
  in

  let check_forwards_defined () =
    Hashtbl.iter
      (fun _ entry ->
        match entry with
        | Symtab.ESub (hdr, defined) when not !defined ->
            report hdr.hline
              (Printf.sprintf
                 "'forward procedure/function %s' is never given a matching definition"
                 hdr.hname)
        | _ -> ())
      (Symtab.current_vars st)
  in

  let rec check_stmt cur_ret (s : Ast.stmt) =
    let line = s.sline in
    match s.sdesc with
    | SEmpty -> ()
    | SAssign (l, e) ->
        if not (is_lvalue l) then report line "left-hand side of ':=' must be an l-value";
        let lt = type_of_expr line cur_ret l in
        let et = type_of_expr line cur_ret e in
        (match lt with
        | Typ lt' ->
            if not (assignment_compatible_sem et lt') then
              report line "right-hand side is not assignment-compatible with the left-hand side"
        | Nil -> report line "cannot assign to 'nil'")
    | SBlock stmts -> List.iter (check_stmt cur_ret) stmts
    | SCall (name, args) -> ignore (check_call line cur_ret name args ~want_value:false)
    | SIf (c, t, e) ->
        (match type_of_expr line cur_ret c with
        | Typ TBoolean -> ()
        | _ -> report line "'if' condition must be boolean");
        check_stmt cur_ret t;
        Option.iter (check_stmt cur_ret) e
    | SWhile (c, s') ->
        (match type_of_expr line cur_ret c with
        | Typ TBoolean -> ()
        | _ -> report line "'while' condition must be boolean");
        check_stmt cur_ret s'
    | SLabel (name, s') ->
        define_label line name;
        check_stmt cur_ret s'
    | SGoto name -> check_goto line name
    | SReturn -> ()
    | SNew (size_opt, l) ->
        if not (is_lvalue l) then report line "'new' target must be an l-value"
        else begin
          let lt = type_of_expr line cur_ret l in
          match (size_opt, lt) with
          | None, Typ (TPointer t) ->
              if not (is_complete t) then
                report line
                  (Printf.sprintf "'new' target's pointee type '%s' must be complete"
                     (string_of_typ t))
          | None, Typ other ->
              report line
                (Printf.sprintf "'new' target must be a pointer, got '%s'" (string_of_typ other))
          | None, Nil -> report line "'new' target must be a pointer l-value, not 'nil'"
          | Some e, Typ (TPointer (TArray (None, _))) -> (
              match type_of_expr line cur_ret e with
              | Typ TInteger -> ()
              | _ -> report line "'new [size]' size must be an integer expression")
          | Some _, Typ (TPointer (TArray (Some _, _))) ->
              report line
                "'new [size]' target must point to an unsized array type (use 'new' without \
                 brackets for a fixed-size element)"
          | Some _, Typ other ->
              report line
                (Printf.sprintf "'new [size]' target must be a pointer to an array, got '%s'"
                   (string_of_typ other))
          | Some _, Nil -> report line "'new [size]' target must be a pointer l-value, not 'nil'"
        end
    | SDispose (is_arr, l) ->
        if not (is_lvalue l) then report line "'dispose' target must be an l-value"
        else begin
          let lt = type_of_expr line cur_ret l in
          match (is_arr, lt) with
          | false, Typ (TPointer t) ->
              if not (is_complete t) then
                report line
                  (Printf.sprintf "'dispose' target's pointee type '%s' must be complete"
                     (string_of_typ t))
          | false, Typ other ->
              report line
                (Printf.sprintf "'dispose' target must be a pointer, got '%s'"
                   (string_of_typ other))
          | false, Nil -> report line "'dispose' target must be a pointer l-value, not 'nil'"
          | true, Typ (TPointer (TArray (None, _))) -> ()
          | true, Typ other ->
              report line
                (Printf.sprintf
                   "'dispose []' target must be a pointer to an (unsized) array, got '%s'"
                   (string_of_typ other))
          | true, Nil -> report line "'dispose []' target must be a pointer l-value, not 'nil'"
        end
  in

  let rec check_local cur_ret = function
    | LVar groups -> List.iter check_var_group groups
    | LLabel (line, names) -> List.iter (declare_label line) names
    | LForward hdr ->
        check_header_types hdr;
        if not (Symtab.declare st hdr.hname (Symtab.ESub (hdr, ref false))) then
          report hdr.hline (Printf.sprintf "duplicate declaration of '%s' in this scope" hdr.hname)
    | LSub sub -> declare_and_check_sub sub

  and check_var_group g =
    check_var_type g.vline g.vtyp;
    List.iter
      (fun name ->
        if not (Symtab.declare st name (Symtab.EVar g.vtyp)) then
          report g.vline (Printf.sprintf "duplicate declaration of '%s' in this scope" name))
      g.vnames

  and declare_and_check_sub (sub : Ast.subprogram) =
    let hdr = sub.shdr in
    check_header_types hdr;
    (match Symtab.lookup_local st hdr.hname with
    | Some (Symtab.ESub (fhdr, defined)) when not !defined ->
        if headers_match fhdr hdr then defined := true
        else
          report hdr.hline
            (Printf.sprintf "definition of '%s' does not match its forward declaration"
               hdr.hname)
    | Some _ ->
        report hdr.hline (Printf.sprintf "duplicate declaration of '%s' in this scope" hdr.hname)
    | None -> ignore (Symtab.declare st hdr.hname (Symtab.ESub (hdr, ref true))));
    Symtab.push_scope st;
    List.iter
      (fun pm ->
        List.iter
          (fun name ->
            if not (Symtab.declare st name (Symtab.EParam (pm.by_ref, pm.ptyp))) then
              report hdr.hline (Printf.sprintf "duplicate parameter name '%s'" name))
          pm.pnames)
      hdr.hparams;
    check_body sub.sbody hdr.hret;
    Symtab.pop_scope st

  and check_body (body : Ast.body) (cur_ret : Ast.typ option) =
    List.iter (check_local cur_ret) body.locals;
    List.iter (check_stmt cur_ret) body.block;
    check_labels_defined ();
    check_forwards_defined ()
  in

  Symtab.push_scope st;
  (* stdlib / global scope, SPEC.md §8: visible in every unit unless shadowed *)
  List.iter
    (fun hdr -> ignore (Symtab.declare st hdr.hname (Symtab.ESub (hdr, ref true))))
    stdlib_sigs;
  Symtab.push_scope st;
  (* the main program's own structural unit *)
  check_body prog.pbody None;
  Symtab.pop_scope st;
  Symtab.pop_scope st;
  List.rev !errors
