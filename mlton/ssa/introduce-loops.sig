(* Copyright (C) 1999-2005 Henry Cejtin, Matthew Fluet, Suresh
 *    Jagannathan, and Stephen Weeks.
 * Copyright (C) 1997-2000 NEC Research Institute.
 *
 * MLton is released under a BSD-style license.
 * See the file MLton-LICENSE for details.
 *)

signature INTRODUCE_LOOPS_STRUCTS = 
   sig
      include SHRINK
   end

signature INTRODUCE_LOOPS = 
   sig
      include INTRODUCE_LOOPS_STRUCTS

      val introduceLoops: Program.t -> Program.t
   end
