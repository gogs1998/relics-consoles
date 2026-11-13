// Build unit for cxd4's RSP interpreter (mupen64plus-rsp-cxd4, CC0), compiled unmodified from
// ThirdParty-src/mupen64plus-rsp-cxd4 through its own unity file lto.c. N64 RDP spike only. Part of Relics: Games (GPLv3).
//
// - The plugin entry points and cxd4's core-function pointers get a cxd4_ prefix (statically linked plugins share
//   one namespace with mupen64plus-core and rsp-hle).
// - sigsetjmp is forced to "already faulted": InitiateRSP otherwise probes the RDRAM size by reading 2 MB steps
//   until it takes a SIGSEGV, which a debugger (Xcode on the iPhone) stops on. rsp_dispatch.c sets the size
//   (su_max_address) itself afterwards.
#include <setjmp.h>
#define sigsetjmp(env, savemask) 1

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

#include "lto.c"

void cxd4_set_rdram_mask(unsigned long mask) { su_max_address = mask; }
