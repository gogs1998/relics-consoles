// Our C interface to the vendored ares cores (SNES and Mega Drive). Not part of ares.
// Swift imports only this header; none of ares' own (C++) headers are exposed.
//
// ares keeps each system's hardware in process-wide globals (one SNES, one Mega Drive) and
// reports through one global `ares::platform` pointer, so only ONE handle may be alive per process
// at a time: `ares_create` fails (returns NULL, error "busy") while another handle exists.
// A handle is confined to one thread. Buffers returned by pointer are owned by the handle and stay
// valid until the next call on it, except where noted (`ares_free`).
#ifndef ARES_GLUE_H
#define ARES_GLUE_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct AresHandle AresHandle;

typedef enum {
    ARES_SYSTEM_SNES = 1,
    ARES_SYSTEM_MD = 2,
} AresSystem;

/// Button bits. SNES uses the SNES names; the Mega Drive uses its 6-button pad names.
enum {
    ARES_BTN_UP = 1 << 0,
    ARES_BTN_DOWN = 1 << 1,
    ARES_BTN_LEFT = 1 << 2,
    ARES_BTN_RIGHT = 1 << 3,
    ARES_BTN_START = 1 << 4,
    ARES_BTN_SELECT = 1 << 5,  // SNES Select / Mega Drive Mode
    ARES_SNES_B = 1 << 6,
    ARES_SNES_Y = 1 << 7,
    ARES_SNES_A = 1 << 8,
    ARES_SNES_X = 1 << 9,
    ARES_SNES_L = 1 << 10,
    ARES_SNES_R = 1 << 11,
    ARES_MD_A = 1 << 6,
    ARES_MD_B = 1 << 7,
    ARES_MD_C = 1 << 8,
    ARES_MD_X = 1 << 9,
    ARES_MD_Y = 1 << 10,
    ARES_MD_Z = 1 << 11,
};

/// Builds a console around a copy of `rom` (an SNES image may carry a 512-byte copier header).
/// `save` (may be NULL) is the battery save to start from. Never reads files or firmware.
/// On failure returns NULL and writes a short reason into `error` (if non-NULL):
/// "busy", "rom", "firmware" (the cartridge needs a coprocessor program we don't ship) or "load".
AresHandle* ares_create(AresSystem system, const uint8_t* rom, size_t romSize,
                        const uint8_t* save, size_t saveSize, double audioRate,
                        char* error, size_t errorSize);
void ares_destroy(AresHandle* h);

void ares_reset(AresHandle* h);
/// Runs one video frame with `buttons` (ARES_BTN_* / ARES_SNES_* / ARES_MD_* bits) held.
void ares_run_frame(AresHandle* h, uint32_t buttons);

/// Sets the buttons held on controller `port` (0 = port 1, 1 = port 2; others ignored).
/// Both ports have a pad connected: SNES gamepads, Mega Drive 6-button pads.
/// `ares_run_frame` overwrites port 1 only; port 2 keeps the last value set here.
void ares_set_input(AresHandle* h, uint32_t port, uint32_t buttons);
/// Runs one video frame with the buttons set by `ares_set_input`.
void ares_run_frame_ports(AresHandle* h);
/// Debug/tests: how many button reads the core made from `port` during the last frame, and in
/// `*seen` (if non-NULL) the pressed button bits it read. 0 reads = the game didn't poll that port.
uint32_t ares_debug_port_reads(const AresHandle* h, uint32_t port, uint32_t* seen);

/// The last frame as little-endian 0xAARRGGBB words (BGRA8 in memory), `*width` x `*height`.
/// SNES: 256x224 (512 wide in hi-res modes, 239/478 lines with overscan/interlace).
/// Mega Drive: 320 or 256 wide x 224 (240 on PAL in V30, doubled when interlaced).
const uint32_t* ares_framebuffer(const AresHandle* h, uint32_t* width, uint32_t* height);

/// Mono float samples at `audioRate` produced since the last drain/discard.
size_t ares_drain_audio(AresHandle* h, const float** out);
void ares_discard_audio(AresHandle* h);

/// Copies the cartridge's save RAM into a malloc'd buffer (free with `ares_free`).
/// Returns 0 when the cartridge has no save RAM.
size_t ares_battery(AresHandle* h, uint8_t** out);

/// Serialises the machine (ares' own serializer) into a malloc'd buffer. Returns 0 on failure.
size_t ares_save_state(AresHandle* h, uint8_t** out);
bool ares_load_state(AresHandle* h, const uint8_t* data, size_t size);

void ares_free(void* p);

/// The console's video refresh rate (Hz), from the core (NTSC ~60.1/59.92, PAL ~50).
double ares_frame_rate(const AresHandle* h);
uint32_t ares_frame_counter(const AresHandle* h);
/// True if the loaded game runs in a PAL region.
bool ares_is_pal(const AresHandle* h);

#ifdef __cplusplus
}
#endif

#endif
