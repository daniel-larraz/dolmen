(* This file is free software, part of dolmen. See file "LICENSE" for more information *)

module Id = Dolmen.Std.Id
module Ast = Dolmen.Std.Term
module Loc = Dolmen.Std.Loc
module Stmt = Dolmen.Std.Statement

module M = Map.Make(Dolmen.Std.Id)
module S = Set.Make(Dolmen.Std.Id)

(* MCIL transition systems *)
(* ************************************************************************ *)

module MCIL (Type : Tff_intf.S) = struct
  
  type _ Type.err +=
    | Bad_inst_arity : Dolmen.Std.Id.t * int * int -> Dolmen.Std.Loc.t Type.err
    | Cannot_find_system : Dolmen.Std.Id.t -> Dolmen.Std.Loc.t Type.err
    | Duplicate_definition : Dolmen.Std.Id.t * Dolmen.Std.Loc.t -> Dolmen.Std.Loc.t Type.err


  let key = Dolmen.Std.Tag.create ()

  let get_defs env =
    match Type.get_global_custom env key with
    | None -> M.empty
    | Some m -> m

  let define_sys id ((env, _), input, output, local) =
    let map = get_defs env in
    let m = M.add id (`Trans_Sys (input, output, local)) map in
    Type.set_global_custom env key m

  let create_primed_id id =
    match (Id.name id) with
    | Simple name ->
      Id.create (Id.ns id) (Dolmen_std.Name.simple (name ^ "'") )
    | _ -> assert false

  let get_symbol_id = function
    | { Ast.term = Ast.Symbol s; _ } -> s
    | _ -> assert false

  let get_symbol_id_and_loc = function
    | { Ast.term = Ast.Symbol s; loc; _ } -> s, loc
    | _ -> assert false

  let get_app_info = function
    | { Ast.term = Ast.App ({ Ast.term = Ast.Symbol s; loc=s_loc; _}, args); loc=app_loc; _ } ->
      s, s_loc, args, app_loc
    | _ -> assert false

  let parse_def_params (env, env') params =
    let rec aux env env' acc = function
      | [] -> (env, env'), List.rev acc
      | p :: r ->
        let id, v, ast = Type.parse_typed_var_in_binding_pos env p in
        let id' = create_primed_id id in
        let env = Type.add_term_var env id v ast in
        let env' = Type.add_term_var env' id v ast in
        let env' = Type.add_term_var env' id' v ast in
        aux env env' ((id, v, ast) :: acc) r
    in
    aux env env' [] params

  let parse_sig env input output local =
    let envs = env, env in
    let envs, parsed_input  = parse_def_params envs input in
    let envs, parsed_output = parse_def_params envs output in
    let envs, parsed_local  = parse_def_params envs local in
    envs, parsed_input, parsed_output, parsed_local

  let parse_condition env cond =
    Type.parse_prop env cond |> ignore

  let _cannot_find_system env loc id =
    Type._error env (Located loc) (Cannot_find_system id)

  let _bad_inst_arity env loc id e a =
    Type._error env (Located loc) (Bad_inst_arity (id, e, a))

  let _duplicate_definition env loc1 id loc2 =
    let loc1, loc2 =
      if Loc.compare loc1 loc2 < 0 then loc2, loc1 else loc1, loc2
    in
    Type._error env (Located loc1) (Duplicate_definition (id, loc2))

  let ensure env ast t ty =
    Type._wrap2 env ast Type.T.ensure t ty

  let parse_ensure env ast ty =
    let t = Type.parse_term env ast in
    ensure env ast t ty

  let vars l = List.map (fun (_, v, _) -> v) l

  let _bad_arity env s n m t =
    Type._error env (Ast t) (Type.Bad_op_arity (s, [n], m))

  let parse_subsystems env (parent : Stmt.sys_def) =
    let defs = get_defs env in
    List.fold_left
      (fun other_subs (local_name, sub_inst, loc) ->
        (* Make sure local name isn't used twice *)
        match M.find_opt local_name other_subs with
        | Some other_loc ->
          _duplicate_definition env loc local_name other_loc
        | None -> (
          let sub_id, sid_loc, args, inst_loc = get_app_info sub_inst in
          let sub_inputs, sub_outputs =
            match M.find_opt sub_id defs with
            | None ->
                _cannot_find_system env sid_loc sub_id
            | Some (`Trans_Sys (input, output, _)) ->
                (vars input, vars output)
          in
          let num_args = List.length args in
          let params = sub_inputs @ sub_outputs in
          let num_params = List.length params in
          if (num_args != num_params) then (
            _bad_inst_arity env inst_loc sub_id num_params num_args
          ) ;
          List.iter2
            (fun arg param ->
              let expected_type = Type.T.Var.ty param in
              parse_ensure env arg expected_type |> ignore
            )
            args
            params ;
          M.add local_name loc other_subs
        )
      )
      M.empty
      parent.subs
    |> ignore

  let parse_def_body ((env, env'), _input, _output, _local) (d: Stmt.sys_def) =
    parse_condition env d.init ;
    parse_condition env' d.trans ; 
    parse_condition env d.inv ;
    parse_subsystems env d

  let finalize_sys (d : Stmt.sys_def) ((env, _), input, output, local) =
    Type.check_no_free_wildcards env d.init;
    Type.check_no_free_wildcards env d.trans;
    Type.check_no_free_wildcards env d.inv;
    let input, output, local = vars input, vars output, vars local in
    (* TODO: review cases of unused variable *)
    List.iter (Type.check_used_term_var ~kind:`Trans_sys_param env) input ;
    List.iter (Type.check_used_term_var ~kind:`Trans_sys_param env) output ;
    List.iter (Type.check_used_term_var ~kind:`Trans_sys_param env) local ;
    `Sys_def (d.id, input, output, local)

  let parse_def env (d : Stmt.sys_def) =
    let ssig = parse_sig env d.input d.output d.local in
    parse_def_body ssig d ;
    define_sys d.id ssig ;
    finalize_sys d ssig

  let get_sys_sig env sid =
    let defs = get_defs env in
    let id, loc = get_symbol_id_and_loc sid in
    match M.find_opt id defs with
    | None -> _cannot_find_system env loc id
    | Some (`Trans_Sys ssig) -> ssig

  let check_sig (env, env') id sys chk =
    match chk with
    | [] -> (
      List.fold_left
        (fun (env, env') (id, v, ast) ->
          let id' = create_primed_id id in
          let env = Type.add_term_var env id v ast in
          let env' = Type.add_term_var env' id v ast in
          let env' = Type.add_term_var env' id' v ast in
          env, env'
        )
        (env, env')
        sys
    )
    | (_, _, a) :: _ -> (
      let n1 = List.length sys in
      let n2 = List.length chk in
      if (n1 != n2) then _bad_arity env (Id id) n1 n2 a ;
      List.iter2
        (fun (_, v1, _) (_, v2, a2) ->
          ensure env a2 (Type.T.of_var v2) (Type.T.Var.ty v1)
          |> ignore
        )
        sys
        chk ;
      env, env'
    )

  let parse_check_sig env (c : Stmt.sys_check) =
    let sys_input, sys_output, sys_local = get_sys_sig env c.sid in
    let (envs, input, output, local) =
      parse_sig env c.input c.output c.local
    in
    let id = get_symbol_id c.sid in
    let envs = check_sig envs id sys_input input in
    let envs = check_sig envs id sys_output output in
    let envs = check_sig envs id sys_local local in
    envs

  let parse_conditions env ids conds =
    List.fold_left
      (fun acc (id, f, loc) -> 
        match M.find_opt id acc with
        | Some other_loc ->
          _duplicate_definition env loc id other_loc
        | None ->
          parse_condition env f ; M.add id loc acc
      )
      ids
      conds

  let parse_assumptions_and_conditions (_, env') (c : Stmt.sys_check) =
    let cids = parse_conditions env' M.empty c.assumption in
    let cids = parse_conditions env' cids c.reachable in
    cids

  let parse_queries (env,_) cond_ids (c : Stmt.sys_check) =
    let parse_query query_ids (id, conds, loc) =
      match M.find_opt id query_ids with
      | Some old_loc ->
        _duplicate_definition env loc id old_loc
      | None ->
        conds |> List.iter (function
        | { Ast.term = Ast.Symbol s; _ } as ast -> (
          if not (M.mem s cond_ids) then
            Type._error env (Ast ast) (Type.Cannot_find (s, ""));
        )
        | _ -> assert false
        ) ;
        M.add id loc query_ids
    in
    List.fold_left parse_query M.empty c.queries |> ignore

  let parse_check env (c : Stmt.sys_check) =
    let envs = parse_check_sig env c in
    let cids = parse_assumptions_and_conditions envs c in
    parse_queries envs cids c ;
    `Sys_check

end