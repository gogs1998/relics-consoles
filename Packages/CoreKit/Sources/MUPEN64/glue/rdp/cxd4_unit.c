// Build unit for cxd4's RSP interpreter (mupen64plus-rsp-cxd4, CC0), vendored unmodified in
// Sources/MUPEN64/rsp-cxd4 and compiled through its own unity file lto.c. Part of Relics: Consoles (GPLv3).
//
// - The plugin entry points and cxd4's core-function pointers get a cxd4_ prefix (statically linked plugins share
//   one namespace with mupen64plus-core and rsp-hle).
// - cxd4 must never touch the process's signal handling (crash reporting, the debugger, other code):
//   * InitiateRSP probes the RDRAM size by installing a SIGSEGV handler and reading in 2 MB steps until it
//     faults. Here sigaction() does nothing and sigsetjmp() reports "already faulted", so no handler is ever
//     installed and no memory outside RDRAM is read; rsp_dispatch.c sets the size (su_max_address) afterwards.
//   * InitiateRSP also installs a permanent SIGILL handler (a warning for SSE builds on old x86 CPUs); here
//     signal() does nothing.
//   * init_regs() reseeds the C library's rand() from the clock; here srand() does nothing (rand() is only used
//     to fill the RSP's power-on register contents).
//   The system headers are included first so these macros only affect cxd4's own code.
#include <setjmp.h>
#include <signal.h>
#include <stdlib.h>
#define sigsetjmp(env, savemask) 1
#define sigaction(sig, act, oldact) ((void)(sig), (void)(act), (void)(oldact), 0)
#define signal(sig, handler) ((void)(sig), (void)(handler), SIG_DFL)
#define srand(seed) ((void)(seed))
#define M64P_PLUGIN_API 1

#define PluginStartup cxd4_PluginStartup
#define PluginShutdown cxd4_PluginShutdown
#define PluginGetVersion cxd4_PluginGetVersion
#define DoRspCycles cxd4_DoRspCycles
#define InitiateRSP cxd4_InitiateRSP
#define RomClosed cxd4_RomClosed
#define RomOpen cxd4_RomOpen
#define ConfigOpenSection cxd4_ConfigOpenSection
#define ConfigDeleteSection cxd4_ConfigDeleteSection
#define ConfigSetParameter cxd4_ConfigSetParameter
#define ConfigGetParameter cxd4_ConfigGetParameter
#define ConfigSetDefaultFloat cxd4_ConfigSetDefaultFloat
#define ConfigSetDefaultBool cxd4_ConfigSetDefaultBool
#define ConfigGetParamBool cxd4_ConfigGetParamBool
#define CoreDoCommand cxd4_CoreDoCommand

#include "../../rsp-cxd4/lto.c"

void cxd4_set_rdram_mask(unsigned long mask) { su_max_address = mask; }
