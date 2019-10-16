(* Copyright (C) 2002-2005 Henry Cejtin, Matthew Fluet, Suresh
 *    Jagannathan, and Stephen Weeks.
 *
 * MLton is released under a BSD-style license.
 * See the file MLton-LICENSE for details.
 *)

signature MLTON_INT_INF =
   sig
      type t

      structure BigWord : WORD
      structure SmallInt : INTEGER

      val areSmall: t * t -> bool
      val gcd: t * t -> t
      val isSmall: t -> bool
      datatype rep =
         Big of BigWord.word vector
       | Small of SmallInt.int
      val rep: t -> rep
   end
