/* Copyright (C) 1999-2005 Henry Cejtin, Matthew Fluet, Suresh
 *    Jagannathan, and Stephen Weeks.
 * Copyright (C) 1997-2000 NEC Research Institute.
 *
 * MLton is released under a BSD-style license.
 * See the file MLton-LICENSE for details.
 */

/* ---------------------------------------------------------------- */
/*                 Jonkers Mark-compact Collection                  */
/* ---------------------------------------------------------------- */

void copyForThreadInternal (pointer dst, pointer src) {
  if (OBJPTR_SIZE > GC_HEADER_SIZE) {
    size_t count;

    assert (0 == (OBJPTR_SIZE % GC_HEADER_SIZE));
    count = (OBJPTR_SIZE - GC_HEADER_SIZE) / GC_HEADER_SIZE;
    src = src + GC_HEADER_SIZE * count;

    for (size_t i = 0; i <= count; i++) {
      *((GC_header*)dst) = *((GC_header*)src);
      dst += GC_HEADER_SIZE;
      src -= GC_HEADER_SIZE;
    }
  } else if (GC_HEADER_SIZE > OBJPTR_SIZE) {
    size_t count;

    assert (0 == (GC_HEADER_SIZE % OBJPTR_SIZE));
    count = (GC_HEADER_SIZE - OBJPTR_SIZE) / OBJPTR_SIZE;
    dst = dst + OBJPTR_SIZE * count;

    for (size_t i = 0; i <= count; i++) {
      *((objptr*)dst) = *((objptr*)src);
      dst -= OBJPTR_SIZE;
      src += OBJPTR_SIZE;
    }
  } else /* (GC_HEADER_SIZE == OBJPTR_SIZE) */ {
    *((GC_header*)dst) = *((GC_header*)src);
  }
}

void threadInternalObjptr (GC_state s, objptr *opp) {
  objptr opop;
  pointer p;
  GC_header *headerp;

  opop = pointerToObjptr ((pointer)opp, s->heap->start);
  p = objptrToPointer (*opp, s->heap->start);
  if (FALSE)
    fprintf (stderr, 
             "threadInternal opp = "FMTPTR"  p = "FMTPTR"  header = "FMTHDR"\n",
             (uintptr_t)opp, (uintptr_t)p, getHeader (p));
  headerp = getHeaderp (p);
  copyForThreadInternal ((pointer)(opp), (pointer)(headerp));
  copyForThreadInternal ((pointer)(headerp), (pointer)(&opop));
}

/* If p is weak, the object pointer was valid, and points to an
 * unmarked object, then clear the object pointer.
 */
void clearIfWeakAndUnmarkedForMarkCompact (GC_state s, pointer p) {
  GC_header header;
  GC_header *headerp;
  uint16_t bytesNonObjptrs, numObjptrs;
  GC_objectTypeTag tag;

  headerp = getHeaderp (p);
  header = *headerp;
  splitHeader(s, *headerp, &tag, NULL, &bytesNonObjptrs, &numObjptrs);
  if (WEAK_TAG == tag and 1 == numObjptrs) {
    GC_header objptrHeader;
    GC_weak w;

    if (DEBUG_MARK_COMPACT or DEBUG_WEAK)
      fprintf (stderr, "clearIfWeakAndUnmarkedForMarkCompact ("FMTPTR")  header = "FMTHDR"\n",
               (uintptr_t)p, header);
    w = (GC_weak)(p + offsetofWeak (s));
    objptrHeader = getHeader (objptrToPointer(w->objptr, s->heap->start));
    /* If it's not threaded and unmarked, clear the weak pointer. */
    if ((GC_VALID_HEADER_MASK & objptrHeader)
        and not (MARK_MASK & objptrHeader)) {
      w->objptr = BOGUS_OBJPTR;
      header = GC_WEAK_GONE_HEADER | MARK_MASK;
      if (DEBUG_WEAK)
        fprintf (stderr, "cleared.  new header = "FMTHDR"\n",
                 header);
      *headerp = header;
    }
  }
}

