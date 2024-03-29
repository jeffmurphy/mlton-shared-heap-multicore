/* Copyright (C) 1999-2005 Henry Cejtin, Matthew Fluet, Suresh
 *    Jagannathan, and Stephen Weeks.
 * Copyright (C) 1997-2000 NEC Research Institute.
 *
 * MLton is released under a BSD-style license.
 * See the file MLton-LICENSE for details.
 */

#if (defined (MLTON_GC_INTERNAL_TYPES))

struct GC_sysvals {
  size_t ram;
  size_t totalRam;
  size_t pageSize;
};

#endif /* (defined (MLTON_GC_INTERNAL_TYPES)) */
