/* Copyright (C) 2004-2005 Henry Cejtin, Matthew Fluet, Suresh
 *    Jagannathan, and Stephen Weeks.
 *
 * MLton is released under a BSD-style license.
 * See the file MLton-LICENSE for details.
 */

#include "platform.h"

Bool MLton_Platform_CygwinUseMmap = FALSE;

void GC_setCygwinUseMmap (bool b) {
  MLton_Platform_CygwinUseMmap = b;
}

void MLton_init (int argc, char **argv, GC_state s) {
  int start;

  Posix_ProcEnv_environ = (C_StringArray_t)environ;
  start = GC_init (s, argc, argv);
  /* Setup argv and argc that SML sees. */
  /* start is now the index of the first real arg. */
  CommandLine_commandName = (C_String_t)(argv[0]);
  CommandLine_argc = argc - start;
  CommandLine_argv = (C_StringArray_t)(argv + start);
}

void MLton_exit (GC_state s, C_Int_t status) {
  GC_done (s);
  exit (status);
}

void MLton_allocTooLarge (void) {
  fprintf (stderr, "Out of memory: attempt to allocate more than %zu bytes.\n", 
           (size_t)0x7FFFFFFF);
  exit (2);
}
