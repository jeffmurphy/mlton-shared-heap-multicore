/* Copyright (C) 1999-2005 Henry Cejtin, Matthew Fluet, Suresh
 *    Jagannathan, and Stephen Weeks.
 * Copyright (C) 1997-2000 NEC Research Institute.
 *
 * MLton is released under a BSD-style license.
 * See the file MLton-LICENSE for details.
 */

#define MLTON_GC_INTERNAL_TYPES
#define MLTON_GC_INTERNAL_FUNCS
#define MLTON_GC_INTERNAL_BASIS
#include "platform.h"

#include "gc/virtual-memory.c"
#include "gc/align.c"
#include "gc/read_write.c"

/* used to look up per-processor state */
extern C_Pthread_Key_t gcstate_key;

#include "gc/array-allocate.c"
#include "gc/array.c"
#include "gc/atomic.c"
#include "gc/call-stack.c"
#include "gc/cheney-copy.c"
#include "gc/controls.c"
#include "gc/copy-thread.c"
#include "gc/current.c"
#include "gc/dfs-mark.c"
#include "gc/done.c"
#include "gc/enter_leave.c"
#include "gc/foreach.c"
#include "gc/forward.c"
#include "gc/frame.c"
#include "gc/processor.c"
#include "gc/garbage-collection.c"
#include "gc/gc_state.c"
#include "gc/generational.c"
#include "gc/handler.c"
#include "gc/hash-cons.c"
#include "gc/heap.c"
#include "gc/heap_predicates.c"
#include "gc/init-world.c"
#include "gc/init.c"
#include "gc/int-inf.c"
#include "gc/invariant.c"
#include "gc/mark-compact.c"
#include "gc/model.c"
#include "gc/new-object.c"
#include "gc/object-size.c"
#include "gc/object.c"
#include "gc/objptr.c"
#include "gc/pack.c"
#include "gc/parallel.c"
#include "gc/pointer.c"
#include "gc/profiling.c"
#include "gc/rusage.c"
#include "gc/share.c"
#include "gc/signals.c"
#include "gc/size.c"
#include "gc/sources.c"
#include "gc/stack.c"
#include "gc/switch-thread.c"
#include "gc/thread.c"
#include "gc/translate.c"
#include "gc/weak.c"
#include "gc/world.c"
