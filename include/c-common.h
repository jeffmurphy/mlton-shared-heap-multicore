/* Copyright (C) 1999-2005 Henry Cejtin, Matthew Fluet, Suresh
 *    Jagannathan, and Stephen Weeks.
 * Copyright (C) 1997-2000 NEC Research Institute.
 *
 * MLton is released under a BSD-style license.
 * See the file MLton-LICENSE for details.
 */

#ifndef _C_COMMON_H_
#define _C_COMMON_H_

#ifndef DEBUG_CCODEGEN
#define DEBUG_CCODEGEN FALSE
#endif

/* A key whose value will be a unique integer per thread */
extern C_Pthread_Key_t gcstate_key;

struct cont {
        void *nextChunk;
        uintptr_t nextFun;
};

extern struct cont (*nextChunks []) (void);
extern struct GC_state * gcState;

#define ChunkName(n) Chunk ## n

#define DeclareChunk(n)                         \
        struct cont ChunkName(n)(uintptr_t l_nextFun)

#define Chunkp(n) &(ChunkName(n))

#define PrepFarJump(cont, n, l)                         \
        do {                                            \
                cont.nextChunk = (void*)ChunkName(n);   \
                cont.nextFun = l;                       \
        } while (0)

#endif /* #ifndef _C_COMMON_H_ */
