# ares (vendored: SNES and Mega Drive cores)

- Upstream: https://github.com/ares-emulator/ares
- Snapshot: commit `0b92893` (shallow clone, approved by Gordon; the clone lives in the gitignored
  `ThirdParty-src/ares` and was never built with its own CMake or scripts — sources were read and copied only)
- Licence: ISC (`LICENSE` here, the upstream file unchanged; it also carries the MAME BSD-3-Clause
  notice and the notices for parts we do NOT vendor: sljit, libchdr, LZMA, zlib, xxHash, MoltenVK, ...).
  ISC needs the copyright + permission notice kept in copies: the app's acknowledgements must show the
  ares ISC notice, the MAME BSD-3-Clause notice (see below) and the qon MIT notice (`LICENSE-qon.txt`).

## Layout

SwiftPM can't reach outside the package, so the vendored sources live **inside the package**,
unmodified, at `Packages/CoreKit/Sources/ARES/ares/` with the upstream repository layout
(`ares/ares`, `ares/sfc`, `ares/md`, `ares/component/...`, `nall/nall`, `libco`, `thirdparty/qon`,
`mia/Database`). Only our own files are compiled (`Package.swift` target `ARES`, `sources:` =
`glue/units` + `glue/src`); each build unit `#include`s one upstream `.cpp`. Ours, not ares:

- `glue/include/AresGlue.h`, `glue/src/ares_glue.cpp`: the plain C API Swift sees, and our
  `ares::Platform` (all data from memory, no files, no firmware). Contains a port of ares' cartridge
  heuristics from `mia/medium/super-famicom.cpp` and `mia/medium/mega-drive.cpp` (ISC; reduced).
- `glue/src/ares_core.cpp`: replaces the CMake-generated `ares/ares.cpp` (template `ares/ares/ares.cpp.in`)
  without the GDB server (TCP) and the generated resources; our `FixedAllocator` (never executable).
- `glue/units/nall.cpp`: replaces `nall/nall.cpp` (not vendored: it also builds a TCP server).
- `glue/shim/` (first on the include path): `sljit.h` (empty; no JIT), `nall/recompiler/generic/generic.hpp`
  (stub with `supported = false`), `recompiler.cpp` + `xxhash.h` (stand-ins for the SH-2 recompiler,
  which is not vendored: upstream `sh2.cpp`'s `#include "recompiler.cpp"` falls through to this stub of
  aborting functions, all unreachable because `SH2::Accuracy::Recompiler` is a compile-time false),
  `ares/resource/resource.hpp` (empty crosshair sprites), `ares_prelude.h` (see iOS below).
- `Sources/AresCore/AresSystems.swift`: `SNESSystem`, `MDSystem` (`EmulatorCore`).

Build settings: C++20 (package-level), `-O2 -w` in every configuration, `PROFILE_PERFORMANCE`,
`CORE_SFC`, `CORE_MD`, `NDEBUG`; libco with `LIBCO_MP` (thread-local active context).

## Patches

**None.** Every vendored file is byte-identical to upstream `0b92893`. (If one ever has to change, put a
unified diff in `patches/NNN-name.patch` and list it here.) Vendored for reference but not compiled:
`ares/ares/ares.cpp.in` (template), `ares/ares/memory/fixed-allocator.cpp` (replaced), nall's `dl.cpp`
and `run.cpp`. Upstream `component/processor/sh2/sh2.cpp` is compiled unmodified through the shims.

## Licence audit (every included directory)

| Vendored path | Licence | Notes |
|---|---|---|
| `ares/ares` (framework: nodes, scheduler, platform, debug) | ISC | no `resource/` (PNG artwork, generated) |
| `ares/sfc` (SNES incl. coprocessor code) | ISC | |
| `ares/md` (Mega Drive incl. 32X/Mega CD/Mega LD code, which compiles in but is unusable without firmware) | ISC | |
| `ares/component/processor/{wdc65816,spc700,arm7tdmi,gsu,hg51b,upd96050}` | ISC | SNES CPUs/coprocessors |
| `ares/component/processor/{m68000,z80,sh2,ssp1601}` | ISC | `sh2/recompiler.cpp` **not vendored** |
| `ares/component/processor/z80/sega/{s315-5114,s315-5177,mc8123}.cpp` | BSD-3-Clause (MAME-derived) | Sega arcade/System E decryption, compiled with the Z80; notice in `LICENSE` ("MAME-derived ROM decryption") |
| `ares/component/audio/{sn76489,ym2612}`, `ares/component/eeprom/m24c` | ISC | |
| `nall/nall` (minus `windows/ xorg/ http/ smtp.* tcptext/ gdb/ recompiler/ cmake/ main.cpp nall.cpp sljitAllocator.cpp`) | ISC | one comment in `thread.hpp` mentions win32-pthreads being GPL (Windows only, not used) |
| `libco/{libco.c,libco.h,settings.h,aarch64.c,amd64.c}` | ISC | |
| `thirdparty/qon` | MIT (Roger Sanders; QOI by Dominic Szablewski) | `LICENSE-qon.txt` |
| `mia/Database/Super Famicom Boards.bml` | ISC | board memory maps, embedded with `#embed` |

