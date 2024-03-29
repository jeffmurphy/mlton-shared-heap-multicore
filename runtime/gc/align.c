/* Copyright (C) 1999-2005 Henry Cejtin, Matthew Fluet, Suresh
 *    Jagannathan, and Stephen Weeks.
 * Copyright (C) 1997-2000 NEC Research Institute.
 *
 * MLton is released under a BSD-style license.
 * See the file MLton-LICENSE for details.
 */

size_t alignWithExtra (GC_state s, size_t bytes, size_t extra) {
  return align (bytes + extra, s->alignment) - extra;
}


#if ASSERT
bool isFrontierAligned (GC_state s, pointer p) {
  return isAligned ((size_t)p + GC_NORMAL_HEADER_SIZE, 
                    s->alignment);
}
#endif

pointer alignFrontier (GC_state s, pointer p) {
  size_t res;

  res = alignWithExtra (s, (size_t)p, GC_NORMAL_HEADER_SIZE);
  assert (isFrontierAligned (s, (pointer)res));
  return (pointer)res;
}

