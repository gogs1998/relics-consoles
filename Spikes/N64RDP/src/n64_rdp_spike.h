// N64 RDP feasibility spike (throwaway, see docs/n64-rdp-spike.md). Part of Relics: Games (GPLv3).
//
// Connects our mupen64plus glue to paraLLEl-RDP (MIT, Vulkan compute, on MoltenVK) for the RDP and to cxd4's RSP
// interpreter (CC0) for graphics tasks; audio and other tasks still go to rsp-hle. Compiled only when
// N64_RDP_SPIKE is defined (the Mac bench in Spikes/N64RDP/build_mac.sh and the N64Bench iOS app); the shipping
// CoreKit MUPEN64 target never defines it, so the app is unaffected.
#ifndef N64_RDP_SPIKE_H
#define N64_RDP_SPIKE_H

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Accumulated since the last n64spike_take_stats (milliseconds are totals, not per frame).
typedef struct N64SpikeStats {
    uint32_t frames;        // VI scan-outs
    double rspMs;           // cxd4 running graphics tasks, minus the RDP work nested inside it
    double hleMs;           // rsp-hle (audio and other non-graphics tasks)
    double rdpEnqueueMs;    // ProcessRDPList on the emulation thread: copying + queueing commands
    double rdpSyncMs;       // waiting for the GPU at SyncFull (synchronous mode only)
    double viMs;            // VI scan-out: GPU filter pass + readback + conversion to 320x240
    double gpuRenderMs;     // GPU time of paraLLEl-RDP render passes (Vulkan timestamps; 0 if unavailable)
    uint64_t rdpWords;      // 64-bit RDP command words processed
    uint64_t triangles;     // RDP triangle commands
    uint64_t syncFulls;
} N64SpikeStats;

// MARK: called by the glue (n64_glue.c, N64_RDP_SPIKE only)

/// `gfxInfo` is the core's GFX_INFO. Creates the Vulkan device and the paraLLEl-RDP command processor.
bool n64spike_gfx_init(const void* gfxInfo);
void n64spike_gfx_shutdown(void);
void n64spike_process_rdp_list(void);
/// Runs the VI on the GPU and writes `width` x `height` 0xAARRGGBB pixels. False when the RDP isn't running.
bool n64spike_scan_out(uint32_t* fb, int width, int height);

/// RSP dispatcher: graphics tasks (OSTask type 1) go to cxd4, everything else to rsp-hle.
void n64spike_rsp_startup(void* coreHandle, void (*debug)(void*, int, const char*));
void n64spike_rsp_shutdown(void);
unsigned int n64spike_rsp_DoRspCycles(unsigned int cycles);
void n64spike_rsp_InitiateRSP(const void* rspInfo, unsigned int* cycleCount);   // RSP_INFO*
void n64spike_rsp_RomClosed(void);

// MARK: bench control

/// Synchronous (default): the emulation thread waits for the GPU at every SyncFull, like a game that reads
/// back what the RDP drew. Asynchronous: only the VI scan-out waits.
void n64spike_set_synchronous(bool on);
void n64spike_take_stats(N64SpikeStats* out);
/// Vulkan device name, RDRAM import mode etc. (valid after n64spike_gfx_init).
const char* n64spike_device_info(void);

// internal: timing shared between the RSP dispatcher and the RDP side
double n64spike_now_ms(void);
double n64spike_rdp_nested_ms(void);   // running total of time spent in n64spike_process_rdp_list
void n64spike_add_rsp_ms(double ms, bool hle);

#ifdef __cplusplus
}
#endif

#endif
