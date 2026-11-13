// N64 RDP spike: benchmark runner shared by the Mac CLI (bench_mac.c) and the N64Bench iOS app.
// Part of Relics: Games (GPLv3). Throwaway spike code, see docs/n64-rdp-spike.md.
#ifndef N64BENCH_H
#define N64BENCH_H
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif

/// Called on the bench thread every 15 frames: a status line and the current 320x240 0xAARRGGBB frame.
typedef void (*N64BenchProgress)(const char* line, const uint32_t* frame, void* ctx);

/// Runs our bench ROM (Spikes/N64RDP/rom/n64_rdpbench.z64) through its three load levels, unthrottled, and writes
/// a plain-text report into `report`. `dataDir` holds mupen64plus.ini; `workDir` is a scratch directory.
/// Returns false if the machine or the RDP couldn't start (the report says why).
bool n64bench_run(const uint8_t* rom, size_t romSize, const char* workDir, const char* dataDir, bool synchronous,
                  N64BenchProgress progress, void* ctx, char* report, size_t reportCap);

#ifdef __cplusplus
}
#endif
#endif
