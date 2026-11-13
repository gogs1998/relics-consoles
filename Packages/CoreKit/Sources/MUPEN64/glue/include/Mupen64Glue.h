// Our C interface to the vendored mupen64plus core + rsp-hle (Nintendo 64). Not part of mupen64plus.
// Swift imports only this header; none of mupen64plus's own headers are exposed.
//
// mupen64plus keeps one machine in process-wide globals, so only one handle may exist at a time
// (`n64_create` returns NULL while another is alive). The machine runs on a private thread; every
// call here is made from one host thread and returns with that private thread parked at a frame
// boundary (inside the vertical interrupt), so nothing races.
//
// No Nintendo files are ever involved: the core's HLE boot replaces the PIF boot ROM, RSP audio tasks are
// high-level emulated (graphics tasks run on cxd4's interpreter), and the CPU is the cached interpreter (no recompiler, no executable memory).
// The plugins are linked statically: the core's dynamic-library hooks resolve against tables here.
#ifndef MUPEN64_GLUE_H
#define MUPEN64_GLUE_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct N64Handle N64Handle;

enum {
    N64_SCREEN_WIDTH = 320,
    N64_SCREEN_HEIGHT = 240,
    N64_MAX_PLAYERS = 4,
};

/// Controller buttons (the N64 controller status word's order). Set = pressed.
enum {
    N64_BTN_DRIGHT = 1 << 0,
    N64_BTN_DLEFT = 1 << 1,
    N64_BTN_DDOWN = 1 << 2,
    N64_BTN_DUP = 1 << 3,
    N64_BTN_START = 1 << 4,
    N64_BTN_Z = 1 << 5,
    N64_BTN_B = 1 << 6,
    N64_BTN_A = 1 << 7,
    N64_BTN_CRIGHT = 1 << 8,
    N64_BTN_CLEFT = 1 << 9,
    N64_BTN_CDOWN = 1 << 10,
    N64_BTN_CUP = 1 << 11,
    N64_BTN_R = 1 << 12,
    N64_BTN_L = 1 << 13,
};

/// Builds the machine around a copy of `rom` (big-endian .z64 order; the core also accepts the
/// byte-swapped orders) and boots it. `battery` (may be NULL) is a blob from `n64_battery`.
/// `workDir` is an empty private directory for the core's scratch files (config, save memory,
/// state files); `dataDir` holds the ROM database `mupen64plus.ini`.
/// Returns NULL if the ROM is rejected or another handle is alive.
N64Handle* n64_create(const uint8_t* rom, size_t romSize, const uint8_t* battery, size_t batterySize,
                      const char* workDir, const char* dataDir);
void n64_destroy(N64Handle* h);

/// Hard reset (power cycle) at the start of the next frame. Save memory is kept.
void n64_reset(N64Handle* h);

/// Sets controller `port` (0-3): N64_BTN_* bits and the analog stick (-128...127, up is positive).
void n64_set_input(N64Handle* h, int port, uint32_t buttons, int8_t x, int8_t y);

/// Runs until the next vertical interrupt (one video field: 1/60 s NTSC, 1/50 s PAL).
void n64_run_frame(N64Handle* h);

/// 320 x 240 pixels, little-endian 0xAARRGGBB words: the VI's framebuffer as the video interface
/// scans it out of RDRAM, scaled to 320 x 240.
const uint32_t* n64_framebuffer(const N64Handle* h);

/// Video fields per second (60 NTSC, 50 PAL), from the cartridge's region.
double n64_frame_rate(const N64Handle* h);

/// Mono float samples at 48 kHz produced since the last drain/discard.
size_t n64_drain_audio(N64Handle* h, const float** out);
void n64_discard_audio(N64Handle* h);
/// The rate the game last programmed into the audio interface (Hz), 0 before it has.
uint32_t n64_audio_rate(const N64Handle* h);

/// The cartridge and Controller Pak save memory the game has written so far, as one blob
/// (malloc'd; free with `n64_free`). Returns 0 when nothing has been written.
size_t n64_battery(N64Handle* h, uint8_t** out);

/// Serialises the machine (a mupen64plus savestate) into a malloc'd buffer. Returns 0 on failure.
size_t n64_save_state(N64Handle* h, uint8_t** out);
/// Loads a mupen64plus savestate; on failure the machine is left exactly as it was.
bool n64_load_state(N64Handle* h, const uint8_t* data, size_t size);

void n64_free(void* p);

uint32_t n64_frame_counter(const N64Handle* h);
/// Tests: reads the big-endian word at RDRAM physical address `address` (0-0x7FFFFF).
uint32_t n64_peek_rdram(const N64Handle* h, uint32_t address);

#ifdef __cplusplus
}
#endif

#include "N64BenchGlue.h"   // the hidden N64 speed test

#endif
