(* Copyright (C) 1999-2005 Henry Cejtin, Matthew Fluet, Suresh
 *    Jagannathan, and Stephen Weeks.
 *
 * MLton is released under a BSD-style license.
 * See the file MLton-LICENSE for details.
 *)

functor Queue(Q: BASIC_QUEUE): QUEUE =
struct

val {error, ...} = Error.errors("queue", "queue")

structure Q' = Sequence(structure I = Integer
                        structure S = Q)

open Q Q'

fun deque q =
   case destruct q of
      SOME xq => xq
    | NONE => error "deque"

end
