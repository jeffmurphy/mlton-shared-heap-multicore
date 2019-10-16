(* Copyright (C) 1999-2005 Henry Cejtin, Matthew Fluet, Suresh
 *    Jagannathan, and Stephen Weeks.
 * Copyright (C) 1997-2000 NEC Research Institute.
 *
 * MLton is released under a BSD-style license.
 * See the file MLton-LICENSE for details.
 *)

functor Simplify2 (S: SIMPLIFY2_STRUCTS): SIMPLIFY2 = 
struct

open S

(* structure CommonArg = CommonArg (S) *)
(* structure CommonBlock = CommonBlock (S) *)
(* structure CommonSubexp = CommonSubexp (S) *)
(* structure ConstantPropagation = ConstantPropagation (S) *)
(* structure Contify = Contify (S) *)
structure DeepFlatten = DeepFlatten (S)
(* structure Flatten = Flatten (S) *)
(* structure Inline = Inline (S) *)
(* structure IntroduceLoops = IntroduceLoops (S) *)
(* structure KnownCase = KnownCase (S) *)
(* structure LocalFlatten = LocalFlatten (S) *)
(* structure LocalRef = LocalRef (S) *)
(* structure LoopInvariant = LoopInvariant (S) *)
(* structure PolyEqual = PolyEqual (S) *)
structure Profile2 = Profile2 (S)
(* structure Redundant = Redundant (S) *)
(* structure RedundantTests = RedundantTests (S) *)
structure RefFlatten = RefFlatten (S)
structure RemoveUnused2 = RemoveUnused2 (S)
(* structure SimplifyTypes = SimplifyTypes (S) *)
(* structure Useless = Useless (S) *)
structure Zone = Zone (S)

type pass = {name: string,
             doit: Program.t -> Program.t}

val ssa2PassesDefault = 
   {name = "deepFlatten", doit = DeepFlatten.flatten} ::
   {name = "refFlatten", doit = RefFlatten.flatten} ::
   {name = "removeUnused5", doit = RemoveUnused2.remove} ::
   {name = "zone", doit = Zone.zone} ::
   nil

val ssa2PassesMinimal =
   nil

val ssa2Passes : pass list ref = ref ssa2PassesDefault

local
   type passGen = string -> pass option

   fun mkSimplePassGen (name, doit): passGen =
      let val count = Counter.new 1
      in fn s => if s = name
                    then SOME {name = concat [name, "#",
                                              Int.toString (Counter.next count)],
                               doit = doit}
                    else NONE
      end


   val passGens = 
      List.map([("addProfile", Profile2.addProfile),
                ("deepFlatten", DeepFlatten.flatten),
                ("dropProfile", Profile2.dropProfile),
                ("refFlatten", RefFlatten.flatten),
                ("removeUnused", RemoveUnused2.remove), 
                ("zone", Zone.zone),
                ("eliminateDeadBlocks",S.eliminateDeadBlocks),
                ("orderFunctions",S.orderFunctions),
                ("reverseFunctions",S.reverseFunctions),
                ("shrink", S.shrink)],
               mkSimplePassGen)

   fun ssa2PassesSetCustom s =
      Exn.withEscape
      (fn esc =>
       (let val ss = String.split (s, #":")
        in 
           ssa2Passes := 
           List.map(ss, fn s =>
                    case (List.peekMap (passGens, fn gen => gen s)) of
                       NONE => esc (Result.No s)
                     | SOME pass => pass)
           ; Control.ssa2Passes := ss
           ; Result.Yes ()
        end))

   datatype t = datatype Control.optimizationPasses
   fun ssa2PassesSet opt =
      case opt of
         OptPassesDefault => (ssa2Passes := ssa2PassesDefault
                              ; Control.ssa2Passes := ["default"]
                              ; Result.Yes ())
       | OptPassesMinimal => (ssa2Passes := ssa2PassesMinimal
                              ; Control.ssa2Passes := ["minimal"]
                              ; Result.Yes ())
       | OptPassesCustom s => ssa2PassesSetCustom s
in
   val _ = Control.ssa2PassesSet := ssa2PassesSet
   val _ = List.push (Control.optimizationPassesSet, ("ssa2", ssa2PassesSet))
end

fun stats p = Control.message (Control.Detail, fn () => Program.layoutStats p)

fun pass ({name, doit, midfix}, p) =
   let
      val _ =
         let open Control
         in maybeSaveToFile
            ({name = name, 
              suffix = midfix ^ "pre.ssa2"},
             Control.No, p, Control.Layouts Program.layouts)
         end
      val p =
         Control.passTypeCheck
         {name = name,
          suffix = midfix ^ "post.ssa2",
          style = Control.No,
          thunk = fn () => doit p,
          display = Control.Layouts Program.layouts,
          typeCheck = typeCheck}
      val _ = stats p
   in
      p
   end 
fun maybePass ({name, doit, midfix}, p) =
   if List.exists (!Control.dropPasses, fn re =>
                   Regexp.Compiled.matchesAll (re, name))
      then p
   else pass ({name = name, doit = doit, midfix = midfix}, p)

fun simplify p =
   let
      fun simplify' n p =
         let
            val midfix = if n = 0
                            then ""
                         else concat [Int.toString n,"."]
         in
            if n = !Control.loopPasses
               then p
            else simplify' 
                 (n + 1)
                 (List.fold
                  (!ssa2Passes, p, fn ({name, doit}, p) =>
                   maybePass ({name = name, doit = doit, midfix = midfix}, p)))
         end
   in
     stats p
     ; simplify' 0 p
   end

val simplify = fn p => let
                         (* Always want to type check the initial and final SSA 
                          * programs, even if type checking is turned off, just
                          * to catch bugs.
                          *)
                         val _ = typeCheck p
                         val p = simplify p
                         val p =
                            if !Control.profile <> Control.ProfileNone
                               andalso !Control.profileIL = Control.ProfileSSA2
                               then pass ({name = "addProfile2",
                                           doit = Profile2.addProfile,
                                           midfix = ""}, p)
                            else p
                         val p = maybePass ({name = "orderFunctions2",
                                             doit = S.orderFunctions,
                                             midfix = ""}, p)
                         val _ = typeCheck p
                       in
                         p
                       end
end
