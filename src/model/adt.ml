
(* This file is free software, part of dolmen. See file "LICENSE" for more information *)

(* Useful shorthand for chaining comparisons *)
let (<?>) = Dolmen.Std.Misc.(<?>)
let lexicographic = Dolmen.Std.Misc.lexicographic


(* Type definitions *)
(* ************************************************************************* *)

module E = Dolmen.Std.Expr
module B = Dolmen.Std.Builtin
module T = Dolmen.Std.Expr.Term
module V = Dolmen.Std.Expr.Term.Var
module C = Dolmen.Std.Expr.Term.Const

exception Not_a_pattern of T.t

type t = {
  head : C.t;
  args : Value.t list;
}

let print fmt { head; args; } =
  match args with
  | [] ->
    Format.fprintf fmt "{%a}" C.print head
  | _ ->
    let pp_sep = Format.pp_print_space in
    Format.fprintf fmt "{%a@ %a}"
      C.print head (Format.pp_print_list ~pp_sep Value.print) args

let compare t t' =
  C.compare t.head t'.head
  <?> (lexicographic Value.compare, t.args, t'.args)

let ops = Value.ops ~print ~compare ()


(* Creating values *)
(* ************************************************************************* *)

let mk head args =
  Value.mk ~ops { head; args; }

let builtins (cst : C.t) =
  match cst.builtin with
  | B.Constructor _ -> Some (Fun.fun_n ~cst (mk cst))
  | _ -> None


(* Pattern matching values *)
(* ************************************************************************* *)

type pat =
  | Var of V.t
  | Cstr of C.t * T.t list

let view_pat (t : T.t) =
  match t.term_descr with
  | Var v -> Var v
  | Cst ( { builtin = B.Constructor _; _ } as cstr )
    -> Cstr (cstr, [])
  | App ({ term_descr = Cst ({
      builtin = B.Constructor _; _ } as cstr); _ }, _, args)
    -> Cstr (cstr, args)
  | Cst _ | App _ | Binder _ | Match _ ->
    raise (Not_a_pattern t)

let rec pattern_match env pat value =
  match view_pat pat with
  | Var pat_var -> Some (Env.Var.add pat_var value env)
  | Cstr (pat_cstr, pat_args) ->
    let v = Value.extract_exn ~ops value in
    if C.equal pat_cstr v.head then
      pattern_match_list env pat_args v.args
    else
      None

and pattern_match_list env pats values =
  match pats, values with
  | [], [] -> Some env
  | pat :: pats, value :: values ->
    begin match pattern_match env pat value with
      | None -> None
      | Some env -> pattern_match_list env pats values
    end
  | [], _ :: _ | _ :: _, [] ->
    (* if we get here, this means that terms were ill-typed *)
    assert false
