(* Tree-walking interpreter for PCL. Runs directly on the Phase 2 AST -
   independent of semantic analysis (Phase 3) and codegen, and independent
   of the still-undecided symbol table design (this is a runtime evaluation
   environment for a different purpose, not a compile-time type checker).
   See guide/INTERP_WALKTHROUGH.md for the full design writeup. *)

open Ast

(* A "cell" is anything addressable: a variable, an array element, a
   dynamically allocated object. Representing all of these uniformly as
   value ref is what lets @ (address-of) and ^ (dereference) work uniformly
   too. *)
type value =
  | VInt of int
  | VReal of float
  | VBool of bool
  | VChar of char
  | VArray of cell array
  | VPtr of cell option (* None = nil *)

and cell = value ref

type proc = {
  pheader : header;
  mutable pbody : body option; (* None only between a forward decl and its real definition *)
  penv : env; (* defining environment - what makes scoping lexical, not dynamic *)
}

and env = {
  vars : (string, cell * typ) Hashtbl.t;
  procs : (string, proc) Hashtbl.t;
  parent : env option;
  result : (cell * typ) option; (* Some only while executing a function body *)
}

exception Return_exc
exception Goto_exc of string
exception Runtime_error of string

let error msg = raise (Runtime_error msg)

(* readString (SPEC.md §8.1) can be asked for fewer characters than remain
   on the current input line, in which case "reading will continue later
   from the point where it stopped." That needs state that outlives any
   single call, hence this module-level buffer of not-yet-consumed input. *)
let pending_line : string option ref = ref None

let next_input_line (max_chars : int) : string =
  let line = match !pending_line with Some l -> l | None -> ( try input_line stdin with End_of_file -> "") in
  if String.length line <= max_chars then (
    pending_line := None;
    line)
  else (
    pending_line := Some (String.sub line max_chars (String.length line - max_chars));
    String.sub line 0 max_chars)

(* ------------------------------------------------------------------ *)
(* Environment lookups: walk the parent chain, same idea as the lexer's
   keyword table but for nested lexical scopes instead of a flat set. *)
(* ------------------------------------------------------------------ *)

let rec lookup_var_entry (env : env) (name : string) : cell * typ =
  match Hashtbl.find_opt env.vars name with
  | Some entry -> entry
  | None -> (
      match env.parent with
      | Some p -> lookup_var_entry p name
      | None -> error (Printf.sprintf "undefined variable %s" name))

let rec lookup_proc (env : env) (name : string) : proc =
  match Hashtbl.find_opt env.procs name with
  | Some p -> p
  | None -> (
      match env.parent with
      | Some p -> lookup_proc p name
      | None -> error (Printf.sprintf "undefined procedure/function %s" name))

let rec lookup_result (env : env) : cell * typ =
  match env.result with
  | Some r -> r
  | None -> (
      match env.parent with
      | Some p -> lookup_result p
      | None -> error "\"result\" used outside a function body")

(* ------------------------------------------------------------------ *)
(* Default values, used to initialize var declarations and new-allocated
   objects, mirroring SPEC.md §2 (a real compiler would leave these
   uninitialized; an interpreter needs *some* concrete starting value). *)
(* ------------------------------------------------------------------ *)

let rec default_value (t : typ) : value =
  match t with
  | TInteger -> VInt 0
  | TReal -> VReal 0.0
  | TBoolean -> VBool false
  | TChar -> VChar '\000'
  | TArray (Some n, elem) -> VArray (Array.init n (fun _ -> ref (default_value elem)))
  | TArray (None, _) -> error "cannot instantiate an unsized array type directly"
  | TPointer _ -> VPtr None

(* ------------------------------------------------------------------ *)
(* Assignment-compatibility coercion (SPEC.md §7): integer widens to real
   when the target expects real. Everything else must already match -
   there is no static type checker here to have caught a mismatch earlier,
   so a genuine type error at this point is a real (if late) error. *)
