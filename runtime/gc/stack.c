/* Copyright (C) 1999-2005 Henry Cejtin, Matthew Fluet, Suresh
 *    Jagannathan, and Stephen Weeks.
 * Copyright (C) 1997-2000 NEC Research Institute.
 *
 * MLton is released under a BSD-style license.
 * See the file MLton-LICENSE for details.
 */

void displayStack (__attribute__ ((unused)) GC_state s,
                   GC_stack stack, 
                   FILE *stream) {
  fprintf(stream,
          "\t\treserved = %zu\n"
          "\t\tused = %zu\n",
          stack->reserved,
          stack->used);
}


bool isStackEmpty (GC_stack stack) {
  return 0 == stack->used;
}

#if ASSERT
bool isStackReservedAligned (GC_state s, size_t reserved) {
  return isAligned (GC_STACK_HEADER_SIZE + sizeof (struct GC_stack) + reserved, 
                    s->alignment);
}
#endif

/* sizeofStackSlop returns the amount of "slop" space needed between
 * the top of the stack and the end of the stack space.
 */
size_t sizeofStackSlop (GC_state s) {
  return (size_t)(2 * s->maxFrameSize);
}

size_t sizeofStackInitial (GC_state s) {
  return sizeofStackSlop (s);
}

/* Pointer to the bottommost word in use on the stack. */
pointer getStackBottom (__attribute__ ((unused)) GC_state s, GC_stack stack) {
  pointer res;

  res = ((pointer)stack) + sizeof (struct GC_stack);
  assert (isAligned ((size_t)res, s->alignment));
  return res;
}

/* Pointer to the topmost word in use on the stack. */
pointer getStackTop (GC_state s, GC_stack stack) {
  pointer res;

  res = getStackBottom (s, stack) + stack->used;
  assert (isAligned ((size_t)res, s->alignment));
  return res;
}

/* Pointer to the end of stack. */
pointer getStackLimitPlusSlop (GC_state s, GC_stack stack) {
  pointer res;

  res = getStackBottom (s, stack) + stack->reserved;
  // assert (isAligned ((size_t)res, s->alignment));
  return res;
}

/* The maximum value which is valid for stackTop. */
pointer getStackLimit (GC_state s, GC_stack stack) {
  pointer res;

  res  = getStackLimitPlusSlop (s, stack) - sizeofStackSlop (s);
  // assert (isAligned ((size_t)res, s->alignment));
  return res;
}


GC_frameIndex getCachedStackTopFrameIndex (GC_state s) {
  GC_frameIndex res;

  res = 
    getFrameIndexFromReturnAddress 
    (s, *((GC_returnAddress*)(s->stackTop - GC_RETURNADDRESS_SIZE)));
  return res;
}

GC_frameLayout getCachedStackTopFrameLayout (GC_state s) {
  GC_frameLayout layout;

  layout = getFrameLayoutFromFrameIndex (s, getCachedStackTopFrameIndex (s));
  return layout;
}

GC_frameIndex getStackTopFrameIndex (GC_state s, GC_stack stack) {
  GC_frameIndex res;

  res = 
    getFrameIndexFromReturnAddress 
    (s, *((GC_returnAddress*)(getStackTop (s, stack) - GC_RETURNADDRESS_SIZE)));
  return res;
}

GC_frameLayout getStackTopFrameLayout (GC_state s, GC_stack stack) {
  GC_frameLayout layout;

  layout = getFrameLayoutFromFrameIndex (s, getStackTopFrameIndex (s, stack));
  return layout;
}

uint16_t getStackTopFrameSize (GC_state s, GC_stack stack) {
  GC_frameLayout layout;

  assert (not (isStackEmpty (stack)));
  layout = getStackTopFrameLayout (s, stack);
  return layout->size;
}

size_t sizeofStackMinimumReserved (GC_state s, GC_stack stack) {
  size_t res;

  res =
    stack->used 
    + sizeofStackSlop (s) 
    - getStackTopFrameSize(s, stack);
  return res;
}

size_t alignStackReserved (GC_state s, size_t reserved) {
  size_t res;

  res = alignWithExtra (s, reserved, GC_STACK_HEADER_SIZE + sizeof (struct GC_stack));
  if (DEBUG_STACKS)
    fprintf (stderr, "%zu = alignStackReserved (%zu)\n", res, reserved);
  assert (isStackReservedAligned (s, res));
  return res;
}

size_t sizeofStackWithHeaderAligned (GC_state s, size_t reserved) {
  size_t res;

  res = 
    align (GC_STACK_HEADER_SIZE 
           + sizeof (struct GC_stack) 
           + reserved,
           s->alignment);
  if (DEBUG_STACKS)
    fprintf (stderr, "%zu = sizeofStackWithHeaderAligned (%zu)\n", res, reserved);
  return res;
}

size_t sizeofStackGrow (GC_state s, GC_stack stack) {
  size_t res;

  res = max (2 * stack->reserved, sizeofStackMinimumReserved (s, stack));
  return res;
}

void copyStack (GC_state s, GC_stack from, GC_stack to) {
  pointer fromBottom, toBottom;

  fromBottom = getStackBottom (s, from);
  toBottom = getStackBottom (s, to);
  assert (from->used <= to->reserved);
  to->used = from->used;
  if (DEBUG_STACKS)
    fprintf (stderr, "stackCopy from "FMTPTR" to "FMTPTR" of length %zu\n",
             (uintptr_t) fromBottom, 
             (uintptr_t) toBottom,
             from->used);
  GC_memcpy (fromBottom, toBottom, from->used);
}
