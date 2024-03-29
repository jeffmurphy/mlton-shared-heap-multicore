/* Copyright (C) 1999-2005 Henry Cejtin, Matthew Fluet, Suresh
 *    Jagannathan, and Stephen Weeks.
 * Copyright (C) 1997-2000 NEC Research Institute.
 *
 * MLton is released under a BSD-style license.
 * See the file MLton-LICENSE for details.
 */

/*
 * Test if a intInf is a fixnum.
 */
static inline bool isSmall (objptr arg) {
  return (arg & 1);
}

static inline bool isEitherSmall (objptr arg1, objptr arg2) {
  return ((arg1 | arg2) & (objptr)1);
}

static inline bool areSmall (objptr arg1, objptr arg2) {
  return (arg1 & arg2 & (objptr)1);
}

/*
 * Convert a bignum intInf to a bignum pointer.
 */
static inline GC_intInf toBignum (GC_state s, objptr arg) {
  GC_intInf bp;

  assert (not isSmall(arg));
  bp = (GC_intInf)(objptrToPointer(arg, s->heap->start) 
                   - offsetof(struct GC_intInf, obj.body.isneg));
  if (DEBUG_INT_INF)
    fprintf (stderr, "bp->header = "FMTHDR"\n", bp->header);
  assert (bp->header == GC_INTINF_HEADER);
  return bp;
}

/*
 * Given an intInf, a pointer to an __mpz_struct and space large
 * enough to contain LIMBS_PER_OBJPTR + 1 limbs, fill in the
 * __mpz_struct.
 */
void fillIntInfArg (GC_state s, objptr arg, __mpz_struct *res, 
                    mp_limb_t space[LIMBS_PER_OBJPTR + 1]) {
  GC_intInf bp;

  if (DEBUG_INT_INF)
    fprintf (stderr, "fillIntInfArg ("FMTOBJPTR", "FMTPTR", "FMTPTR")\n",
             arg, (uintptr_t)res, (uintptr_t)space);
  if (isSmall(arg)) {
    res->_mp_alloc = LIMBS_PER_OBJPTR + 1;
    res->_mp_d = space;
    if (arg == (objptr)1) {
      res->_mp_size = 0;
    } else {
      objptr highBitMask = (objptr)1 << (CHAR_BIT * OBJPTR_SIZE - 1);
      bool neg = (arg & highBitMask) != (objptr)0;
      if (neg) {
        res->_mp_size = - (mp_size_t)LIMBS_PER_OBJPTR;
        arg = -((arg >> 1) | highBitMask);
      } else {
        res->_mp_size = (mp_size_t)LIMBS_PER_OBJPTR;
        arg = (arg >> 1);
      }
      for (unsigned int i = 0; i < LIMBS_PER_OBJPTR; i++) {
        space[i] = (mp_limb_t)arg;
        // The conditional below is to quell a gcc warning:
        //   right shift count >= width of type
        // When 1 == LIMBS_PEROBJPTR, the for loop will not continue, so the
        // shift doesn't matter.
        arg = arg >> (1 == LIMBS_PER_OBJPTR ?
                        0 :
                        CHAR_BIT * sizeof(mp_limb_t));
      }
    }
  } else {
    bp = toBignum (s, arg);
    res->_mp_alloc = bp->length - 1;
    res->_mp_d = (mp_limb_t*)(bp->obj.body.limbs);
    res->_mp_size = bp->obj.body.isneg ? - res->_mp_alloc : res->_mp_alloc;
  }
  assert ((res->_mp_size == 0) 
          or (res->_mp_d[(res->_mp_size < 0 
                          ? - res->_mp_size 
                          : res->_mp_size) - 1] != 0));
  if (DEBUG_INT_INF_DETAILED)
    fprintf (stderr, "arg --> %s\n",
             mpz_get_str (NULL, 10, res));
}

/*
 * Initialize an __mpz_struct to use the space provided by the heap.
 */
