#include "platform.h"

/* XXX reference to global gcState */
extern struct GC_state gcState;

static void handler (int signum) {
  GC_handler (&gcState, signum);
}

enum {
#if (defined (SA_ONSTACK))
  SA_FLAGS = SA_ONSTACK,
#else
  SA_FLAGS = 0,
#endif
};

C_Errno_t(C_Int_t) Posix_Signal_default (C_Signal_t signum) {
  struct sigaction sa;

  sigdelset (GC_getSignalsHandledAddr (&gcState), signum);
  memset (&sa, 0, sizeof(sa));
  sa.sa_handler = SIG_DFL;
  sa.sa_flags = SA_FLAGS;
  return sigaction (signum, &sa, NULL);
}

C_Errno_t(C_Int_t) Posix_Signal_isDefault (C_Int_t signum, Ref(C_Int_t) isDef) {
  int res;
  struct sigaction sa;

  sa.sa_flags = SA_FLAGS;
  res = sigaction (signum, NULL, &sa);
  *((C_Int_t*)isDef) = sa.sa_handler == SIG_DFL;
  return res;
}

C_Errno_t(C_Int_t) Posix_Signal_ignore (C_Signal_t signum) {
  struct sigaction sa;

  sigdelset (GC_getSignalsHandledAddr (&gcState), signum);
  memset (&sa, 0, sizeof(sa));
  sa.sa_handler = SIG_IGN;
  sa.sa_flags = SA_FLAGS;
  return sigaction (signum, &sa, NULL);
}

C_Errno_t(C_Int_t) Posix_Signal_isIgnore (C_Int_t signum, Ref(C_Int_t) isIgn) {
  int res;
  struct sigaction sa;

  sa.sa_flags = SA_FLAGS;
  res = sigaction (signum, NULL, &sa);
  *((C_Int_t*)isIgn) = sa.sa_handler == SIG_IGN;
  return res;
}

C_Errno_t(C_Int_t) Posix_Signal_handlee (C_Int_t signum) {
  /* XXX global state */
  static struct sigaction sa;

  sigaddset (GC_getSignalsHandledAddr (&gcState), signum);
  memset (&sa, 0, sizeof(sa));
  /* The mask must be full because GC_handler reads and writes 
   * s->signalsPending (else there is a race condition).
   */
  sigfillset (&sa.sa_mask);
  sa.sa_handler = handler;
  sa.sa_flags = SA_FLAGS;
  return sigaction (signum, &sa, NULL);
}

void Posix_Signal_handleGC (void) {
  GC_setGCSignalHandled (&gcState, TRUE);
}

C_Int_t Posix_Signal_isPending (C_Int_t signum) {
  return sigismember (GC_getSignalsPendingAddr (&gcState), signum);
}

C_Int_t Posix_Signal_isPendingGC (void) {
  return GC_getGCSignalPending (&gcState);
}

void Posix_Signal_resetPending (void) {
  sigemptyset (GC_getSignalsPendingAddr (&gcState));
  GC_setGCSignalPending (&gcState, FALSE);
}

/* XXX global state */
static sigset_t set;

C_Errno_t(C_Int_t) Posix_Signal_sigaddset (C_Signal_t signum) {
  return sigaddset (&set, signum);
}

C_Errno_t(C_Int_t) Posix_Signal_sigdelset (C_Signal_t signum) {
  return sigdelset (&set, signum);
}

C_Errno_t(C_Int_t) Posix_Signal_sigemptyset (void) {
  return sigemptyset (&set);
}

C_Errno_t(C_Int_t) Posix_Signal_sigfillset (void) {
  return sigfillset (&set);
}

C_Errno_t(C_Int_t) Posix_Signal_sigismember (C_Signal_t signum) {
  return sigismember (&set, signum);
}

C_Errno_t(C_Int_t) Posix_Signal_sigprocmask (C_Int_t how) {
  return sigprocmask (how, &set, &set);
}

void Posix_Signal_sigsuspend (void) {
  int res;

  res = sigsuspend (&set);
  assert (-1 == res);
}
