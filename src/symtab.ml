(* Symbol table for Phase 3 (semantic analysis). Design chosen with the user
   (see docs/SPEC.md §4's note and docs/PROGRESS.md): a mutable stack of hash
   tables, one per open lexical scope. push_scope/pop_scope enter and leave a
   scope (a program or subprogram's own structural unit); lookup walks the
   stack innermost-to-outermost, which gives Pascal-style shadowing for free.

   Only the fields Phase 3 itself needs are tracked - no storage/offset
   information for later codegen phases; that gets added when Phase 4/6
   actually need it.

   Labels are a separate namespace from variables/parameters/subprograms
   (as in ISO Pascal) and, per docs/SPEC.md §6, a goto may only target a
   label declared in the *same* structural unit - never an enclosing one.
   So label lookups only ever look at the innermost frame, never walk
   outward the way variable/subprogram lookups do; keeping them in their
   own per-frame table (rather than in Symtab's usual entry type) makes
   that restriction the natural behavior instead of a special case. *)

type entry =
  | EVar of Ast.typ
  | EParam of bool * Ast.typ (* by_ref, type *)
  | ESub of Ast.header * bool ref (* header; ref is true once a matching body has been given *)

(* int = the line the label was declared on (for an "never defined" error);
   bool ref = whether a "name: stmt" definition for it has been seen yet. *)
type label_entry = int * bool ref

type frame = {
  vars : (string, entry) Hashtbl.t;
  labels : (string, label_entry) Hashtbl.t;
}

type t = frame list ref

let create () : t = ref []

let push_scope (t : t) =
  t := { vars = Hashtbl.create 16; labels = Hashtbl.create 4 } :: !t

let pop_scope (t : t) =
  match !t with
  | [] -> failwith "Symtab.pop_scope: no open scope"
  | _ :: rest -> t := rest

let current_frame (t : t) =
  match !t with
  | [] -> failwith "Symtab.current_frame: no open scope"
  | f :: _ -> f

let current_vars (t : t) = (current_frame t).vars
let current_labels (t : t) = (current_frame t).labels

(* Declares [name] in the innermost scope. Returns [false] (and declares
   nothing) if [name] is already declared in that same scope - the caller is
   responsible for reporting the duplicate-declaration error, since only it
   knows the source line to blame. *)
let declare (t : t) (name : string) (e : entry) : bool =
  let vars = current_vars t in
  if Hashtbl.mem vars name then false
  else begin
    Hashtbl.add vars name e;
    true
  end

(* Innermost-to-outermost search, as Pascal's nested-scope shadowing requires. *)
let lookup (t : t) (name : string) : entry option =
  let rec go = function
    | [] -> None
    | f :: rest -> (
        match Hashtbl.find_opt f.vars name with
        | Some _ as found -> found
        | None -> go rest)
  in
  go !t

(* Restricted to the current (innermost) scope - used for duplicate-decl checks. *)
let lookup_local (t : t) (name : string) : entry option =
  Hashtbl.find_opt (current_vars t) name