void initIntInfRes (GC_state s, __mpz_struct *res, 
                    __attribute__ ((unused)) size_t bytes) {
  GC_intInf bp;

  assert (bytes <= (size_t)(s->limitPlusSlop - s->frontier));
  bp = (GC_intInf)s->frontier;
  /* We have as much space for the limbs as there is to the end of the
   * heap.  Divide by (sizeof(mp_limb_t)) to get number of limbs.
   */
  res->_mp_alloc = (s->limitPlusSlop - (pointer)bp->obj.body.limbs) / (sizeof(mp_limb_t));
  res->_mp_d = (mp_limb_t*)(bp->obj.body.limbs);
  res->_mp_size = 0; /* is this necessary? */
}

/*
 * Given an __mpz_struct pointer which reflects the answer, set
 * gcState.frontier and return the answer.
 * If the answer fits in a fixnum, we return that, with the frontier
 * rolled back.
 * If the answer doesn't need all of the space allocated, we adjust
 * the array size and roll the frontier slightly back.
 */
objptr finiIntInfRes (GC_state s, __mpz_struct *res, size_t bytes) {
  GC_intInf bp;
  mp_size_t size;

  assert ((res->_mp_size == 0) 
          or (res->_mp_d[(res->_mp_size < 0 
                          ? - res->_mp_size 
                          : res->_mp_size) - 1] != 0));
  if (DEBUG_INT_INF)
    fprintf (stderr, "finiIntInfRes ("FMTPTR", %zu)\n",
             (uintptr_t)res, bytes);
  if (DEBUG_INT_INF_DETAILED)
    fprintf (stderr, "res --> %s\n",
             mpz_get_str (NULL, 10, res));
  bp = (GC_intInf)((pointer)res->_mp_d - offsetof(struct GC_intInf, obj.body.limbs));
  assert (res->_mp_d == (mp_limb_t*)(bp->obj.body.limbs));
  size = res->_mp_size;
  if (size < 0) {
    bp->obj.body.isneg = TRUE;
    size = - size;
  } else
    bp->obj.body.isneg = FALSE;
  if (size <= 1) {
    uintmax_t val, ans;

    if (size == 0)
      val = 0;
    else
      val = bp->obj.body.limbs[0];
    if (bp->obj.body.isneg) {
      /*
       * We only fit if val in [1, 2^(CHAR_BIT * OBJPTR_SIZE - 2)].
       */
      ans = - val;
      val = val - 1;
    } else
      /*
       * We only fit if val in [0, 2^(CHAR_BIT * OBJPTR_SIZE - 2) - 1].
       */
      ans = val;
    if (val < (uintmax_t)1<<(CHAR_BIT * OBJPTR_SIZE - 2)) {
      return (objptr)(ans<<1 | 1);
    }
  }
  setFrontier (s, (pointer)(&bp->obj.body.limbs[size]), bytes);
  bp->counter = 0;
  bp->length = size + 1; /* +1 for isneg field */
  bp->header = GC_INTINF_HEADER;
  return pointerToObjptr ((pointer)&bp->obj, s->heap->start);
}

static inline objptr binary (objptr lhs, objptr rhs, size_t bytes,
                             void(*binop)(__mpz_struct *resmpz,
                                          __gmp_const __mpz_struct *lhsspace,
                                          __gmp_const __mpz_struct *rhsspace)) {
  __mpz_struct lhsmpz, rhsmpz, resmpz;
  mp_limb_t lhsspace[LIMBS_PER_OBJPTR + 1], rhsspace[LIMBS_PER_OBJPTR + 1];
  GC_state s = pthread_getspecific (gcstate_key);

  initIntInfRes (s, &resmpz, bytes);
  fillIntInfArg (s, lhs, &lhsmpz, lhsspace);
  fillIntInfArg (s, rhs, &rhsmpz, rhsspace);
  binop (&resmpz, &lhsmpz, &rhsmpz);
  return finiIntInfRes (s, &resmpz, bytes);
}

objptr IntInf_add (objptr lhs, objptr rhs, size_t bytes) {
  if (DEBUG_INT_INF)
    fprintf (stderr, "IntInf_add ("FMTOBJPTR", "FMTOBJPTR", %zu)\n",
             lhs, rhs, bytes);
  return binary (lhs, rhs, bytes, &mpz_add);
}