void updateForwardPointersForMarkCompact (GC_state s) {
  pointer back;
  pointer endOfLastMarked;
  pointer front;
  size_t gap;
  GC_header header;
  GC_header *headerp;
  pointer p;
  size_t size;

  if (DEBUG_MARK_COMPACT)
    fprintf (stderr, "Update forward pointers.\n");
  front = alignFrontier (s, s->heap->start);
  back = s->heap->start + s->heap->oldGenSize;
  endOfLastMarked = front;
  gap = 0;
updateObject:
  if (DEBUG_MARK_COMPACT)
    fprintf (stderr, "updateObject  front = "FMTPTR"  back = "FMTPTR"\n",
             (uintptr_t)front, (uintptr_t)back);
  if (front == back)
    goto done;
  p = advanceToObjectData (s, front);
  headerp = getHeaderp (p);
  header = *headerp;
  if (GC_VALID_HEADER_MASK & header) {
    /* It's a header */
    if (MARK_MASK & header) {
      /* It is marked, but has no forward pointers.
       * Thread internal pointers.
       */
thread:
      clearIfWeakAndUnmarkedForMarkCompact (s, p);
      size = sizeofObject (s, p);
      if (DEBUG_MARK_COMPACT)
        fprintf (stderr, "threading "FMTPTR" of size %zu\n",
                 (uintptr_t)p, size);
      if ((size_t)(front - endOfLastMarked) >= GC_ARRAY_HEADER_SIZE + OBJPTR_SIZE) {
        pointer newArray = endOfLastMarked;
        /* Compress all of the unmarked into one vector.  We require
         * (GC_ARRAY_HEADER_SIZE + OBJPTR_SIZE) space to be available
         * because that is the smallest possible array.  You cannot
         * use GC_ARRAY_HEADER_SIZE because even very small (including
         * zero-length) arrays require extra space for the forwarding
         * pointer.  If you did use GC_ARRAY_HEADER_SIZE,
         * updateBackwardPointersAndSlideForMarkCompact would skip the
         * extra space and be completely busted.
         */
        if (DEBUG_MARK_COMPACT)
          fprintf (stderr, "compressing from "FMTPTR" to "FMTPTR" (length = %zu)\n",
                   (uintptr_t)endOfLastMarked, (uintptr_t)front,
                   (size_t)(front - endOfLastMarked));
        *((GC_arrayCounter*)(newArray)) = 0;
        newArray += GC_ARRAY_COUNTER_SIZE;
        *((GC_arrayLength*)(newArray)) = 
          ((size_t)(front - endOfLastMarked)) - GC_ARRAY_HEADER_SIZE;
        newArray += GC_ARRAY_LENGTH_SIZE;
        *((GC_header*)(newArray)) = GC_WORD8_VECTOR_HEADER;
      }
      front += size;
      endOfLastMarked = front;
      foreachObjptrInObject (s, p, threadInternalObjptr, FALSE);
      goto updateObject;
    } else {
      /* It's not marked. */
      size = sizeofObject (s, p);
      gap += size;
      front += size;
      goto updateObject;
    }
  } else {
    pointer new;
    objptr newObjptr;

    assert (not (GC_VALID_HEADER_MASK & header));
    /* It's a pointer.  This object must be live.  Fix all the forward
     * pointers to it, store its header, then thread its internal
     * pointers.
     */
    new = p - gap;
    newObjptr = pointerToObjptr (new, s->heap->start);
    do {
      pointer cur;
      objptr curObjptr;

      copyForThreadInternal ((pointer)(&curObjptr), (pointer)headerp);
      cur = objptrToPointer (curObjptr, s->heap->start);

      copyForThreadInternal ((pointer)headerp, cur);
      *((objptr*)cur) = newObjptr;

      header = *headerp;
    } while (0 == (1 & header));
    goto thread;
  }
  assert (FALSE);
done:
  return;
}

