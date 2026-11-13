// RSP dispatcher (Relics: Games, GPLv3). Graphics tasks (OSTask type 1 at DMEM 0xFC0) run on cxd4's interpreter (LLE),
// so the RDP gets the real command stream; audio and everything else stay on rsp-hle. Part of Relics: Games (GPLv3).
#define M64P_PLUGIN_PROTOTYPES 1
#include <string.h>

#include "api/m64p_plugin.h"
#include "api/m64p_types.h"
#include "n64_rdp.h"

// rsp-hle (renamed by glue/units/rsphle_plugin.c) and cxd4 (renamed by cxd4_unit.c)
unsigned int rsphle_DoRspCycles(unsigned int);
void rsphle_InitiateRSP(RSP_INFO, unsigned int*);
void rsphle_RomClosed(void);
m64p_error cxd4_PluginStartup(m64p_dynlib_handle, void*, void (*)(void*, int, const char*));
m64p_error cxd4_PluginShutdown(void);
unsigned int cxd4_DoRspCycles(unsigned int);
void cxd4_InitiateRSP(RSP_INFO, unsigned int*);
void cxd4_RomClosed(void);
void cxd4_set_rdram_mask(unsigned long mask);

static RSP_INFO g_rsp;

void n64rdp_rsp_startup(void* coreHandle, void (*debug)(void*, int, const char*))
{
    cxd4_PluginStartup((m64p_dynlib_handle)coreHandle, NULL, debug);
}

void n64rdp_rsp_shutdown(void) { cxd4_PluginShutdown(); }

unsigned int n64rdp_rsp_DoRspCycles(unsigned int cycles)
{
    uint32_t type = 0;
    if (g_rsp.DMEM) memcpy(&type, g_rsp.DMEM + 0xFC0, 4);   // host-order word = the task type
    const double t0 = n64rdp_now_ms();
    const double nested0 = n64rdp_rdp_nested_ms();
    unsigned int r;
    if (type == 1) r = cxd4_DoRspCycles(cycles);
    else r = rsphle_DoRspCycles(cycles);
    const double dt = n64rdp_now_ms() - t0 - (n64rdp_rdp_nested_ms() - nested0);
    n64rdp_add_rsp_ms(dt, type != 1);
    return r;
}

void n64rdp_rsp_InitiateRSP(const void* info, unsigned int* cycleCount)
{
    g_rsp = *(const RSP_INFO*)info;
    rsphle_InitiateRSP(g_rsp, cycleCount);
    cxd4_InitiateRSP(g_rsp, cycleCount);
    cxd4_set_rdram_mask(0x7FFFFF);   // 8 MB (the probe is disabled in cxd4_unit.c)
}

void n64rdp_rsp_RomClosed(void)
{
    rsphle_RomClosed();
    cxd4_RomClosed();
}
