// Our C interface to the vendored melonDS core (Nintendo DS mode only). Not part of melonDS.
// Swift imports only this header; none of melonDS's own headers are exposed.
//
// A handle is confined to one thread. Buffers returned by pointer are owned by the handle and stay
// valid until the next call on it, except where noted (`melonds_free`).
//
// No Nintendo files are ever involved: the core boots with melonDS's built-in FreeBIOS and a
// generated firmware image, and starts the cartridge directly (direct boot). The glue has no file
// access at all (every melonDS file hook returns "not found").
#ifndef MELONDS_GLUE_H
#define MELONDS_GLUE_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct MelonDSHandle MelonDSHandle;

enum {
    MELONDS_SCREEN_WIDTH = 256,
    MELONDS_SCREEN_HEIGHT = 192,
};

/// DS key bits (KEYINPUT order, then X and Y from EXTKEYIN). Set = pressed.
enum {
    MELONDS_KEY_A = 1 << 0,
    MELONDS_KEY_B = 1 << 1,
    MELONDS_KEY_SELECT = 1 << 2,
    MELONDS_KEY_START = 1 << 3,
    MELONDS_KEY_RIGHT = 1 << 4,
    MELONDS_KEY_LEFT = 1 << 5,
    MELONDS_KEY_UP = 1 << 6,
    MELONDS_KEY_DOWN = 1 << 7,
    MELONDS_KEY_R = 1 << 8,
    MELONDS_KEY_L = 1 << 9,
    MELONDS_KEY_X = 1 << 10,
    MELONDS_KEY_Y = 1 << 11,
};

/// True if `rom` has a plausible DS cartridge header (ARM9/ARM7 binaries inside the file).
bool melonds_is_rom(const uint8_t* rom, size_t size);

/// Builds a DS around a copy of `rom` and direct-boots it. `save` (may be NULL) is the battery
/// save to start from. `threaded3D` runs the software 3D rasteriser on its own thread.
/// Returns NULL if melonDS rejects the ROM (or it is a DSi-only title).
MelonDSHandle* melonds_create(const uint8_t* rom, size_t romSize, const uint8_t* save, size_t saveSize,
                              double audioRate, bool threaded3D);
void melonds_destroy(MelonDSHandle* h);

/// Power-cycles and direct-boots the cartridge again (the save memory is kept).
void melonds_reset(MelonDSHandle* h);

/// Runs one video frame with `keys` (MELONDS_KEY_* bits) held and the stylus down at (x, y)
/// on the touch screen when `touching` (x 0-255, y 0-191).
void melonds_run_frame(MelonDSHandle* h, uint32_t keys, bool touching, uint16_t x, uint16_t y);

/// 256 x 384 pixels as little-endian 0xAARRGGBB words: the top screen (rows 0-191) above the
/// touch screen (rows 192-383).
const uint32_t* melonds_framebuffer(const MelonDSHandle* h);

/// Mono float samples at `audioRate` produced since the last drain/discard.
size_t melonds_drain_audio(MelonDSHandle* h, const float** out);
void melonds_discard_audio(MelonDSHandle* h);

/// Copies the cartridge save memory into a malloc'd buffer (free with `melonds_free`).
/// Returns 0 when the cartridge has none.
size_t melonds_savedata(MelonDSHandle* h, uint8_t** out);

/// Serialises the machine (a melonDS savestate) into a malloc'd buffer. Returns 0 on failure.
size_t melonds_save_state(MelonDSHandle* h, uint8_t** out);
/// Loads a melonDS savestate; on failure the machine is left exactly as it was.
bool melonds_load_state(MelonDSHandle* h, const uint8_t* data, size_t size);

void melonds_free(void* p);

uint32_t melonds_frame_counter(const MelonDSHandle* h);
/// Tests: reads a word of main RAM (address 0x02000000-0x02FFFFFF, mirrored) without side effects.
uint32_t melonds_peek_main_ram(const MelonDSHandle* h, uint32_t address);

#ifdef __cplusplus
}
#endif

#endif
