// Our C interface to the vendored mGBA core (GBA only). Not part of mGBA.
// Swift imports only this header; none of mGBA's own headers are exposed.
//
// A handle is confined to one thread. All buffers returned by pointer are owned by the handle
// and stay valid until the next call on it, except where noted (`mgba_free`).
#ifndef MGBA_GLUE_H
#define MGBA_GLUE_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct MGBAHandle MGBAHandle;

enum {
    MGBA_WIDTH = 240,
    MGBA_HEIGHT = 160,
};

/// GBA key bits (KEYINPUT order): A B Select Start Right Left Up Down R L.
enum {
    MGBA_KEY_A = 1 << 0,
    MGBA_KEY_B = 1 << 1,
    MGBA_KEY_SELECT = 1 << 2,
    MGBA_KEY_START = 1 << 3,
    MGBA_KEY_RIGHT = 1 << 4,
    MGBA_KEY_LEFT = 1 << 5,
    MGBA_KEY_UP = 1 << 6,
    MGBA_KEY_DOWN = 1 << 7,
    MGBA_KEY_R = 1 << 8,
    MGBA_KEY_L = 1 << 9,
};

/// True if `rom` looks like a GBA ROM to mGBA (fixed byte 0x96 at 0xB2, or a multiboot image).
bool mgba_is_rom(const uint8_t* rom, size_t size);

/// Builds a core around a copy of `rom`. `save` (may be NULL) is the battery save to start from.
/// Uses mGBA's built-in HLE BIOS; never reads a BIOS file. Returns NULL if the ROM is rejected.
MGBAHandle* mgba_create(const uint8_t* rom, size_t romSize, const uint8_t* save, size_t saveSize,
                        double audioRate);
void mgba_destroy(MGBAHandle* h);

void mgba_reset(MGBAHandle* h);
/// Runs one video frame with `keys` (MGBA_KEY_* bits) held.
void mgba_run_frame(MGBAHandle* h, uint32_t keys);

/// MGBA_WIDTH x MGBA_HEIGHT pixels as little-endian 0xAARRGGBB words (BGRA8 in memory).
const uint32_t* mgba_framebuffer(const MGBAHandle* h);

/// Mono float samples at `audioRate` produced since the last drain/discard.
/// Returns the count; `*out` points into the handle's buffer.
size_t mgba_drain_audio(MGBAHandle* h, const float** out);
void mgba_discard_audio(MGBAHandle* h);

/// Copies the cartridge save memory into a malloc'd buffer (free with `mgba_free`).
/// Returns 0 (and NULL) when the cartridge has no save memory (or hasn't used it yet).
size_t mgba_savedata(MGBAHandle* h, uint8_t** out);

/// Serialises the machine into a malloc'd buffer (free with `mgba_free`). Returns 0 on failure.
size_t mgba_save_state(MGBAHandle* h, uint8_t** out);
bool mgba_load_state(MGBAHandle* h, const uint8_t* data, size_t size);

void mgba_free(void* p);

/// Side-effect-free byte read of the bus (debugging and tests).
uint8_t mgba_peek(MGBAHandle* h, uint32_t address);
uint32_t mgba_frame_counter(const MGBAHandle* h);
/// mGBA's current native audio rate (Hz); depends on the game's SOUNDBIAS resolution.
uint32_t mgba_native_audio_rate(const MGBAHandle* h);

#ifdef __cplusplus
}
#endif

#endif
