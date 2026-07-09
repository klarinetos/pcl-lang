(* Abstract syntax tree for PCL. Shapes follow docs/SPEC.md sections 3-6. *)

type typ =
  | TInteger
  | TReal
  | TBoolean
  | TChar
  | TArray of int option * typ  (* None = array of t (unsized), Some n = array [n] of t *)
  | TPointer of typ

type unop = UPlus | UMinus | UNot

type binop =
  | Add | Sub | Mul | Div | DivInt | Mod
  | Or | And
  | Eq | Neq | Lt | Le | Gt | Ge

(* One AST type covers both l-value-shaped and r-value-shaped expressions.
   SPEC.md's grammar keeps l-value and r-value as separate nonterminals so
   that, e.g., a bare constant can never be used as an assignment target -
   parser.mly preserves that restriction with a separate "lvalue" grammar
   rule, but both rules build the same OCaml type, since nothing downstream
   needs a different tree shape depending on which side of an assignment an
   expression happened to appear on. *)
type expr =
  | EInt of int
  | EReal of float
  | EChar of char
  | EString of string
  | EBool of bool
  | ENil
  | EId of string
  | EResult
  | EIndex of expr * expr        (* l-value [ e ] *)
  | EDeref of expr               (* e ^ *)
  | EAddr of expr                (* @ l-value *)
  | ECall of string * expr list  (* f(e1, ..., en) *)
  | EUnop of unop * expr
  | EBinop of binop * expr * expr

type stmt =
  | SEmpty
  | SAssign of expr * expr
  | SBlock of stmt list
  | SCall of string * expr list
  | SIf of expr * stmt * stmt option
  | SWhile of expr * stmt
  | SLabel of string * stmt
  | SGoto of string
  | SReturn
  | SNew of expr option * expr      (* size expr (if array form), target l-value *)
  | SDispose of bool * expr         (* true = "dispose []" array form *)

type param = {
  by_ref : bool;
  pnames : string list;
  ptyp : typ;
}

type header = {
  hname : string;
  hparams : param list;
  hret : typ option;  (* None = procedure, Some t = function returning t *)
}

type local =
  | LVar of (string list * typ) list  (* one "var" keyword, one or more name-list : type groups *)
  | LLabel of string list
  | LSub of subprogram
  | LForward of header

and subprogram = { shdr : header; sbody : body }

and body = { locals : local list; block : stmt list }

type program = { pname : string; pbody : body }