void updateBackwardPointersAndSlideForMarkCompact (GC_state s) {
  pointer back;
  pointer front;
  size_t gap;
  GC_header header;
  GC_header *headerp;
  pointer p;
  size_t size;

  if (DEBUG_MARK_COMPACT)
    fprintf (stderr, "Update backward pointers and slide.\n");
  front = alignFrontier (s, s->heap->start);
  back = s->heap->start + s->heap->oldGenSize;
  gap = 0;
updateObject:
  if (DEBUG_MARK_COMPACT)
    fprintf (stderr, "updateObject  front = "FMTPTR"  back = "FMTPTR"\n",
             (uintptr_t)front, (uintptr_t)back);
  if (front == back)
    goto done;
  p = advanceToObjectData (s, front);
  headerp = getHeaderp (p);
  header = *headerp;
  if (GC_VALID_HEADER_MASK & header) {
    /* It's a header */
    if (MARK_MASK & header) {
      /* It is marked, but has no backward pointers to it.
       * Unmark it.
       */
unmark:
      size = sizeofObject (s, p);
      /* unmark */
      if (DEBUG_MARK_COMPACT)
        fprintf (stderr, "unmarking "FMTPTR" of size %zu\n",
                 (uintptr_t)p, size);
      *headerp = header & ~MARK_MASK;
      /* slide */
      if (DEBUG_MARK_COMPACT)
        fprintf (stderr, "sliding "FMTPTR" down %zu\n",
                 (uintptr_t)front, gap);
      GC_memcpy (front, front - gap, size);
      front += size;
      goto updateObject;
    } else {
      /* It's not marked. */
      size = sizeofObject (s, p);
      if (DEBUG_MARK_COMPACT)
        fprintf (stderr, "skipping "FMTPTR" of size %zu\n",
                 (uintptr_t)p, size);
      gap += size;
      front += size;
      goto updateObject;
    }
  } else {
    pointer new;
    objptr newObjptr;

    assert (not (GC_VALID_HEADER_MASK & header));
    /* It's a pointer.  This object must be live.  Fix all the
     * backward pointers to it.  Then unmark it.
     */
    new = p - gap;
    newObjptr = pointerToObjptr (new, s->heap->start);
    do {
      pointer cur;
      objptr curObjptr;

      copyForThreadInternal ((pointer)(&curObjptr), (pointer)headerp);
      cur = objptrToPointer (curObjptr, s->heap->start);

      copyForThreadInternal ((pointer)headerp, cur);
      *((objptr*)cur) = newObjptr;

      header = *headerp;
    } while (0 == (1 & header));
    /* The unmarked header will be stored by unmark. */
    goto unmark;
  }
  assert (FALSE);
done:
  s->heap->oldGenSize = front - gap - s->heap->start;
  if (DEBUG_MARK_COMPACT)
    fprintf (stderr, "oldGenSize = %zu\n", s->heap->oldGenSize);
  return;
}

void majorMarkCompactGC (GC_state s) {
  size_t bytesMarkCompacted;
  struct rusage ru_start;

  if (detailedGCTime (s))
    startTiming (&ru_start);
  s->cumulativeStatistics->numMarkCompactGCs++;
  if (DEBUG or s->controls->messages) {
    fprintf (stderr, "[GC: Major mark-compact; heap at "FMTPTR" of size %s bytes.]\n",
             (uintptr_t)(s->heap->start), 
             uintmaxToCommaString(s->heap->size));
  }
  if (s->hashConsDuringGC) {
    s->lastMajorStatistics->bytesHashConsed = 0;
    s->cumulativeStatistics->numHashConsGCs++;
    s->objectHashTable = allocHashTable (s);
    foreachGlobalObjptr (s, dfsMarkWithHashCons);
    freeHashTable (s->objectHashTable);
  } else {
    foreachGlobalObjptr (s, dfsMarkWithoutHashCons);
  }
  foreachGlobalObjptr (s, threadInternalObjptr);
  updateForwardPointersForMarkCompact (s);
  updateBackwardPointersAndSlideForMarkCompact (s);
  clearCrossMap (s);
  bytesMarkCompacted = s->heap->oldGenSize;
  s->cumulativeStatistics->bytesMarkCompacted += bytesMarkCompacted;
  s->lastMajorStatistics->kind = GC_MARK_COMPACT;
  if (detailedGCTime (s))
    stopTiming (&ru_start, &s->cumulativeStatistics->ru_gcMarkCompact);
  if (DEBUG or s->controls->messages) {
    fprintf (stderr, "[GC: Major mark-compact done; %s bytes mark compacted.]\n",
             uintmaxToCommaString(bytesMarkCompacted));
    if (s->hashConsDuringGC)
      printBytesHashConsedMessage(s, 
                                  s->lastMajorStatistics->bytesHashConsed 
                                  + s->heap->oldGenSize);
  }
}
