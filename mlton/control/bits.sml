(* Copyright (C) 2004-2005 Henry Cejtin, Matthew Fluet, Suresh 
 *    Jagannathan, and Stephen Weeks.
 *
 * MLton is released under a BSD-style license.
 * See the file MLton-LICENSE for details.
 *)

local
   type int = Int.t
   type word = Word.t
   structure All:>
      sig
         type bits
         type bytes

         structure Bits:
            sig
               eqtype t

               val + : t * t -> t
               val - : t * t -> t
               val ~ : t -> t
               val < : t * t -> bool
               val <= : t * t -> bool
               val > : t * t -> bool
               val >= : t * t -> bool
               (* val align: t * {alignment: t} -> t *)
               (* val alignWord32: t -> t *)
               (* val alignWord64: t -> t *)
               val compare: t * t -> Relation.t
               val equals: t * t -> bool
               val fromInt: int -> t
               val fromIntInf: IntInf.t -> t
               val inByte: t
               val inWord32: t
               val inWord64: t
               (* val isAligned: t * {alignment: t} -> bool *)
               val isByteAligned: t -> bool
               val isWord32Aligned: t -> bool
               (* val isWord64Aligned: t -> bool *)
               val isZero: t -> bool
               val layout: t -> Layout.t
               val one: t
               val toBytes: t -> bytes
               val toInt: t -> int
               val toIntInf: t -> IntInf.t
               val toString: t -> string
               val toWord: t -> word
               val zero: t
            end

         structure Bytes:
            sig
               type t

               val + : t * t -> t
               val - : t * t -> t
               val ~ : t -> t
               val < : t * t -> bool
               val <= : t * t -> bool
               val > : t * t -> bool
               val >= : t * t -> bool
               val align: t * {alignment: t} -> t
               val alignWord32: t -> t
               val alignWord64: t -> t
               val compare: t * t -> Relation.t
               val equals: t * t -> bool
               val fromInt: int -> t
               val fromIntInf: IntInf.t -> t
               val fromWord: word -> t
               val inWord32: t
               val inWord64: t
               (* val isAligned: t * {alignment: t} -> bool *)
               val isWord32Aligned: t -> bool
               (* val isWord64Aligned: t -> bool *)
               val isZero: t -> bool
               val layout: t -> Layout.t
               val max: t * t -> t
               val one: t
               val toBits: t -> Bits.t
               val toInt: t -> int
               val toIntInf: t -> IntInf.t
               val toString: t -> string
               val toWord: t -> word
               val zero: t
            end

         sharing type bits = Bits.t
         sharing type bytes = Bytes.t
      end =
      struct
         type bits = IntInf.t
         type bytes = IntInf.t

         val rem = IntInf.rem

         fun align (b, {alignment = a}) =
            let
               val b = b + (a - 1)
            in
               b - rem (b, a)
            end

         structure Bits =
            struct
               open IntInf

               val inByte: bits = 8
               val inWord32: bits = 32
               val inWord64: bits = 64

               fun isAligned (b, {alignment = a}) = 0 = rem (b, a)
               fun isByteAligned b = isAligned (b, {alignment = inByte})
               fun isWord32Aligned b = isAligned (b, {alignment = inWord32})
               (* fun isWord64Aligned b = isAligned (b, {alignment = inWord64}) *)

               fun toBytes b =
                  if isByteAligned b
                     then quot (b, inByte)
                  else Error.bug "Bits.toBytes"

               val toWord = Word.fromIntInf

               (* val align = align *)
               (* fun alignWord32 b = align (b, {alignment = inWord32}) *)
               (* fun alignWord64 b = align (b, {alignment = inWord64}) *)
            end

         structure Bytes =
            struct
               open IntInf

               val inWord32: bytes = 4
               val inWord64: bytes = 8

               val fromWord = Word.toIntInf

               fun isAligned (b, {alignment = a}) = 0 = rem (b, a)
               fun isWord32Aligned b = isAligned (b, {alignment = inWord32})
               (* fun isWord64Aligned b = isAligned (b, {alignment = inWord64}) *)

               fun toBits b = b * Bits.inByte

               val toWord = Word.fromIntInf

               val align = align

               fun alignWord32 b = align (b, {alignment = inWord32})
               fun alignWord64 b = align (b, {alignment = inWord64}) 
           end
      end

   open All
in
   structure Bits = Bits
   structure Bytes = Bytes
end