(* ------------------------------------------------------------------ *)

let coerce_to (target : typ) (v : value) : value =
  match (target, v) with
  | TReal, VInt n -> VReal (float_of_int n)
  | _ -> v

(* ------------------------------------------------------------------ *)
(* lvalue_cell: the address of an expression, for anything SPEC.md §5.1
   allows as an assignment target / by-reference argument / new-dispose
   target. Mirrors parser.mly's "lvalue" grammar rule one-to-one - if a
   new lvalue form is ever added there, it needs a matching case here.
   Deliberately NOT exhaustive over all of Ast.expr: calling this on a
   non-lvalue-shaped node (e.g. EInt) is a bug (should have been rejected
   by the grammar already), so the wildcard case below is a genuine
   internal-error signal, not a normal user-facing runtime error.
   ------------------------------------------------------------------ *)

let rec lvalue_cell (env : env) (e : expr) : cell =
  match e with
  | EId name -> fst (lookup_var_entry env name)
  | EResult -> fst (lookup_result env)
  | EString s ->
      (* Each occurrence gets a fresh backing array - see
         guide/INTERP_WALKTHROUGH.md for why that is a reasonable reading of
         SPEC.md §5.1's "each such l-value corresponds to an array object." *)
      let with_nul = s ^ "\000" in
      ref (VArray (Array.init (String.length with_nul) (fun i -> ref (VChar with_nul.[i]))))
  | EIndex (base, idx) -> (
      match !(lvalue_cell env base) with
      | VArray cells ->
          let i = eval_int env idx in
          if i < 0 || i >= Array.length cells then
            error (Printf.sprintf "array index %d out of bounds (size %d)" i (Array.length cells))
          else cells.(i)
      | _ -> error "indexed value is not an array")
  | EDeref inner -> (
      match eval_expr env inner with
      | VPtr (Some c) -> c
      | VPtr None -> error "dereference of nil pointer"
      | _ -> error "dereference of a non-pointer value")
  | _ -> error "internal error: expression is not an lvalue"

(* ------------------------------------------------------------------ *)
(* type_of_lvalue / type_of_expr: a small, partial type inference, only as
   much as new/dispose actually need (they are the only constructs that
   care what type an object should be, since unlike C's malloc they are
   type-directed). This is NOT semantic analysis - it assumes the program
   is already well-formed and does no checking of its own.
   ------------------------------------------------------------------ *)

and type_of_lvalue (env : env) (e : expr) : typ =
  match e with
  | EId name -> snd (lookup_var_entry env name)
  | EResult -> snd (lookup_result env)
  | EString _ -> TArray (None, TChar)
  | EIndex (base, _) -> (
      match type_of_lvalue env base with
      | TArray (_, elem) -> elem
      | _ -> error "internal error: indexing a non-array type")
  | EDeref inner -> (
      match type_of_expr env inner with
      | TPointer t -> t
      | _ -> error "internal error: dereferencing a non-pointer type")
  | _ -> error "internal error: expression is not an lvalue"

and type_of_expr (env : env) (e : expr) : typ =
  match e with
  | EInt _ -> TInteger
  | EReal _ -> TReal
  | EBool _ -> TBoolean
  | EChar _ -> TChar
  | ENil -> error "internal error: nil has no unique type"
  | EAddr inner -> TPointer (type_of_lvalue env inner)
  | ECall (name, _) -> (
      match (lookup_proc env name).pheader.hret with
      | Some t -> t
      | None -> error "internal error: procedure used where a function was expected")
  | EUnop (_, inner) -> type_of_expr env inner
  | EBinop _ -> error "internal error: type_of_expr on a binop (not needed by new/dispose)"
  | EId _ | EResult | EString _ | EIndex _ | EDeref _ -> type_of_lvalue env e

(* ------------------------------------------------------------------ *)
(* Expression evaluation *)
(* ------------------------------------------------------------------ *)

and eval_expr (env : env) (e : expr) : value =
  match e with
  | EInt n -> VInt n
  | EReal f -> VReal f
  | EChar c -> VChar c
  | EBool b -> VBool b
  | ENil -> VPtr None
  | EString _ | EId _ | EResult | EIndex _ | EDeref _ -> !(lvalue_cell env e)
  | EAddr inner -> VPtr (Some (lvalue_cell env inner))
  | ECall (name, args) -> (
      match call env name args with
      | Some v -> v
      | None -> error (Printf.sprintf "%s is a procedure, not a function" name))
  | EUnop (op, inner) -> eval_unop op (eval_expr env inner)
  (* and/or short-circuit per SPEC.md §4.3: the second operand is not
     evaluated at all once the first alone determines the result. *)
  | EBinop (And, a, b) -> (
      match eval_expr env a with
      | VBool false -> VBool false
      | VBool true -> (
          match eval_expr env b with
          | VBool r -> VBool r
          | _ -> error "and: right operand is not boolean")
      | _ -> error "and: left operand is not boolean")
  | EBinop (Or, a, b) -> (
      match eval_expr env a with
      | VBool true -> VBool true
      | VBool false -> (
          match eval_expr env b with
          | VBool r -> VBool r
          | _ -> error "or: right operand is not boolean")
      | _ -> error "or: left operand is not boolean")
  | EBinop (op, a, b) -> eval_binop op (eval_expr env a) (eval_expr env b)

and eval_int (env : env) (e : expr) : int =
  match eval_expr env e with
  | VInt n -> n
  | _ -> error "expected an integer value"

and eval_unop (op : unop) (v : value) : value =
  match (op, v) with
  | UPlus, (VInt _ | VReal _) -> v
  | UMinus, VInt n -> VInt (-n)
  | UMinus, VReal f -> VReal (-.f)
  | UNot, VBool b -> VBool (not b)
  | _ -> error "unary operator applied to a value of the wrong type"

(* Arithmetic result-type rules per SPEC.md §4.3/§5.3: +,-,* stay integer
   only if both operands are; / is always real; div/mod require both
   integer. Comparisons accept either two arithmetic operands (compared by
   value, promoting integer to real as needed) or two values of the same
   non-array type (compared structurally). *)
and eval_binop (op : binop) (a : value) (b : value) : value =
  let as_real = function VInt n -> float_of_int n | VReal f -> f | _ -> error "expected a number" in
  match (op, a, b) with
  | Add, VInt x, VInt y -> VInt (x + y)
  | Add, _, _ -> VReal (as_real a +. as_real b)
  | Sub, VInt x, VInt y -> VInt (x - y)
  | Sub, _, _ -> VReal (as_real a -. as_real b)
  | Mul, VInt x, VInt y -> VInt (x * y)
  | Mul, _, _ -> VReal (as_real a *. as_real b)
  | Div, _, _ -> VReal (as_real a /. as_real b)
  | DivInt, VInt x, VInt y ->
      if y = 0 then error "division by zero (div)" else VInt (x / y)
  | DivInt, _, _ -> error "div requires integer operands"
  | Mod, VInt x, VInt y ->
      if y = 0 then error "division by zero (mod)" else VInt (x mod y)
  | Mod, _, _ -> error "mod requires integer operands"
  | Eq, _, _ -> VBool (values_equal a b)
  | Neq, _, _ -> VBool (not (values_equal a b))
  | Lt, _, _ -> VBool (as_real a < as_real b)
  | Le, _, _ -> VBool (as_real a <= as_real b)
  | Gt, _, _ -> VBool (as_real a > as_real b)
  | Ge, _, _ -> VBool (as_real a >= as_real b)
  | (Or | And), _, _ -> error "internal error: and/or handled separately for short-circuiting"

and values_equal (a : value) (b : value) : bool =
  match (a, b) with
  | (VInt _ | VReal _), (VInt _ | VReal _) ->
      let f = function VInt n -> float_of_int n | VReal r -> r | _ -> assert false in
      f a = f b
  | VBool x, VBool y -> x = y
  | VChar x, VChar y -> x = y
  | VPtr None, VPtr None -> true
  | VPtr (Some x), VPtr (Some y) -> x == y
  | VPtr _, VPtr _ -> false
  | _ -> error "= / <> require two arithmetic values or two values of the same non-array type"

(* ------------------------------------------------------------------ *)
(* The standard library (SPEC.md §8). Implemented directly here, in the
   same mutually-recursive group as eval_expr/lvalue_cell, rather than as a
   separate module - a separate Builtins module would need to call back
   into eval_expr/lvalue_cell, and Interp would need to call into
   Builtins.find, which is a circular module dependency OCaml does not
   support without extra machinery (functors, first-class modules) that
   would not pull its weight here for what is fundamentally one cohesive
   evaluator. Returns None (outer option) for "not a builtin - keep
   looking," so ordinary user-defined procedures/functions still work.
   Builtin names shadow user declarations of the same name, matching
   SPEC.md §8's "visible ... unless shadowed" - actually the reverse of
   that here, since this check runs BEFORE the user-proc lookup; accepted
   as a minor deviation for an interpreter that is not solving the general
   name-shadowing problem semantic analysis would otherwise handle. *)
(* ------------------------------------------------------------------ *)

and try_builtin (env : env) (name : string) (args : expr list) : value option option =
  let arg n = eval_expr env (List.nth args n) in
  let iarg n = match arg n with VInt i -> i | _ -> error (name ^ ": expected an integer argument") in
  let rarg n = match arg n with VReal r -> r | VInt i -> float_of_int i | _ -> error (name ^ ": expected a real argument") in
  let carg n = match arg n with VChar c -> c | _ -> error (name ^ ": expected a char argument") in
  let barg n = match arg n with VBool b -> b | _ -> error (name ^ ": expected a boolean argument") in
  (* Scans a null-terminated char array cell (a string literal or a
     var/array-of-char argument), calling f on each char before the
     terminator. Shared by writeString and readString. *)
  let char_array_cells arg_expr =
    match !(lvalue_cell env arg_expr) with
    | VArray cells -> cells
    | _ -> error (name ^ ": argument is not a char array")
  in
  match name with
  | "writeInteger" -> print_string (string_of_int (iarg 0));
      Some None
  | "writeBoolean" -> print_string (if barg 0 then "true" else "false");
      Some None
  | "writeChar" -> print_char (carg 0);
      Some None
  | "writeReal" -> print_string (string_of_float (rarg 0));
      Some None
  | "writeString" ->
      let cells = char_array_cells (List.nth args 0) in
      (try
         let i = ref 0 in
         while !(cells.(!i)) <> VChar '\000' do
           (match !(cells.(!i)) with VChar c -> print_char c | _ -> error "writeString: not a char array");
           incr i
         done
       with Invalid_argument _ -> ());
      Some None
  | "readInteger" -> Some (Some (VInt (Scanf.scanf " %d" (fun n -> n))))
  | "readBoolean" -> Some (Some (VBool (Scanf.scanf " %s" (fun s -> s = "true"))))
  | "readChar" -> Some (Some (VChar (Scanf.scanf "%c" (fun c -> c))))
  | "readReal" -> Some (Some (VReal (Scanf.scanf " %f" (fun f -> f))))
  | "readString" ->
      let size = iarg 0 in
      if size < 1 then error "readString: size must be positive";
      let cells = char_array_cells (List.nth args 1) in
      let line = next_input_line (size - 1) in
      let n = String.length line in
      for i = 0 to n - 1 do
        cells.(i) := VChar line.[i]
      done;
      cells.(n) := VChar '\000';
      Some None
  | "abs" -> Some (Some (VInt (abs (iarg 0))))
  | "fabs" -> Some (Some (VReal (Float.abs (rarg 0))))
  | "sqrt" -> Some (Some (VReal (sqrt (rarg 0))))
  | "sin" -> Some (Some (VReal (sin (rarg 0))))
  | "cos" -> Some (Some (VReal (cos (rarg 0))))
  | "tan" -> Some (Some (VReal (tan (rarg 0))))
  | "arctan" -> Some (Some (VReal (atan (rarg 0))))
  | "exp" -> Some (Some (VReal (exp (rarg 0))))
  | "ln" -> Some (Some (VReal (log (rarg 0))))
  | "pi" -> Some (Some (VReal (4.0 *. atan 1.0)))
  | "trunc" -> Some (Some (VInt (int_of_float (Float.trunc (rarg 0)))))
  (* SPEC.md §8.3: ties round away from zero (larger absolute value wins) -
     exactly what OCaml's Float.round already does, unlike languages whose
     default is round-half-to-even. *)
  | "round" -> Some (Some (VInt (int_of_float (Float.round (rarg 0)))))
  | "ord" -> Some (Some (VInt (Char.code (carg 0))))
  | "chr" -> Some (Some (VChar (Char.chr (iarg 0))))
  | _ -> None

(* ------------------------------------------------------------------ *)
(* Calling a procedure or function. Builtins (the standard library) are
   checked first, since they are not declared anywhere in user code for
   this interpreter to have registered a "proc" entry for. *)
(* ------------------------------------------------------------------ *)

and call (env : env) (name : string) (args : expr list) : value option =
  match try_builtin env name args with
  | Some result -> result
  | None ->
      let p = lookup_proc env name in
      let body =
        match p.pbody with
        | Some b -> b
        | None -> error (Printf.sprintf "%s was forward-declared but never defined" name)
      in
      let call_env =
        { vars = Hashtbl.create 16; procs = Hashtbl.create 4; parent = Some p.penv; result = None }
      in
      bind_params env call_env p.pheader.hparams args;
      let call_env =
        match p.pheader.hret with
        | Some t -> { call_env with result = Some (ref (default_value t), t) }
        | None -> call_env
      in
      setup_locals call_env body.locals;
      (try exec_stmts call_env body.block with Return_exc -> ());
      Option.map (fun (cell, _) -> !cell) call_env.result

and bind_params (caller_env : env) (call_env : env) (params : param list) (args : expr list) : unit
    =
  let flat =
    List.concat_map (fun p -> List.map (fun n -> (n, p.by_ref, p.ptyp)) p.pnames) params
  in
  (try List.iter2 (fun (name, by_ref, typ) arg -> bind_one caller_env call_env name by_ref typ arg) flat args
   with Invalid_argument _ -> error "argument count does not match parameter count")

and bind_one caller_env call_env name by_ref typ arg =
  if by_ref then
    let cell = lvalue_cell caller_env arg in
    Hashtbl.replace call_env.vars name (cell, typ)
  else
    let v = coerce_to typ (eval_expr caller_env arg) in
    Hashtbl.replace call_env.vars name (ref v, typ)

(* ------------------------------------------------------------------ *)
(* Registering local declarations into a (freshly created) scope, before
   that scope's statements run. Handles forward declarations by updating
   the existing proc entry in place rather than creating a second one, so
   mutually-recursive procedures see each other correctly - see
   guide/INTERP_WALKTHROUGH.md for the worked example. *)
(* ------------------------------------------------------------------ *)

and setup_locals (env : env) (locals : local list) : unit =
  List.iter
    (fun loc ->
      match loc with
      | LVar groups ->
          List.iter
            (fun (names, t) ->
              List.iter (fun name -> Hashtbl.replace env.vars name (ref (default_value t), t)) names)
            groups
      | LLabel _ -> () (* goto/label resolution happens structurally in exec_stmts, no entry needed *)
      | LForward hdr -> Hashtbl.replace env.procs hdr.hname { pheader = hdr; pbody = None; penv = env }
      | LSub sub -> (
          match Hashtbl.find_opt env.procs sub.shdr.hname with
          | Some existing when existing.pbody = None -> existing.pbody <- Some sub.sbody
          | _ -> Hashtbl.replace env.procs sub.shdr.hname { pheader = sub.shdr; pbody = Some sub.sbody; penv = env }))
    locals

(* ------------------------------------------------------------------ *)
(* Statement execution. exec_stmts (plural) is where goto/label resolution
   actually happens: a Goto_exc raised anywhere inside is caught here, and
   this statement list is searched for a matching label. If found, execution
   resumes from there; if not, the exception is re-raised so an ENCLOSING
   exec_stmts call (a step further out, e.g. the block containing the loop
   this one is nested in) gets a chance to find it instead. This correctly
   handles jumping out of a nested block to a label in an enclosing one
   (the common case - e.g. breaking out of a loop) but will not find a label
   nested inside a DIFFERENT sibling block - see
   guide/INTERP_WALKTHROUGH.md for why that scope was judged acceptable. *)
(* ------------------------------------------------------------------ *)

and exec_stmts (env : env) (stmts : stmt list) : unit =
  let arr = Array.of_list stmts in
  let n = Array.length arr in
  let find_label label =
    let rec go i = if i >= n then None else match arr.(i) with SLabel (l, _) when l = label -> Some i | _ -> go (i + 1) in
    go 0
  in
  let rec run i =
    if i < n then
      match exec_stmt env arr.(i) with
      | () -> run (i + 1)
      | exception Goto_exc label -> (
          match find_label label with
          | Some j -> run j
          | None -> raise (Goto_exc label))
  in
  run 0

and exec_stmt (env : env) (s : stmt) : unit =
  match s with
  | SEmpty -> ()
  | SAssign (lv, e) ->
      let v = eval_expr env e in
      let cell = lvalue_cell env lv in
      let t = type_of_lvalue env lv in
      cell := coerce_to t v
  | SBlock stmts -> exec_stmts env stmts
  | SCall (name, args) -> ignore (call env name args)
  | SIf (c, t, e_opt) -> (
      match eval_expr env c with
      | VBool true -> exec_stmt env t
      | VBool false -> ( match e_opt with Some s -> exec_stmt env s | None -> ())
      | _ -> error "if condition is not boolean")
  | SWhile (c, body) ->
      let rec loop () =
        match eval_expr env c with
        | VBool true ->
            exec_stmt env body;
            loop ()
        | VBool false -> ()
        | _ -> error "while condition is not boolean"
      in
      loop ()
  | SLabel (_, s) -> exec_stmt env s
  | SGoto label -> raise (Goto_exc label)
  | SReturn -> raise Return_exc
  | SNew (size_opt, lv) -> (
      let target = lvalue_cell env lv in
      match (size_opt, type_of_lvalue env lv) with
      | None, TPointer t -> target := VPtr (Some (ref (default_value t)))
      | Some size_e, TPointer (TArray (None, elem)) ->
          let n = eval_int env size_e in
          if n <= 0 then error "new [n]: size must be positive"
          else target := VPtr (Some (ref (VArray (Array.init n (fun _ -> ref (default_value elem))))))
      | _ -> error "internal error: new applied to a non-pointer, or size form mismatched with target type")
  | SDispose (_, lv) ->
      let target = lvalue_cell env lv in
      target := VPtr None

(* ------------------------------------------------------------------ *)
(* Program entry point *)
(* ------------------------------------------------------------------ *)

let run (prog : program) : unit =
  let root = { vars = Hashtbl.create 16; procs = Hashtbl.create 16; parent = None; result = None } in
  setup_locals root prog.pbody.locals;
  try exec_stmts root prog.pbody.block with Return_exc -> ()
