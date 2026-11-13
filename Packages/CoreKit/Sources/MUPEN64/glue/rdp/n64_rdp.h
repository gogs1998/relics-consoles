// Our paraLLEl-RDP + cxd4 layer under the mupen64plus glue. Part of Relics: Games (GPLv3).
//
// Connects the glue to paraLLEl-RDP (MIT, Vulkan compute, on MoltenVK) for the RDP and to cxd4's RSP interpreter
// (CC0) for graphics tasks; audio and other tasks still go to rsp-hle. Without Vulkan (simulator, Mac tests)
// n64rdp_gfx_init fails and the glue falls back to scanning the VI framebuffer out of RDRAM.
#ifndef N64_RDP_H
#define N64_RDP_H

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Accumulated since the last n64rdp_take_stats (milliseconds are totals, not per frame).
typedef struct N64RdpStats {
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
} N64RdpStats;

// MARK: called by the glue (n64_glue.c)

/// `gfxInfo` is the core's GFX_INFO. Creates the Vulkan device and the paraLLEl-RDP command processor.
bool n64rdp_gfx_init(const void* gfxInfo);
/// Saves the pipeline cache, waits for the GPU and tears the renderer down. Safe when init failed.
void n64rdp_gfx_shutdown(void);

/// Why the RDP is or isn't running (N64_RENDERER_* in Mupen64Glue.h); the reason is in n64rdp_device_info.
int n64rdp_status(void);
/// The pipeline cache file (empty or NULL = none). Read at the next n64rdp_gfx_init.
void n64rdp_set_pipeline_cache_path(const char* path);
/// Writes the pipeline cache now if it grew since the last write. CPU only (no GPU work, so it is safe while the
/// app is going to the background). Call only while the core thread is parked or from the core thread.
void n64rdp_save_pipeline_cache(void);
void n64rdp_process_rdp_list(void);
/// A save state was loaded: drop any half-received RDP command carried over from before it.
void n64rdp_state_loaded(void);
/// Runs the VI on the GPU and writes `width` x `height` 0xAARRGGBB pixels (the VI's 640 x 480 or 640 x 576 output
/// resampled; both are 4:3). Then waits for the RDP timeline, so at return no GPU work or RDRAM writeback is in flight
/// (save states are taken at this boundary). False when the RDP isn't running.
bool n64rdp_scan_out(uint32_t* fb, int width, int height);

/// RSP dispatcher: graphics tasks (OSTask type 1) go to cxd4, everything else to rsp-hle.
void n64rdp_rsp_startup(void* coreHandle, void (*debug)(void*, int, const char*));
void n64rdp_rsp_shutdown(void);
unsigned int n64rdp_rsp_DoRspCycles(unsigned int cycles);
void n64rdp_rsp_InitiateRSP(const void* rspInfo, unsigned int* cycleCount);   // RSP_INFO*
void n64rdp_rsp_RomClosed(void);

// MARK: bench control

/// Synchronous (default): the emulation thread waits for the GPU at every SyncFull, like a game that reads
/// back what the RDP drew. Asynchronous: only the VI scan-out waits.
void n64rdp_set_synchronous(bool on);
void n64rdp_take_stats(N64RdpStats* out);
/// Vulkan device name, RDRAM import mode etc. (valid after n64rdp_gfx_init).
const char* n64rdp_device_info(void);

// internal: timing shared between the RSP dispatcher and the RDP side
double n64rdp_now_ms(void);
double n64rdp_rdp_nested_ms(void);   // running total of time spent in n64rdp_process_rdp_list
void n64rdp_add_rsp_ms(double ms, bool hle);

#ifdef __cplusplus
}
#endif

#endif