objptr IntInf_andb (objptr lhs, objptr rhs, size_t bytes) {
  if (DEBUG_INT_INF)
    fprintf (stderr, "IntInf_andb ("FMTOBJPTR", "FMTOBJPTR", %zu)\n",
             lhs, rhs, bytes);
  return binary (lhs, rhs, bytes, &mpz_and);
}

objptr IntInf_gcd (objptr lhs, objptr rhs, size_t bytes) {
  if (DEBUG_INT_INF)
    fprintf (stderr, "IntInf_gcd ("FMTOBJPTR", "FMTOBJPTR", %zu)\n",
             lhs, rhs, bytes);
  return binary (lhs, rhs, bytes, &mpz_gcd);
}

objptr IntInf_mul (objptr lhs, objptr rhs, size_t bytes) {
  if (DEBUG_INT_INF)
    fprintf (stderr, "IntInf_mul ("FMTOBJPTR", "FMTOBJPTR", %zu)\n",
             lhs, rhs, bytes);
  return binary (lhs, rhs, bytes, &mpz_mul);
}

objptr IntInf_quot (objptr lhs, objptr rhs, size_t bytes) {
  if (DEBUG_INT_INF)
    fprintf (stderr, "IntInf_quot ("FMTOBJPTR", "FMTOBJPTR", %zu)\n",
             lhs, rhs, bytes);
  return binary (lhs, rhs, bytes, &mpz_tdiv_q);
}

objptr IntInf_orb (objptr lhs, objptr rhs, size_t bytes) {
  if (DEBUG_INT_INF)
    fprintf (stderr, "IntInf_orb ("FMTOBJPTR", "FMTOBJPTR", %zu)\n",
             lhs, rhs, bytes);
  return binary (lhs, rhs, bytes, &mpz_ior);
}

objptr IntInf_rem (objptr lhs, objptr rhs, size_t bytes) {
  if (DEBUG_INT_INF)
    fprintf (stderr, "IntInf_quot ("FMTOBJPTR", "FMTOBJPTR", %zu)\n",
             lhs, rhs, bytes);
  return binary (lhs, rhs, bytes, &mpz_tdiv_r);
}

objptr IntInf_sub (objptr lhs, objptr rhs, size_t bytes) {
  if (DEBUG_INT_INF)
    fprintf (stderr, "IntInf_sub ("FMTOBJPTR", "FMTOBJPTR", %zu)\n",
             lhs, rhs, bytes);
  return binary (lhs, rhs, bytes, &mpz_sub);
}

objptr IntInf_xorb (objptr lhs, objptr rhs, size_t bytes) {
  if (DEBUG_INT_INF)
    fprintf (stderr, "IntInf_xorb ("FMTOBJPTR", "FMTOBJPTR", %zu)\n",
             lhs, rhs, bytes);
  return binary (lhs, rhs, bytes, &mpz_xor);
}

static objptr unary (objptr arg, size_t bytes,
                     void(*unop)(__mpz_struct *resmpz,
                                 __gmp_const __mpz_struct *argspace)) {
  __mpz_struct argmpz, resmpz;
 mp_limb_t argspace[LIMBS_PER_OBJPTR + 1];
 GC_state s = pthread_getspecific (gcstate_key);

 initIntInfRes (s, &resmpz, bytes);
 fillIntInfArg (s, arg, &argmpz, argspace);
 unop (&resmpz, &argmpz);
 return finiIntInfRes (s, &resmpz, bytes);
}

objptr IntInf_neg (objptr arg, size_t bytes) {
  if (DEBUG_INT_INF)
    fprintf (stderr, "IntInf_neg ("FMTOBJPTR", %zu)\n",
             arg, bytes);
  return unary (arg, bytes, &mpz_neg);
}

objptr IntInf_notb (objptr arg, size_t bytes) {
  if (DEBUG_INT_INF)
    fprintf (stderr, "IntInf_notb ("FMTOBJPTR", %zu)\n",
             arg, bytes);
  return unary (arg, bytes, &mpz_com);
}

