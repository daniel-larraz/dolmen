
(* This file is free software, part of dolmen. See file "LICENSE" for more information *)

(* Type definition & Exceptions *)
(* ************************************************************************* *)

type perm =
  | Allow
  | Warn
  | Error

exception File_not_found of
    Dolmen.ParseLocation.t option * string * string

exception Input_lang_changed of
    Parser.language * Parser.language

(* Type definition *)
(* ************************************************************************* *)

type lang = Parser.language
type ty_state = Typer.ty_state
type solve_state = unit

type 'solve state = {

  (* Debug option *)
  debug             : bool;
  context           : bool;

  (* Limits for time and size *)
  time_limit        : float;
  size_limit        : float;

  (* Input settings *)
  input_dir         : string;
  input_lang        : lang option;
  input_mode        : [ `Full
                      | `Incremental ] option;
  input_source      : [ `Stdin
                      | `File of string
                      | `Raw of string * string ];

  (* Typechecking state *)
  type_state        : ty_state;
  type_check        : bool;
  type_strict       : bool;

  (* Solving state *)
  solve_state       : 'solve;

  (* Output settings *)
  export_lang       : (lang * Format.formatter) list;

}

type t = solve_state state

(* Warning and error printers *)
(* ************************************************************************* *)

let pp_loc fmt o =
  match o with
  | None -> ()
  | Some loc ->
    Format.fprintf fmt "%a:@ " Dolmen.ParseLocation.fmt loc

let error ?loc _ format =
  Format.kfprintf (fun _ -> exit 1) Format.err_formatter
    ("@[<v>%a%a @[<hov>" ^^ format ^^ "@]@]@.")
    pp_loc loc
    Fmt.(styled `Bold @@ styled (`Fg (`Hi `Red)) string) "Error"

let warn ?loc st format =
  Format.kfprintf (fun _ -> st) Format.err_formatter
    ("@[<v>%a%a @[<hov>" ^^ format ^^ "@]@]@.")
    pp_loc loc
    Fmt.(styled `Bold @@ styled (`Fg (`Hi `Magenta)) string) "Warning"

(* Getting/Setting options *)
(* ************************************************************************* *)

let time_limit t = t.time_limit
let size_limit t = t.size_limit

let input_dir t = t.input_dir
let input_mode t = t.input_mode
let input_lang t = t.input_lang
let input_source t = t.input_source

let set_mode t m = { t with input_mode = Some m; }

let ty_state { type_state; _ } = type_state
let set_ty_state st type_state = { st with type_state; }

let typecheck st = st.type_check
let strict_typing { type_strict; _ } = type_strict

let is_interactive = function
  | { input_source = `Stdin; _ } -> true
  | _ -> false

let prelude _ = "prompt>"

(* Setting language *)
(* ************************************************************************* *)

let set_lang_aux t l =
  let t = { t with input_lang = Some l; } in
  match l with
  | Parser.Alt_ergo ->
    let old_mode = input_mode t in
    let t = set_mode t `Full in
    begin match old_mode with
      | Some `Incremental ->
        warn t
          "The Alt-ergo format does not support incremental mode, switching to full mode"
      | _ -> t
    end
  | _ -> t

let set_lang t l =
  match t.input_lang with
  | None -> set_lang_aux t l
  | Some l' ->
    if l = l'
    then set_lang_aux t l
    else raise (Input_lang_changed (l', l))

(* Full state *)
(* ************************************************************************* *)

let start _ = ()
let stop _ = ()


let file_not_found ?loc ~dir ~file =
  raise (File_not_found (loc, dir, file))

