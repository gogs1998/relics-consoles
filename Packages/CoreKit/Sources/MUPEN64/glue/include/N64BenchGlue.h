// N64 speed test: runs our own bench ROM through paraLLEl-RDP + cxd4 and reports fps with a CPU/RSP/RDP/GPU
// breakdown (docs/n64-rdp-spike.md). Used by the hidden speed-test screen and Spikes/N64RDP's Mac CLI.
// Part of Relics: Games (GPLv3).
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

/// Runs our bench ROM (N64Core resource n64_rdpbench.z64, built by Tools/build_n64_bench_rom.py) through its three load levels, unthrottled, and writes
/// a plain-text report into `report`. `dataDir` holds mupen64plus.ini; `workDir` is a scratch directory.
/// Returns false if the machine or the RDP couldn't start (the report says why).
bool n64bench_run(const uint8_t* rom, size_t romSize, const char* workDir, const char* dataDir, bool synchronous,
                  N64BenchProgress progress, void* ctx, char* report, size_t reportCap);

#ifdef __cplusplus
}
#endif
#endif
