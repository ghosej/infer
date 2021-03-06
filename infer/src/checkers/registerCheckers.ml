(*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 *)

open! IStd

(** Module for registering checkers. *)

module F = Format

(* make sure SimpleChecker.ml is not dead code *)
let () =
  if false then
    let module SC = SimpleChecker.Make in
    ()


type callback_fun =
  | Procedure of Callbacks.proc_callback_t
  | DynamicDispatch of Callbacks.proc_callback_t
  | File of {callback: Callbacks.file_callback_t; issue_dir: string}

type callback = callback_fun * Language.t

type checker = {name: string; active: bool; callbacks: callback list}

let all_checkers =
  (* TODO (T24393492): the checkers should run in the order from this list.
     Currently, the checkers are run in the reverse order *)
  [ { name= "annotation reachability"
    ; active= Config.annotation_reachability
    ; callbacks=
        [ (Procedure AnnotationReachability.checker, Language.Java)
        ; (Procedure AnnotationReachability.checker, Language.Clang) ] }
  ; { name= "biabduction"
    ; active= Config.biabduction
    ; callbacks=
        [ (DynamicDispatch Interproc.analyze_procedure, Language.Clang)
        ; (DynamicDispatch Interproc.analyze_procedure, Language.Java) ] }
  ; { name= "buffer overrun analysis"
    ; active=
        Config.bufferoverrun || Config.cost || Config.loop_hoisting || Config.purity
        || Config.quandaryBO
    ; callbacks=
        [ (Procedure BufferOverrunAnalysis.do_analysis, Language.Clang)
        ; (Procedure BufferOverrunAnalysis.do_analysis, Language.Java) ] }
  ; { name= "buffer overrun checker"
    ; active= Config.bufferoverrun || Config.quandaryBO
    ; callbacks=
        [ (Procedure BufferOverrunChecker.checker, Language.Clang)
        ; (Procedure BufferOverrunChecker.checker, Language.Java) ] }
  ; { name= "eradicate"
    ; active= Config.eradicate
    ; callbacks= [(Procedure Eradicate.callback_eradicate, Language.Java)] }
  ; { name= "fragment retains view"
    ; active= Config.fragment_retains_view
    ; callbacks=
        [(Procedure FragmentRetainsViewChecker.callback_fragment_retains_view, Language.Java)] }
  ; { name= "immutable cast"
    ; active= Config.immutable_cast
    ; callbacks= [(Procedure ImmutableChecker.callback_check_immutable_cast, Language.Java)] }
  ; { name= "inefficient keyset iterator"
    ; active= Config.inefficient_keyset_iterator
    ; callbacks= [(Procedure InefficientKeysetIterator.checker, Language.Java)] }
  ; { name= "liveness"
    ; active= Config.liveness
    ; callbacks= [(Procedure Liveness.checker, Language.Clang)] }
  ; { name= "printf args"
    ; active= Config.printf_args
    ; callbacks= [(Procedure PrintfArgs.callback_printf_args, Language.Java)] }
  ; { name= "impurity"
    ; active= Config.impurity
    ; callbacks=
        [(Procedure Impurity.checker, Language.Java); (Procedure Impurity.checker, Language.Clang)]
    }
  ; { name= "pulse"
    ; active= Config.pulse || Config.impurity
    ; callbacks=
        (Procedure Pulse.checker, Language.Clang)
        :: (if Config.impurity then [(Procedure Pulse.checker, Language.Java)] else []) }
  ; { name= "quandary"
    ; active= Config.quandary || Config.quandaryBO
    ; callbacks=
        [ (Procedure JavaTaintAnalysis.checker, Language.Java)
        ; (Procedure ClangTaintAnalysis.checker, Language.Clang) ] }
  ; { name= "RacerD"
    ; active= Config.racerd
    ; callbacks=
        [ (Procedure RacerD.analyze_procedure, Language.Clang)
        ; (Procedure RacerD.analyze_procedure, Language.Java)
        ; ( File {callback= RacerD.file_analysis; issue_dir= Config.racerd_issues_dir_name}
          , Language.Clang )
        ; ( File {callback= RacerD.file_analysis; issue_dir= Config.racerd_issues_dir_name}
          , Language.Java ) ] }
    (* toy resource analysis to use in the infer lab, see the lab/ directory *)
  ; { name= "resource leak"
    ; active= Config.resource_leak
    ; callbacks=
        [ ( (* the checked-in version is intraprocedural, but the lab asks to make it
               interprocedural later on *)
            Procedure ResourceLeaks.checker
          , Language.Java ) ] }
  ; { name= "litho-required-props"
    ; active= Config.litho_required_props
    ; callbacks= [(Procedure RequiredProps.checker, Language.Java)] }
  ; {name= "SIOF"; active= Config.siof; callbacks= [(Procedure Siof.checker, Language.Clang)]}
  ; { name= "uninitialized variables"
    ; active= Config.uninit
    ; callbacks= [(Procedure Uninit.checker, Language.Clang)] }
  ; { name= "cost analysis"
    ; active= Config.cost || (Config.loop_hoisting && Config.hoisting_report_only_expensive)
    ; callbacks= [(Procedure Cost.checker, Language.Clang); (Procedure Cost.checker, Language.Java)]
    }
  ; { name= "loop hoisting"
    ; active= Config.loop_hoisting
    ; callbacks=
        [(Procedure Hoisting.checker, Language.Clang); (Procedure Hoisting.checker, Language.Java)]
    }
  ; { name= "Starvation analysis"
    ; active= Config.starvation
    ; callbacks=
        [ (Procedure Starvation.analyze_procedure, Language.Java)
        ; ( File {callback= Starvation.reporting; issue_dir= Config.starvation_issues_dir_name}
          , Language.Java )
        ; (Procedure Starvation.analyze_procedure, Language.Clang)
        ; ( File {callback= Starvation.reporting; issue_dir= Config.starvation_issues_dir_name}
          , Language.Clang ) ] }
  ; { name= "purity"
    ; active= Config.purity || Config.loop_hoisting
    ; callbacks=
        [(Procedure Purity.checker, Language.Java); (Procedure Purity.checker, Language.Clang)] }
  ; { name= "Class loading analysis"
    ; active= Config.class_loads
    ; callbacks= [(Procedure ClassLoads.analyze_procedure, Language.Java)] }
  ; { name= "Self captured in block checker"
    ; active= Config.self_in_block
    ; callbacks= [(Procedure SelfInBlock.checker, Language.Clang)] } ]


let get_active_checkers () =
  let filter_checker {active} = active in
  List.filter ~f:filter_checker all_checkers


let register checkers =
  let register_one {name; callbacks} =
    let register_callback (callback, language) =
      match callback with
      | Procedure procedure_cb ->
          Callbacks.register_procedure_callback ~checker_name:name language procedure_cb
      | DynamicDispatch procedure_cb ->
          Callbacks.register_procedure_callback ~checker_name:name ~dynamic_dispatch:true language
            procedure_cb
      | File {callback; issue_dir} ->
          Callbacks.register_file_callback ~checker_name:name language callback ~issue_dir
    in
    List.iter ~f:register_callback callbacks
  in
  List.iter ~f:register_one checkers


module LanguageSet = Caml.Set.Make (Language)

let pp_checker fmt {name; callbacks} =
  let langs_of_callbacks =
    List.fold_left callbacks ~init:LanguageSet.empty ~f:(fun langs (_, lang) ->
        LanguageSet.add lang langs )
    |> LanguageSet.elements
  in
  F.fprintf fmt "%s (%a)" name
    (Pp.seq ~sep:", " (Pp.of_string ~f:Language.to_string))
    langs_of_callbacks
