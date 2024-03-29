(* Copyright (C) 2004-2005 Henry Cejtin, Matthew Fluet, Suresh
 *    Jagannathan, and Stephen Weeks.
 *
 * MLton is released under a BSD-style license.
 * See the file MLton-LICENSE for details.
 *)

functor RepType (S: REP_TYPE_STRUCTS): REP_TYPE =
struct

open S

structure CFunction = CFunction

type int = Int.t

structure Type =
   struct
      datatype t = T of {node: node,
                         width: Bits.t}
      and node =
          Bits
        | CPointer
        | ExnStack
        | GCState
        | Label of Label.t
        | Objptr of ObjptrTycon.t vector
        | Real of RealSize.t
        | Seq of t vector
        | Word of WordSize.t

      local
         fun make f (T r) = f r
      in
         val node = make #node
         val width = make #width
      end
      val bytes: t -> Bytes.t = Bits.toBytes o width

      val rec layout: t -> Layout.t =
         fn t =>
         let
            open Layout
         in
            case node t of
               Bits => str (concat ["Bits", Bits.toString (width t)])
             | CPointer => str "CPointer"
             | ExnStack => str "ExnStack"
             | GCState => str "GCState"
             | Label l => seq [str "Label ", Label.layout l]
             | Objptr opts =>
                  seq [str "Objptr ",
                       tuple (Vector.toListMap (opts, ObjptrTycon.layout))]
             | Real s => str (concat ["Real", RealSize.toString s])
             | Seq ts => List.layout layout (Vector.toList ts)
             | Word s => str (concat ["Word", WordSize.toString s])
         end

      val rec equals: t * t -> bool =
         fn (t, t') =>
         Bits.equals (width t, width t')
         andalso
         (case (node t, node t') of
             (Bits, Bits) => true 
           | (CPointer, CPointer) => true
           | (ExnStack, ExnStack) => true
           | (GCState, GCState) => true
           | (Label l, Label l') => Label.equals (l, l')
           | (Objptr opts, Objptr opts') =>
                Vector.equals (opts, opts', ObjptrTycon.equals)
           | (Real s, Real s') => RealSize.equals (s, s')
           | (Seq ts, Seq ts') => Vector.equals (ts, ts', equals)
           | (Word s, Word s') => WordSize.equals (s, s')
           | _ => false)

      val sameWidth: t * t -> bool =
         fn (t, t') => Bits.equals (width t, width t')


      val bits: Bits.t -> t = fn width => T {node = Bits, width = width}

      val cpointer: unit -> t = fn () =>
         T {node = CPointer, width = WordSize.bits (WordSize.cpointer ())}

      val exnStack: unit -> t = fn () => 
         T {node = ExnStack, width = WordSize.bits (WordSize.csize ())}

      val gcState: unit -> t = fn () => 
         T {node = GCState, width = WordSize.bits (WordSize.cpointer ())}

      val label: Label.t -> t =
         fn l => T {node = Label l, width = WordSize.bits (WordSize.cpointer ())}

      val objptr: ObjptrTycon.t -> t =
         fn opt => T {node = Objptr (Vector.new1 opt),
                      width = WordSize.bits (WordSize.objptr ())}

      val real: RealSize.t -> t =
         fn s => T {node = Real s, width = RealSize.bits s}
 
      val word: WordSize.t -> t = 
         fn s => T {node = Word s, width = WordSize.bits s}


      val bool: t = word WordSize.bool

      val csize: unit -> t = word o WordSize.csize

      val cint: unit -> t = word o WordSize.cint

      val objptrHeader: unit -> t = word o WordSize.objptrHeader

      val seqIndex: unit -> t = word o WordSize.seqIndex

      val shiftArg: t = word WordSize.shiftArg

      val stack : unit -> t = fn () => 
         objptr ObjptrTycon.stack

      val thread : unit -> t = fn () => 
         objptr ObjptrTycon.thread

      val word0: t = bits Bits.zero
      val word8: t = word WordSize.word8
      val word32: t = word WordSize.word32

      val wordVector: WordSize.t -> t = 
         objptr o ObjptrTycon.wordVector o WordSize.bits

      val word8Vector: unit -> t =  fn () => 
         wordVector WordSize.word8

      val string: unit -> t = word8Vector

      val unit: t = bits Bits.zero

      val zero: Bits.t -> t = bits


      val ofWordX: WordX.t -> t = 
         fn w => word (WordX.size w)

      fun ofWordXVector (v: WordXVector.t): t =
         wordVector (WordXVector.elementSize v)


      val seq: t vector -> t =
         fn ts =>
         if 0 = Vector.length ts
            then unit
         else
            let
               fun seqOnto (ts, ac) =
                  Vector.foldr
                  (ts, ac, fn (t, ac) =>
                   if Bits.equals (width t, Bits.zero)
                      then ac
                   else (case node t of
                            Seq ts => seqOnto (ts, ac)
                          | _ => (case ac of
                                     [] => [t]
                                   | t' :: ac' =>
                                        (case (node t, node t') of
                                            (Bits, Bits) => 
                                               bits (Bits.+ (width t, width t')) :: ac'
                                          | _ => t :: ac))))
            in
               case seqOnto (ts, []) of
                  [] => word0
                | [t] => t
                | ts =>
                     let
                        val ts = Vector.fromList ts
                     in
                        T {node = Seq ts,
                           width = Vector.fold (ts, Bits.zero, fn (t, ac) =>
                                                Bits.+ (ac, width t))}
                     end
            end

      val seq = Trace.trace ("RepType.Type.seq", Vector.layout layout, layout) seq

      val sum: t vector -> t =
         fn ts =>
         if 0 = Vector.length ts
            then Error.bug "RepType.Type.sum: empty"
         else
            let
               val opts =
                  Vector.concatV
                  (Vector.keepAllMap
                   (ts, fn t =>
                    case node t of
                       Objptr opts => SOME opts
                     | _ => NONE))
            in
               if 0 = Vector.length opts
                  then Vector.sub (ts, 0)
               else
                  T {node = (Objptr (QuickSort.sortVector (opts, ObjptrTycon.<=))),
                     width = WordSize.bits (WordSize.objptr ())}
            end

      val sum = Trace.trace ("RepType.Type.sum", Vector.layout layout, layout) sum

      val intInf: unit -> t = fn () =>
         sum (Vector.new2
              (wordVector (WordSize.bigIntInfWord ()),
               seq (Vector.new2
                    (bits Bits.one,
                     word (WordSize.fromBits 
                           (Bits.- (WordSize.bits (WordSize.smallIntInfWord ()),
                                    Bits.one)))))))

      val deLabel: t -> Label.t option =
         fn t =>
         case node t of
            Label l => SOME l
          | _ => NONE

      val deObjptr: t -> ObjptrTycon.t option =
         fn t => 
         case node t of
            Objptr opts =>
               if 1 = Vector.length opts
                  then SOME (Vector.sub (opts, 0))
               else NONE
          | _ => NONE

      val deReal: t -> RealSize.t option =
         fn t =>
         case node t of
            Real s => SOME s
          | _ => NONE

      val deWord: t -> WordSize.t option =
         fn t =>
         case node t of
            Word s => SOME s
          | _ => NONE

      val isCPointer: t -> bool =
         fn t =>
         case node t of
            CPointer => true
          | _ => false

      val isObjptr: t -> bool =
         fn t =>
         case node t of
            Objptr _ => true
          | _ => false

      val isUnit: t -> bool = fn t => Bits.equals (Bits.zero, width t)

      val isSubtype: t * t -> bool =
         fn (t, t') =>
         if not (sameWidth (t, t'))
            then false (* Error.bug "RepType.Type.isSubtype" *)
         else
            (equals (t, t')
             orelse
             case (node t, node t') of
                (Objptr opts, Objptr opts') =>
                   Vector.isSubsequence (opts, opts', ObjptrTycon.equals)
              | (Real _, _) => false
              | (Bits, Objptr _) => true
              | (Word _, Objptr _) => true
              | (Seq ts, Objptr _) =>
                   Vector.forall 
                   (ts, (fn Bits => true 
                          | Real _ => true 
                          | Word _ => true 
                          | _ => false) o node)
              | (_, Bits) => true
              | (_, Word _) => true
              | (_, Seq ts) => 
                   Vector.forall 
                   (ts, (fn Bits => true 
                          | Real _ => true
                          | Word _ => true 
                          | _ => false) o node)
              | _ => false)

      val isSubtype =
         Trace.trace2 ("RepType.Type.isSubtype", layout, layout, Bool.layout)
         isSubtype

      fun exists (t, p) =
         if p t
            then true
         else (case node t of
                  Seq ts => Vector.exists (ts, fn t => exists (t, p))
                | _ => false)


      val resize: t * Bits.t -> t = fn (_, b) => bits b

      val bogusWord: t -> WordX.t =
         fn t => WordX.one (WordSize.fromBits (width t))

      local
         structure C =
            struct
               open CType

               fun fromBits (b: Bits.t): t =
                  case Bits.toInt b of
                     8 => Word8
                   | 16 => Word16
                   | 32 => Word32
                   | 64 => Word64
                   | _ => Error.bug (concat ["RepType.Type.CType.fromBits: ",
                                             Bits.toString b])
            end
      in
         val toCType: t -> CType.t =
            fn t =>
            if isObjptr t
               then C.Objptr
            else 
               case node t of
                  CPointer => C.CPointer
                | Real s =>
                     (case s of
                         RealSize.R32 => C.Real32
                       | RealSize.R64 => C.Real64)
                | _ => C.fromBits (width t)
                         
         val name = C.name o toCType
            
         val align: t * Bytes.t -> Bytes.t =
            fn (t, n) => C.align (toCType t, n)
      end

      fun bytesAndObjptrs (t: t): Bytes.t * int =
         case node t of
            Objptr _ => (Bytes.zero, 1)
          | Seq ts =>
               (case Vector.peeki (ts, isObjptr o #2) of
                   NONE => (bytes t, 0)
                 | SOME (i, _) =>
                      let
                         val b = bytes (seq (Vector.prefix (ts, i)))
                         val j = (Vector.length ts) - i
                      in
                         (b, j)
                      end)
          | _ => (bytes t, 0)
   end

structure ObjectType =
   struct
      structure ObjptrTycon = ObjptrTycon
      structure Runtime = Runtime

      type ty = Type.t
      datatype t =
         Array of {elt: ty,
                   hasIdentity: bool}
       | Normal of {hasIdentity: bool,
                    ty: ty}
       | Stack
       | Weak of Type.t
       | WeakGone
       | HeaderOnly
       | Fill

      fun layout (t: t) =
         let
            open Layout
         in
            case t of
               Array {elt, hasIdentity} =>
                  seq [str "Array ",
                       record [("elt", Type.layout elt),
                               ("hasIdentity", Bool.layout hasIdentity)]]
             | Normal {hasIdentity, ty} =>
                  seq [str "Normal ",
                       record [("hasIdentity", Bool.layout hasIdentity),
                               ("ty", Type.layout ty)]]
             | Stack => str "Stack"
             | Weak t => seq [str "Weak ", Type.layout t]
             | WeakGone => str "WeakGone"
             | HeaderOnly => str "HeaderOnly"
             | Fill => str "Fill"
         end

      fun isOk (t: t): bool =
         case t of
            Array {elt, ...} =>
               let
                  val b = Type.width elt
               in
                  Bits.> (b, Bits.zero)
                  andalso Bits.isByteAligned b
               end
          | Normal {ty, ...} =>
               not (Type.isUnit ty) 
               andalso Bits.isWord32Aligned (Type.width ty)
          | Stack => true
          | Weak t => Type.isObjptr t
          | WeakGone => true
          | HeaderOnly => true
          | Fill => true

      val stack = Stack

      val thread = fn () =>
         let
            val padding =
               case (!Control.align,
                     Bits.toInt (Control.Target.Size.csize ()),
                     Bits.toInt (Control.Target.Size.objptr ())) of
                  (Control.Align4,32,32) => Type.word0
                | (Control.Align8,32,32) => Type.word0
                | (Control.Align4,64,64) => Type.word0
                | (Control.Align8,64,64) => Type.word0
                | _ => Error.bug "RepType.ObjectType.thread"
         in
            Normal {hasIdentity = true,
                    ty = Type.seq (Vector.new4 (padding,
                                                Type.csize (),
                                                Type.exnStack (),
                                                Type.stack ()))}
         end

      (* Order in the following vector matters.  The basic pointer tycons must
       * correspond to the constants in gc.h.
       * STACK_TYPE_INDEX,
       * THREAD_TYPE_INDEX,
       * WEAK_GONE_TYPE_INDEX,
       * WORD8_VECTOR_TYPE_INDEX,
       * WORD16_VECTOR_TYPE_INDEX,
       * WORD32_VECTOR_TYPE_INDEX.
       * WORD64_VECTOR_TYPE_INDEX.
       * ZERO_WORD_TYPE_INDEX,
       * ONE_WORD_TYPE_INDEX,
       * TWO_WORD_TYPE_INDEX.
       *)
      val basic = fn () => 
         let
            fun wordVec i =
               let
                  val b = Bits.fromInt i
               in
                  (ObjptrTycon.wordVector b,
                   Array {hasIdentity = false,
                          elt = Type.word (WordSize.fromBits b)})
               end
         in
            Vector.fromList
            [(ObjptrTycon.stack, stack),
             (ObjptrTycon.thread, thread ()),
             (ObjptrTycon.weakGone, WeakGone),
             wordVec 8,
             wordVec 32,
             wordVec 16,
             wordVec 64,
             (ObjptrTycon.headerOnly, HeaderOnly),
             (ObjptrTycon.fill, Fill)]
         end

      local
         structure R = Runtime.RObjectType
      in
         fun toRuntime (t: t): R.t =
            case t of
               Array {elt, hasIdentity} =>
                  let
                     val (b, nops) = Type.bytesAndObjptrs elt
                  in
                     R.Array {hasIdentity = hasIdentity,
                              bytesNonObjptrs = b,
                              numObjptrs = nops}
                  end
             | Normal {hasIdentity, ty} =>
                  let
                     val (b, nops) = Type.bytesAndObjptrs ty
                  in
                     R.Normal {hasIdentity = hasIdentity,
                               bytesNonObjptrs = b,
                               numObjptrs = nops}
                  end
             | Stack => R.Stack
             | Weak _ => R.Weak
             | WeakGone => R.WeakGone
             | HeaderOnly => R.HeaderOnly
             | Fill => R.Fill
      end
   end

open Type

structure GCField = Runtime.GCField

fun ofGCField (f: GCField.t): t =
   let
      datatype z = datatype GCField.t
   in
      case f of
         AtomicState => word32
       | CardMapAbsolute => cpointer ()
       | CurrentThread => thread ()
       | CurSourceSeqsIndex => word32
       | ExnStack => exnStack ()
       | FFIOp => word32
       | Frontier => cpointer ()
       | GlobalObjptrNonRoot => cpointer ()
       | Limit => cpointer ()
       | LimitPlusSlop => cpointer ()
       | MaxFrameSize => word32
       | ReturnToC => word32
       | SignalIsPending => word32
       | StackBottom => cpointer ()
       | StackLimit => cpointer ()
       | StackTop => cpointer ()
   end

fun castIsOk {from, to, tyconTy = _} =
   Bits.equals (width from, width to)

fun checkPrimApp {args, prim, result} = 
   let
      datatype z = datatype Prim.Name.t
      fun done (argsP, resultP) =
         let
            val argsP = Vector.fromList argsP
         in
            (Vector.length args = Vector.length argsP)
            andalso (Vector.forall2 (args, argsP, 
                                     fn (arg, argP) => argP arg))
            andalso (case (result, resultP) of
                        (NONE, NONE) => true
                      | (SOME result, SOME resultP) => resultP result
                      | _ => false)
         end
      val bits = fn s => fn t => equals (t, bits s)
      val bool = fn t => equals (t, bool)
      val cpointer = fn t => equals (t, cpointer ())
      val objptr = fn t => (case node t of Objptr _ => true | _ => false)
      val real = fn s => fn t => equals (t, real s)
      val seq = fn s => fn t => 
         (case node t 
             of Seq _ => Bits.equals (width t, WordSize.bits s) 
           | _ => false)
      val word = fn s => fn t => equals (t, word s)

      val cint = word (WordSize.cint ())
      val csize = word (WordSize.csize ())
      val shiftArg = word WordSize.shiftArg

      val or = fn (p1, p2) => fn t => p1 t orelse p2 t
      val bitsOrSeq = fn s => or (bits (WordSize.bits s), seq s)
      val wordOrBitsOrSeq = fn s => or (word s, bitsOrSeq s)
      local
         fun make f s = let val t = f s in done ([t], SOME t) end
      in
         val realUnary = make real
         val wordUnary = make wordOrBitsOrSeq
      end
      local
         fun make f s = let val t = f s in done ([t, t], SOME t) end
      in
         val realBinary = make real
         val wordBinary = make wordOrBitsOrSeq
      end
      local
         fun make f s = let val t = f s in done ([t, t], SOME bool) end
      in
         val realCompare = make real
         val wordCompare = make wordOrBitsOrSeq
         val objptrCompare = make (fn _ => objptr) ()
      end
      fun realTernary s = done ([real s, real s, real s], SOME (real s))
      fun wordShift s = done ([wordOrBitsOrSeq s, shiftArg], SOME (wordOrBitsOrSeq s))
   in
      case Prim.name prim of
         CPointer_add => done ([cpointer, csize], SOME cpointer)
       | CPointer_diff => done ([cpointer, cpointer], SOME csize)
       | CPointer_equal => done ([cpointer, cpointer], SOME bool)
       | CPointer_fromWord => done ([csize], SOME cpointer)
       | CPointer_lt => done ([cpointer, cpointer], SOME bool)
       | CPointer_sub => done ([cpointer, csize], SOME cpointer)
       | CPointer_toWord => done ([cpointer], SOME csize)
       | FFI f => done (Vector.toListMap (CFunction.args f, 
                                          fn t' => fn t => equals (t', t)),
                        SOME (fn t => equals (t, CFunction.return f)))
       | FFI_Symbol _ => done ([], SOME cpointer)
       | MLton_touch => done ([objptr], NONE)
       | Real_Math_acos s => realUnary s
       | Real_Math_asin s => realUnary s
       | Real_Math_atan s => realUnary s
       | Real_Math_atan2 s => realBinary s
       | Real_Math_cos s => realUnary s
       | Real_Math_exp s => realUnary s
       | Real_Math_ln s => realUnary s
       | Real_Math_log10 s => realUnary s
       | Real_Math_sin s => realUnary s
       | Real_Math_sqrt s => realUnary s
       | Real_Math_tan s => realUnary s
       | Real_abs s => realUnary s
       | Real_add s => realBinary s
       | Real_castToWord (s, s') => done ([real s], SOME (word s'))
       | Real_div s => realBinary s
       | Real_equal s => realCompare s
       | Real_ldexp s => done ([real s, cint], SOME (real s))
       | Real_le s => realCompare s
       | Real_lt s => realCompare s
       | Real_mul s => realBinary s
       | Real_muladd s => realTernary s
       | Real_mulsub s => realTernary s
       | Real_neg s => realUnary s
       | Real_qequal s => realCompare s
       | Real_rndToReal (s, s') => done ([real s], SOME (real s'))
       | Real_rndToWord (s, s', _) => done ([real s], SOME (word s'))
       | Real_round s => realUnary s
       | Real_sub s => realBinary s
       | Word_add s => wordBinary s
       | Word_addCheck (s, _) => wordBinary s
       | Word_andb s => wordBinary s
       | Word_castToReal (s, s') => done ([word s], SOME (real s'))
       | Word_equal s => (wordCompare s) orelse objptrCompare
       | Word_extdToWord (s, s', _) => done ([wordOrBitsOrSeq s], 
                                             SOME (wordOrBitsOrSeq s'))
       | Word_lshift s => wordShift s
       | Word_lt (s, _) => wordCompare s
       | Word_mul (s, _) => wordBinary s
       | Word_mulCheck (s, _) => wordBinary s
       | Word_neg s => wordUnary s
       | Word_negCheck s => wordUnary s
       | Word_notb s => wordUnary s
       | Word_orb s => wordBinary s
       | Word_quot (s, _) => wordBinary s
       | Word_rem (s, _) => wordBinary s
       | Word_rndToReal (s, s', _) => done ([word s], SOME (real s'))
       | Word_rol s => wordShift s
       | Word_ror s => wordShift s
       | Word_rshift (s, _) => wordShift s
       | Word_sub s => wordBinary s
       | Word_subCheck (s, _) => wordBinary s
       | Word_xorb s => wordBinary s
       | _ => Error.bug (concat ["RepType.checkPrimApp got strange prim: ",
                                 Prim.toString prim])
   end

fun checkOffset {base, offset, result} =
   let
      fun getTys ty =
         case node ty of
            Seq tys => Vector.toList tys
          | _ => [ty]
      fun loop (offset, tys) =
         case tys of
            [] => false
          | ty::tys =>
               if Bits.equals (offset, Bits.zero)
                  then let
                          fun loop (resTys, eltTys) =
                             case (resTys, eltTys) of
                                ([], _) => true
                              | (_, []) => false
                              | (resTy::resTys, eltTy::eltTys) => 
                                   (case (node resTy, resTys, node eltTy) of
                                       (Bits, [], Bits) => 
                                          Bits.<= (width resTy, width eltTy)
                                     | _ => (equals (resTy, eltTy))
                                            andalso (loop (resTys, eltTys)))
                       in
                          loop (getTys result, ty::tys)
                       end
               else if Bits.>= (offset, width ty)
                  then loop (Bits.- (offset, width ty), tys)
               else (case node ty of
                        Bits => loop (Bits.zero, (bits (Bits.- (width ty, offset))) :: tys)
                      | _ => false)
   in
      if Control.Target.bigEndian ()
         then true
      else loop (Bytes.toBits offset, getTys base)
   end

fun offsetIsOk {base, offset, tyconTy, result} = 
   case node base of
      Objptr opts => 
         if Bytes.equals (offset, Runtime.headerOffset ())
            then equals (result, objptrHeader ())
         else if Bytes.equals (offset, Runtime.arrayLengthOffset ())
            then (1 = Vector.length opts)
                 andalso (case tyconTy (Vector.sub (opts, 0)) of
                             ObjectType.Array _ => true
                           | _ => false)
                 andalso (equals (result, seqIndex ()))
         else (1 = Vector.length opts)
              andalso (case tyconTy (Vector.sub (opts, 0)) of
                          ObjectType.Normal {ty, ...} => 
                             checkOffset {base = ty,
                                          offset = offset,
                                          result = result}
                        | _ => false)
    | _ => false

fun arrayOffsetIsOk {base, index, offset, tyconTy, result, scale} = 
   case node base of
      CPointer => 
         (equals (index, csize ()))
         andalso (case node result of
                     CPointer => true
                   | Objptr _ => true (* for FFI export of indirect types *)
                   | Real _ => true
                   | Word _ => true
                   | _ => false)
         andalso (case Scale.fromBytes (bytes result) of
                     NONE => false
                   | SOME s => scale = s)
         andalso (Bytes.equals (offset, Bytes.zero))
    | Objptr opts => 
         (equals (index, seqIndex ()))
         andalso (1 = Vector.length opts)
         andalso (case tyconTy (Vector.sub (opts, 0)) of
                     ObjectType.Array {elt, ...} => 
                        if equals (elt, word8)
                           then (* special case for PackWord operations *)
                                (case node result of
                                    Word wsRes => 
                                       (case Scale.fromBytes (WordSize.bytes wsRes) of
                                           NONE => false
                                         | SOME s => scale = s)
                                       andalso (Bytes.equals (offset, Bytes.zero))
                                  | _ => false)
                        else (case Scale.fromBytes (bytes elt) of
                                 NONE => scale = Scale.One
                               | SOME s => scale = s)
                             andalso (checkOffset {base = elt,
                                                   offset = offset,
                                                   result = result})
                   | _ => false)
    | _ => false



structure BuiltInCFunction =
   struct
      open CFunction

      datatype z = datatype Convention.t
      datatype z = datatype Target.t

      fun bug () = 
         vanilla {args = Vector.new1 (string ()),
                  name = "MLton_bug",
                  prototype = (Vector.new1 CType.cpointer, NONE),
                  return = unit}

      local
         fun make b = fn () =>
            T {args = Vector.new5 (Type.gcState (), Type.csize (), Type.bool, 
                                   Type.cpointer (), Type.word WordSize.word32),
                   bytesNeeded = NONE,
                   convention = Cdecl,
                   ensuresBytesFree = true,
                   mayGC = true,
                   maySwitchThreads = b,
                   modifiesFrontier = true,
                   prototype = (Vector.new5 (CType.cpointer, CType.csize (), CType.bool, 
                                             CType.cpointer, CType.Int32),
                                NONE),
                   readsStackTop = true,
                   return = Type.unit,       
                   target = Direct "GC_collect",
                   writesStackTop = true}
         val t = make true
         val f = make false
      in
         fun gc {maySwitchThreads = b} = if b then t () else f ()
      end
   end

end