static objptr shary (objptr arg, Word32_t shift, size_t bytes,
                     void(*shop)(__mpz_struct *resmpz,
                                 __gmp_const __mpz_struct *argspace,
                                 unsigned long shift))
{
  __mpz_struct argmpz, resmpz;
  mp_limb_t argspace[LIMBS_PER_OBJPTR + 1];
  GC_state s = pthread_getspecific (gcstate_key);

  initIntInfRes (s, &resmpz, bytes);
  fillIntInfArg (s, arg, &argmpz, argspace);
  shop (&resmpz, &argmpz, (unsigned long)shift);
  return finiIntInfRes (s, &resmpz, bytes);
}

objptr IntInf_arshift (objptr arg, Word32_t shift, size_t bytes) {
  if (DEBUG_INT_INF)
    fprintf (stderr, "IntInf_arshift ("FMTOBJPTR", %"PRIu32", %zu)\n",
             arg, shift, bytes);
  return shary (arg, shift, bytes, &mpz_fdiv_q_2exp);
}

objptr IntInf_lshift (objptr arg, Word32_t shift, size_t bytes) {
  if (DEBUG_INT_INF)
    fprintf (stderr, "IntInf_lshift ("FMTOBJPTR", %"PRIu32", %zu)\n",
             arg, shift, bytes);
  return shary(arg, shift, bytes, &mpz_mul_2exp);
}

/*
 * Return an integer which compares to 0 as the two intInf args compare
 * to each other.
 */
Int32_t IntInf_compare (objptr lhs, objptr rhs) {
  __mpz_struct lhsmpz, rhsmpz;
  mp_limb_t lhsspace[LIMBS_PER_OBJPTR + 1], rhsspace[LIMBS_PER_OBJPTR + 1];
  int res;
  GC_state s = pthread_getspecific (gcstate_key);

  if (DEBUG_INT_INF)
    fprintf (stderr, "IntInf_compare ("FMTOBJPTR", "FMTOBJPTR")\n",
             lhs, rhs);
  fillIntInfArg (s, lhs, &lhsmpz, lhsspace);
  fillIntInfArg (s, rhs, &rhsmpz, rhsspace);
  res = mpz_cmp (&lhsmpz, &rhsmpz);
  if (res < 0) return -1;
  if (res > 0) return 1;
  return 0;
}

/*
 * Check if two IntInf.int's are equal.
 */
Bool_t IntInf_equal (objptr lhs, objptr rhs) {
  if (lhs == rhs)
    return TRUE;
  if (isEitherSmall (lhs, rhs))
    return FALSE;
  else
    return 0 == IntInf_compare (lhs, rhs);
}

/*
 * Convert an intInf to a string.
 * Arg is an intInf, base is the base to use (2, 8, 10 or 16) and
 * space is a string (mutable) which is large enough.
 */
objptr IntInf_toString (objptr arg, int32_t base, size_t bytes) {
  GC_string8 sp;
  __mpz_struct argmpz;
  mp_limb_t argspace[LIMBS_PER_OBJPTR + 1];
  char *str;
  size_t size;
  GC_state s = pthread_getspecific (gcstate_key);

  if (DEBUG_INT_INF)
    fprintf (stderr, "IntInf_toString ("FMTOBJPTR", %"PRId32", %zu)\n",
             arg, base, bytes);
  assert (base == 2 || base == 8 || base == 10 || base == 16);
  fillIntInfArg (s, arg, &argmpz, argspace);
  sp = (GC_string8)s->frontier;
  str = mpz_get_str((void*)&sp->obj, base, &argmpz);
  assert (str == (char*)&sp->obj);
  size = strlen(str);
  if (sp->obj.body.chars[0] == '-')
    sp->obj.body.chars[0] = '~';
  if (base > 0)
    for (unsigned int i = 0; i < size; i++) {
      char c = sp->obj.body.chars[i];
      if (('a' <= c) && (c <= 'z'))
        sp->obj.body.chars[i] = c + ('A' - 'a');
    }
  setFrontier (s, (pointer)&sp->obj + size, bytes);
  sp->counter = 0;
  sp->length = size;
  sp->header = GC_STRING8_HEADER;
  return pointerToObjptr ((pointer)&sp->obj, s->heap->start);
}