Excluded on purpose: `thirdparty/sljit` (JIT; App Store forbids JIT), every recompiler
(`nall/recompiler`, SH-2 `recompiler.cpp`), N64/PS1/Saturn and all other cores, `thirdparty/{libchdr,
librashader,ymfm,TZXFile,GL,KHR,sse2neon.h,xxhash.h}`, `desktop-ui`, `hiro`, `ruby`, `mia` program code,
`tools`, `tests`, and **all firmware**: `ares/System/*` and `mia/Firmware/*` (SPC700 IPL, TMSS, SVP, DSP-n,
ST01x, Cx4, SGB, 32X, ...). No GPL/LGPL/non-commercial code is included (grep of the vendored tree:
the only "GPL" hit is that comment).

## Firmware: what we never ship and what it costs

- **SPC700 IPL boot ROM** (64 bytes, needed by *every* SNES game): replaced by **our own** boot program
  (`kBootProgram` in `ares_glue.cpp`, assembly in the comment), written from the documented upload
  protocol, not from Nintendo's ROM. The test ROM uploads its sound program through it. Decision for
  Gordon: this is a clean-room functional replacement (like mGBA's HLE BIOS); a game that jumps into the
  middle of the original ROM or reads its bytes would misbehave (none known among common titles).
- SNES coprocessors whose programs are chip firmware are **refused** (`AresError.needsFirmware`) unless
  the player's own dump has the firmware appended (as some dumps do): DSP-1/1A/1B (Super Mario Kart,
  Pilotwings, Super Air Diver, Ballz 3D, Suzuka 8 Hours, ...), DSP-2 (Dungeon Master), DSP-3 (SD Gundam GX),
  DSP-4 (Top Gear 3000), ST010 (F1 ROC II), ST011 (Hayazashi Nidan Morita Shougi), ST018 (Hayazashi Nidan
  Morita Shougi 2), Cx4 (Mega Man X2, Mega Man X3), Super Game Boy (also needs a GB core).
  Supported without firmware: SA-1, Super FX (GSU), S-DD1, SPC7110, OBC1, S-RTC/Epson RTC (clock not saved).
- Mega Drive: TMSS off (no TMSS ROM). SVP (Virtua Racing) needs `svp.rom` firmware: not supported (loads,
  but the DSP has no program). 32X and Mega CD need BIOS: not supported (the code is compiled but never used).

## iOS / App Store

- No JIT, no sljit, no executable memory: every TU starts with `glue/shim/ares_prelude.h`, which compiles
  nall's `memory::map/protect` with `PROT_EXEC` and `MAP_JIT` defined to 0 and turns
  `pthread_jit_write_protect_np` into a no-op; `FixedAllocator` is ours and empty.
- libco's aarch64 context switch is a constant array placed in `__TEXT,__text` (signed with the app;
  no `mprotect`, `LIBCO_MPROTECT` not defined). Stacks are malloc'd (128 KiB per emulated thread).
- `dlopen` appears in the binary only through nall's `library` (used by the SNES "21FX" developer
  expansion port, never connected); `mmap` only for non-executable allocations and Mega CD image mapping.
- ares spawns one thread per screen (`Video::Threaded`) that converts the frame; the glue waits for it
  each frame, so the C API stays synchronous.
- All ARES units syntax-check against the iPhoneOS 27.1 SDK (arm64-apple-ios26.0); not yet built in the app.

## Known gaps

EEPROM saves on a few Mega Drive sports titles (ares finds them by hash in a database we don't ship);
the six-button-incompatible Mega Drive games ares special-cases (we always attach the 6-button pad);
RTC time is not persisted; Satellaview / Sufami Turbo / MSU-1 not supported; the SNES uses ares' fast
scanline PPU ("Pixel Accuracy" off), the Mega Drive ares' cycle-accurate VDP.
