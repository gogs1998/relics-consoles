# mupen64plus (vendored, Nintendo 64, cached interpreter)

- Upstream: https://github.com/mupen64plus/mupen64plus-core (commit `daae68e`) and
  https://github.com/mupen64plus/mupen64plus-rsp-hle (commit `4cdc305`), cloned (shallow) into the gitignored
  `ThirdParty-src/`; never built with their own Makefiles.
- Licence: GPL-2.0-or-later (every source file's header says "either version 2 of the License, or (at your
  option) any later version"; the top-level LICENSES files just say "GPL version 2"). Foldback is GPLv3, so we
  take the "or later" option; the whole app's source (including this snapshot) must be offered with any public build.

## Video: GLideN64 is NOT used (licence)

The plan was mupen64plus + GLideN64 + rsp-hle. GLideN64 (cloned at `a04081a`) cannot go into a GPLv3 app:
its `LICENSE` says "GLideN64 is licensed under the GNU General Public License version 2." with no "or later"
grant, and its ~256 core source files carry no licence header at all (only the bundled mupen64plus API headers,
`winlnxdefs.h` and GLideNHQ say "or any later version"). GPLv2 §9: a program that names a version without "any
later version" is under that version only, and GPL-2.0-only code can't be combined with GPLv3 code. So nothing
of GLideN64 is vendored. (Its bundled parts were also checked: GLSL-FXAA MIT, Glow MIT-style, readerwriterqueue
BSD-2, gles2n64 LGPL-3, GlideHQ/GLideNHQ GPL-2-or-later; all would have been fine on their own; the blocker is
GLideN64's own code.)

Instead our video plugin (`glue/src/n64_glue.c`) is a VI scan-out: at each vertical interrupt it reads the
framebuffer the VI points at in RDRAM (16-bit 5551 or 32-bit) and scales it to 320x240. Anything the CPU draws
shows; **RDP-rendered graphics (essentially every commercial game's 3D and most 2D) do not**, because no RDP
renderer is linked. Options for a real renderer (each needs Gordon's approval to download):
- **paraLLEl-RDP** (MIT) on Vulkan through **MoltenVK** (Apache-2.0): accurate LLE RDP; needs an LLE RSP for
  graphics tasks (paraLLEl-RSP uses a JIT, so cxd4's RSP interpreter, CC0/public domain, would be the no-JIT pick).
- **angrylion-rdp-plus** software RDP: licence must be checked first (historically MAME-style non-commercial for
  the original angrylion code; the "plus" fork claims MIT) and it is CPU-heavy.
- Ask GLideN64's authors for a GPLv3-compatible licence ("or later") grant.

## Layout

SwiftPM can't reach outside the package, so the vendored files live inside it, byte-identical to upstream
(same relative paths): `Packages/CoreKit/Sources/MUPEN64/mupen64plus-core/` and `.../rsp-hle/`. The ROM database
`mupen64plus.ini` is a byte-identical copy in `Sources/N64Core/Resources/` (SwiftPM resources must sit in the
target that uses them; it lists names, CRCs, MD5s, save types and per-game settings, no ROM data).

Our own files (GPLv3, part of Foldback), in `Sources/MUPEN64/glue`:

- `include/Mupen64Glue.h`, `src/n64_glue.c`: the C API Swift sees. Runs the core's own loop (`M64CMD_EXECUTE`) on
  a private thread and parks it at every vertical interrupt (inside the video plugin's `UpdateScreen`), so the
  host steps one field at a time; save states are taken and restored synchronously at that same point (the core's
  own `savestates_save/load`, through a temp file; level-1 gzip). The four plugins are linked statically:
  `osal_dynlib_getproc` (the only way the core and rsp-hle find plugin and core functions) resolves names against
  tables of function pointers; `osal_dynlib_open` always fails (rsp-hle's optional fallback plugin is never
  loaded). Our video (VI scan-out), audio (AI samples, linear resample to 48 kHz mono) and input plugins are here.
  Battery saves: the core writes EEPROM/SRAM/FlashRAM/Controller Pak files into a private work dir; the glue packs
  whichever exist into one "N64B" blob (and writes them back before boot).
- `src/n64_platform.c`: stand-ins for upstream files we don't compile: osal (`files_*.c`: every path is the work
  dir or the ROM-database dir), the video extension (`api/vidext.c`: SDL windows/GL/Vulkan; never used),
  `main/eventloop.c` + `sdl_key_converter.c` (SDL hotkeys) and `main/screenshot.c` (libpng).
- `shim/SDL.h` (+ `SDL_thread.h`, `SDL_timer.h`): a pthread-backed stand-in for the handful of SDL calls the
  compiled files make (recursive mutexes, a millisecond clock, sleep, no-op init/quit/pump). Not SDL.
- `units/core_main.c`: compiles `src/main/main.c` (SwiftPM would otherwise treat a `main.c` as an executable).
- `units/rsphle_plugin.c`: compiles rsp-hle's `plugin.c` with its six entry points renamed `rsphle_*` (the core
  also exports `PluginGetVersion`, and every plugin has a `RomClosed`).

Compile settings (`mupenC` in `Package.swift`): `-O2 -fno-strict-aliasing`, upstream warnings silenced (`-w`),
`NO_ASM`, `NOCRYPT`/`NOUNCRYPT` (MiniZip), `NDEBUG`; zlib from the SDK. Never defined: `DYNAREC`, `NEW_DYNAREC`,
`M64P_PARALLEL` (so the work queue runs inline), `M64P_OSD`, `M64P_NETPLAY`, `DBG`, `WITH_LIRC`, `PROFILE`,
`COUNT_INSTR`, `VIDEXT_VULKAN`. The front end sets `R4300Emulator = 1` (cached interpreter: decodes MIPS
instructions into tables of C function pointers, generates no machine code), `RandomizeInterrupt = 0`
(deterministic states), `SaveFilenameFormat = 0`, `OnScreenDisplay = 0`, and turns the speed limiter off.

## No JIT, no Nintendo files

- No recompiler source is in the repository: `device/r4300/new_dynarec/` holds only `new_dynarec.h` and
  `device/r4300/x86/`, `x86_64/` only `assemble_struct.h` (struct declarations that `recomp_types.h` includes
  unconditionally); `recomp.c`, `dynarec.c`, `assemble.c`, `regcache.c`, the `.asm`/`.S` linkage files and
  `new_dynarec.c` are not vendored. No executable memory is ever mapped.
- Boot: mupen64plus's HLE PIF boot (`device/pif/bootrom_hle.c`) sets up the machine and runs the cartridge's own
  code at 0x40-0xFFF (normally its IPL3). Nothing is ever loaded from outside the ROM; there is no PIF ROM, no
  64DD IPL (64DD disks are not supported: no disk is ever configured).
- Our test cartridge (`Tools/build_n64_roms.py`) is our own MIPS code with our own 15-instruction boot stub in the
  IPL3 area.

## Patches

**None.** Every file under `Sources/MUPEN64/mupen64plus-core` and `Sources/MUPEN64/rsp-hle` is byte-identical to
upstream (`daae68e`, `4cdc305`); `ThirdParty/mupen64/patches/` does not exist. If a file ever has to change, save
a unified diff there as `NNN-name.patch` with the reason, and list it here.

## Licence audit

200 vendored files (plus `mupen64plus.ini`, GPL-2.0-or-later data of mupen64plus-core):

- 182 file(s): GPL-2.0-or-later
- 8 file(s): zlib (minizip)
- 2 file(s): licence statement (GPL)
- 2 file(s): zlib-style (L. Peter Deutsch)
- 2 file(s): BSD-2-Clause (X-Scale)
- 1 file(s): GPL-2.0 text
- 1 file(s): zlib (MiniZip, Mark Adler)
- 1 file(s): BSD-2-Clause (xxHash)
- 1 file(s): no header; covered by mupen64plus GPL-2.0-or-later

All GPLv3-compatible (GPL-2.0-or-later taken as GPL-3.0, zlib, BSD-2-Clause). No non-commercial or
no-derivatives code. App acknowledgements: `Licenses/mupen64plus-GPL-2.0-or-later.txt` and
`Licenses/mupen64plus-bundled.txt` (MiniZip, MD5, xxHash, CIC-NUS-6105). The CIC-NUS-6105 file is X-Scale's
reimplementation of that chip's challenge response from analysis (BSD-2-Clause); flag it for the Fable review as
the one firmware-adjacent file.

## Files

| File (under `Packages/CoreKit/Sources/MUPEN64/`) | Bytes | Licence |
|---|---:|---|
| `mupen64plus-core/LICENSES` | 2162 | licence statement (GPL) |
| `mupen64plus-core/doc/gpl-license` | 18639 | GPL-2.0 text |
| `mupen64plus-core/src/api/callbacks.c` | 2770 | GPL-2.0-or-later |
| `mupen64plus-core/src/api/callbacks.h` | 2346 | GPL-2.0-or-later |
| `mupen64plus-core/src/api/common.c` | 4687 | GPL-2.0-or-later |
| `mupen64plus-core/src/api/config.c` | 52363 | GPL-2.0-or-later |
| `mupen64plus-core/src/api/config.h` | 1834 | GPL-2.0-or-later |
| `mupen64plus-core/src/api/debugger.c` | 14298 | GPL-2.0-or-later |
| `mupen64plus-core/src/api/debugger.h` | 2211 | GPL-2.0-or-later |
| `mupen64plus-core/src/api/frontend.c` | 17474 | GPL-2.0-or-later |
| `mupen64plus-core/src/api/m64p_common.h` | 3664 | GPL-2.0-or-later |
| `mupen64plus-core/src/api/m64p_config.h` | 12641 | GPL-2.0-or-later |
| `mupen64plus-core/src/api/m64p_debugger.h` | 8718 | GPL-2.0-or-later |
| `mupen64plus-core/src/api/m64p_frontend.h` | 5627 | GPL-2.0-or-later |
| `mupen64plus-core/src/api/m64p_plugin.h` | 11394 | GPL-2.0-or-later |
| `mupen64plus-core/src/api/m64p_types.h` | 15108 | GPL-2.0-or-later |
| `mupen64plus-core/src/api/m64p_vidext.h` | 8277 | GPL-2.0-or-later |
| `mupen64plus-core/src/api/vidext.h` | 2061 | GPL-2.0-or-later |
| `mupen64plus-core/src/backends/api/audio_out_backend.h` | 1965 | GPL-2.0-or-later |
| `mupen64plus-core/src/backends/api/clock_backend.h` | 1767 | GPL-2.0-or-later |
| `mupen64plus-core/src/backends/api/controller_input_backend.h` | 2696 | GPL-2.0-or-later |
| `mupen64plus-core/src/backends/api/joybus.h` | 3458 | GPL-2.0-or-later |
| `mupen64plus-core/src/backends/api/rumble_backend.h` | 1851 | GPL-2.0-or-later |
| `mupen64plus-core/src/backends/api/storage_backend.h` | 2032 | GPL-2.0-or-later |
| `mupen64plus-core/src/backends/api/video_capture_backend.c` | 2614 | GPL-2.0-or-later |
| `mupen64plus-core/src/backends/api/video_capture_backend.h` | 3216 | GPL-2.0-or-later |
| `mupen64plus-core/src/backends/clock_ctime_plus_delta.c` | 1866 | GPL-2.0-or-later |
| `mupen64plus-core/src/backends/clock_ctime_plus_delta.h` | 1757 | GPL-2.0-or-later |
| `mupen64plus-core/src/backends/dummy_video_capture.c` | 2893 | GPL-2.0-or-later |
| `mupen64plus-core/src/backends/file_storage.c` | 5272 | GPL-2.0-or-later |
| `mupen64plus-core/src/backends/file_storage.h` | 2307 | GPL-2.0-or-later |
| `mupen64plus-core/src/backends/plugins_compat/audio_plugin_compat.c` | 3016 | GPL-2.0-or-later |
| `mupen64plus-core/src/backends/plugins_compat/input_plugin_compat.c` | 7691 | GPL-2.0-or-later |
| `mupen64plus-core/src/backends/plugins_compat/plugins_compat.h` | 2747 | GPL-2.0-or-later |
| `mupen64plus-core/src/debugger/dbg_breakpoints.h` | 2500 | GPL-2.0-or-later |
| `mupen64plus-core/src/debugger/dbg_debugger.h` | 2066 | GPL-2.0-or-later |
| `mupen64plus-core/src/debugger/dbg_decoder.h` | 2225 | GPL-2.0-or-later |
| `mupen64plus-core/src/debugger/dbg_memory.h` | 3120 | GPL-2.0-or-later |
| `mupen64plus-core/src/device/cart/af_rtc.c` | 4172 | GPL-2.0-or-later |
| `mupen64plus-core/src/device/cart/af_rtc.h` | 2249 | GPL-2.0-or-later |
| `mupen64plus-core/src/device/cart/cart.c` | 7607 | GPL-2.0-or-later |
| `mupen64plus-core/src/device/cart/cart.h` | 3622 | GPL-2.0-or-later |
| `mupen64plus-core/src/device/cart/cart_rom.c` | 4712 | GPL-2.0-or-later |
| `mupen64plus-core/src/device/cart/cart_rom.h` | 2611 | GPL-2.0-or-later |
| `mupen64plus-core/src/device/cart/eeprom.c` | 3043 | GPL-2.0-or-later |
| `mupen64plus-core/src/device/cart/eeprom.h` | 2176 | GPL-2.0-or-later |
| `mupen64plus-core/src/device/cart/flashram.c` | 8961 | GPL-2.0-or-later |
| `mupen64plus-core/src/device/cart/flashram.h` | 3224 | GPL-2.0-or-later |
| `mupen64plus-core/src/device/cart/is_viewer.c` | 3956 | GPL-2.0-or-later |
| `mupen64plus-core/src/device/cart/is_viewer.h` | 2021 | GPL-2.0-or-later |
| `mupen64plus-core/src/device/cart/sram.c` | 3615 | GPL-2.0-or-later |
| `mupen64plus-core/src/device/cart/sram.h` | 2364 | GPL-2.0-or-later |
| `mupen64plus-core/src/device/controllers/game_controller.c` | 6962 | GPL-2.0-or-later |
| `mupen64plus-core/src/device/controllers/game_controller.h` | 3162 | GPL-2.0-or-later |
| `mupen64plus-core/src/device/controllers/paks/biopak.c` | 2742 | GPL-2.0-or-later |
| `mupen64plus-core/src/device/controllers/paks/biopak.h` | 1840 | GPL-2.0-or-later |
| `mupen64plus-core/src/device/controllers/paks/mempak.c` | 6238 | GPL-2.0-or-later |
| `mupen64plus-core/src/device/controllers/paks/mempak.h` | 2270 | GPL-2.0-or-later |
| `mupen64plus-core/src/device/controllers/paks/rumblepak.c` | 3078 | GPL-2.0-or-later |
| `mupen64plus-core/src/device/controllers/paks/rumblepak.h` | 2075 | GPL-2.0-or-later |
| `mupen64plus-core/src/device/controllers/paks/transferpak.c` | 6765 | GPL-2.0-or-later |
| `mupen64plus-core/src/device/controllers/paks/transferpak.h` | 2095 | GPL-2.0-or-later |
| `mupen64plus-core/src/device/controllers/vru_controller.c` | 9093 | GPL-2.0-or-later |
| `mupen64plus-core/src/device/controllers/vru_controller.h` | 1908 | GPL-2.0-or-later |
| `mupen64plus-core/src/device/dd/dd_controller.c` | 34844 | GPL-2.0-or-later |
| `mupen64plus-core/src/device/dd/dd_controller.h` | 4524 | GPL-2.0-or-later |
| `mupen64plus-core/src/device/dd/disk.c` | 21360 | GPL-2.0-or-later |
| `mupen64plus-core/src/device/dd/disk.h` | 7890 | GPL-2.0-or-later |
| `mupen64plus-core/src/device/device.c` | 11440 | GPL-2.0-or-later |
| `mupen64plus-core/src/device/device.h` | 6557 | GPL-2.0-or-later |
| `mupen64plus-core/src/device/gb/gb_cart.c` | 37863 | GPL-2.0-or-later |
| `mupen64plus-core/src/device/gb/gb_cart.h` | 3588 | GPL-2.0-or-later |
| `mupen64plus-core/src/device/gb/m64282fp.c` | 6923 | GPL-2.0-or-later |
| `mupen64plus-core/src/device/gb/m64282fp.h` | 2038 | GPL-2.0-or-later |
| `mupen64plus-core/src/device/gb/mbc3_rtc.c` | 4134 | GPL-2.0-or-later |
| `mupen64plus-core/src/device/gb/mbc3_rtc.h` | 2800 | GPL-2.0-or-later |
| `mupen64plus-core/src/device/memory/memory.c` | 10788 | GPL-2.0-or-later |
| `mupen64plus-core/src/device/memory/memory.h` | 4004 | GPL-2.0-or-later |
| `mupen64plus-core/src/device/pif/bootrom_hle.c` | 6680 | GPL-2.0-or-later |
| `mupen64plus-core/src/device/pif/bootrom_hle.h` | 1814 | GPL-2.0-or-later |
| `mupen64plus-core/src/device/pif/cic.c` | 3389 | GPL-2.0-or-later |
| `mupen64plus-core/src/device/pif/cic.h` | 1924 | GPL-2.0-or-later |
| `mupen64plus-core/src/device/pif/n64_cic_nus_6105.c` | 6147 | BSD-2-Clause (X-Scale) |
| `mupen64plus-core/src/device/pif/n64_cic_nus_6105.h` | 5397 | BSD-2-Clause (X-Scale) |
| `mupen64plus-core/src/device/pif/pif.c` | 11732 | GPL-2.0-or-later |
| `mupen64plus-core/src/device/pif/pif.h` | 3104 | GPL-2.0-or-later |
| `mupen64plus-core/src/device/r4300/cached_interp.c` | 32701 | GPL-2.0-or-later |
| `mupen64plus-core/src/device/r4300/cached_interp.h` | 11123 | GPL-2.0-or-later |
| `mupen64plus-core/src/device/r4300/cp0.c` | 9479 | GPL-2.0-or-later |
| `mupen64plus-core/src/device/r4300/cp0.h` | 8247 | GPL-2.0-or-later |
| `mupen64plus-core/src/device/r4300/cp1.c` | 4927 | GPL-2.0-or-later |
| `mupen64plus-core/src/device/r4300/cp1.h` | 4225 | GPL-2.0-or-later |
| `mupen64plus-core/src/device/r4300/cp2.c` | 2165 | GPL-2.0-or-later |
| `mupen64plus-core/src/device/r4300/cp2.h` | 2069 | GPL-2.0-or-later |
| `mupen64plus-core/src/device/r4300/fpu.h` | 30086 | GPL-2.0-or-later |
| `mupen64plus-core/src/device/r4300/idec.c` | 28686 | GPL-2.0-or-later |
| `mupen64plus-core/src/device/r4300/idec.h` | 3267 | GPL-2.0-or-later |
| `mupen64plus-core/src/device/r4300/interrupt.c` | 19996 | GPL-2.0-or-later |
| `mupen64plus-core/src/device/r4300/interrupt.h` | 3227 | GPL-2.0-or-later |
| `mupen64plus-core/src/device/r4300/mips_instructions.def` | 63156 | GPL-2.0-or-later |
| `mupen64plus-core/src/device/r4300/new_dynarec/new_dynarec.h` | 3648 | GPL-2.0-or-later |
| `mupen64plus-core/src/device/r4300/opcodes.md` | 3015 | no header; covered by mupen64plus GPL-2.0-or-later |
| `mupen64plus-core/src/device/r4300/pure_interp.c` | 27711 | GPL-2.0-or-later |
| `mupen64plus-core/src/device/r4300/pure_interp.h` | 1742 | GPL-2.0-or-later |
| `mupen64plus-core/src/device/r4300/r4300_core.c` | 13770 | GPL-2.0-or-later |
| `mupen64plus-core/src/device/r4300/r4300_core.h` | 8762 | GPL-2.0-or-later |
| `mupen64plus-core/src/device/r4300/recomp.h` | 2836 | GPL-2.0-or-later |
| `mupen64plus-core/src/device/r4300/recomp_types.h` | 3141 | GPL-2.0-or-later |
| `mupen64plus-core/src/device/r4300/tlb.c` | 5311 | GPL-2.0-or-later |
| `mupen64plus-core/src/device/r4300/tlb.h` | 2472 | GPL-2.0-or-later |
| `mupen64plus-core/src/device/r4300/x86/assemble_struct.h` | 2125 | GPL-2.0-or-later |
| `mupen64plus-core/src/device/r4300/x86_64/assemble_struct.h` | 2601 | GPL-2.0-or-later |
| `mupen64plus-core/src/device/rcp/ai/ai_controller.c` | 7749 | GPL-2.0-or-later |
| `mupen64plus-core/src/device/rcp/ai/ai_controller.h` | 3076 | GPL-2.0-or-later |
| `mupen64plus-core/src/device/rcp/mi/mi_controller.c` | 5100 | GPL-2.0-or-later |
| `mupen64plus-core/src/device/rcp/mi/mi_controller.h` | 2641 | GPL-2.0-or-later |
| `mupen64plus-core/src/device/rcp/pi/pi_controller.c` | 7909 | GPL-2.0-or-later |
| `mupen64plus-core/src/device/rcp/pi/pi_controller.h` | 3734 | GPL-2.0-or-later |
| `mupen64plus-core/src/device/rcp/rdp/fb.c` | 7394 | GPL-2.0-or-later |
| `mupen64plus-core/src/device/rcp/rdp/fb.h` | 2549 | GPL-2.0-or-later |
| `mupen64plus-core/src/device/rcp/rdp/rdp_core.c` | 4965 | GPL-2.0-or-later |
| `mupen64plus-core/src/device/rcp/rdp/rdp_core.h` | 3897 | GPL-2.0-or-later |
| `mupen64plus-core/src/device/rcp/ri/ri_controller.c` | 2251 | GPL-2.0-or-later |
| `mupen64plus-core/src/device/rcp/ri/ri_controller.h` | 3193 | GPL-2.0-or-later |
| `mupen64plus-core/src/device/rcp/rsp/rsp_core.c` | 13831 | GPL-2.0-or-later |
| `mupen64plus-core/src/device/rcp/rsp/rsp_core.h` | 4279 | GPL-2.0-or-later |
| `mupen64plus-core/src/device/rcp/si/si_controller.c` | 5750 | GPL-2.0-or-later |
| `mupen64plus-core/src/device/rcp/si/si_controller.h` | 2934 | GPL-2.0-or-later |
| `mupen64plus-core/src/device/rcp/vi/vi_controller.c` | 6109 | GPL-2.0-or-later |
| `mupen64plus-core/src/device/rcp/vi/vi_controller.h` | 3038 | GPL-2.0-or-later |
| `mupen64plus-core/src/device/rdram/rdram.c` | 8793 | GPL-2.0-or-later |
| `mupen64plus-core/src/device/rdram/rdram.h` | 3003 | GPL-2.0-or-later |
| `mupen64plus-core/src/main/cheat.c` | 17009 | GPL-2.0-or-later |
| `mupen64plus-core/src/main/cheat.h` | 2301 | GPL-2.0-or-later |
| `mupen64plus-core/src/main/eventloop.h` | 1897 | GPL-2.0-or-later |
| `mupen64plus-core/src/main/list.h` | 4036 | GPL-2.0-or-later |
| `mupen64plus-core/src/main/main.c` | 70034 | GPL-2.0-or-later |
| `mupen64plus-core/src/main/main.h` | 3827 | GPL-2.0-or-later |
| `mupen64plus-core/src/main/netplay.h` | 4312 | GPL-2.0-or-later |
| `mupen64plus-core/src/main/profile.h` | 2053 | GPL-2.0-or-later |
| `mupen64plus-core/src/main/rom.c` | 35541 | GPL-2.0-or-later |
| `mupen64plus-core/src/main/rom.h` | 5871 | GPL-2.0-or-later |
| `mupen64plus-core/src/main/savestates.c` | 95307 | GPL-2.0-or-later |
| `mupen64plus-core/src/main/savestates.h` | 2540 | GPL-2.0-or-later |
| `mupen64plus-core/src/main/screenshot.h` | 1682 | GPL-2.0-or-later |
| `mupen64plus-core/src/main/util.c` | 156775 | GPL-2.0-or-later |
| `mupen64plus-core/src/main/util.h` | 9931 | GPL-2.0-or-later |
| `mupen64plus-core/src/main/version.h` | 2018 | GPL-2.0-or-later |
| `mupen64plus-core/src/main/workqueue.h` | 2287 | GPL-2.0-or-later |
| `mupen64plus-core/src/osal/dynamiclib.h` | 1766 | GPL-2.0-or-later |
| `mupen64plus-core/src/osal/files.h` | 2951 | GPL-2.0-or-later |
| `mupen64plus-core/src/osal/preproc.h` | 3576 | GPL-2.0-or-later |
| `mupen64plus-core/src/osd/osd.h` | 4848 | GPL-2.0-or-later |
| `mupen64plus-core/src/plugin/dummy_audio.c` | 2939 | GPL-2.0-or-later |
| `mupen64plus-core/src/plugin/dummy_audio.h` | 2491 | GPL-2.0-or-later |
| `mupen64plus-core/src/plugin/dummy_input.c` | 3275 | GPL-2.0-or-later |
| `mupen64plus-core/src/plugin/dummy_input.h` | 2974 | GPL-2.0-or-later |
| `mupen64plus-core/src/plugin/dummy_rsp.c` | 2385 | GPL-2.0-or-later |
| `mupen64plus-core/src/plugin/dummy_rsp.h` | 2058 | GPL-2.0-or-later |
| `mupen64plus-core/src/plugin/dummy_video.c` | 3157 | GPL-2.0-or-later |
| `mupen64plus-core/src/plugin/dummy_video.h` | 2770 | GPL-2.0-or-later |
| `mupen64plus-core/src/plugin/plugin.c` | 23707 | GPL-2.0-or-later |
| `mupen64plus-core/src/plugin/plugin.h` | 4669 | GPL-2.0-or-later |
| `mupen64plus-core/subprojects/md5/md5.c` | 13342 | zlib-style (L. Peter Deutsch) |
| `mupen64plus-core/subprojects/md5/md5.h` | 3359 | zlib-style (L. Peter Deutsch) |
| `mupen64plus-core/subprojects/minizip/crypt.h` | 4801 | zlib (minizip) |
| `mupen64plus-core/subprojects/minizip/ints.h` | 1602 | zlib (minizip) |
| `mupen64plus-core/subprojects/minizip/ioapi.c` | 7743 | zlib (minizip) |
| `mupen64plus-core/subprojects/minizip/ioapi.h` | 6662 | zlib (minizip) |
| `mupen64plus-core/subprojects/minizip/skipset.h` | 13774 | zlib (MiniZip, Mark Adler) |
| `mupen64plus-core/subprojects/minizip/unzip.c` | 67672 | zlib (minizip) |
| `mupen64plus-core/subprojects/minizip/unzip.h` | 16708 | zlib (minizip) |
| `mupen64plus-core/subprojects/minizip/zip.c` | 74926 | zlib (minizip) |
| `mupen64plus-core/subprojects/minizip/zip.h` | 15695 | zlib (minizip) |
| `mupen64plus-core/subprojects/xxhash/xxhash.h` | 268319 | BSD-2-Clause (xxHash) |
| `rsp-hle/LICENSES` | 19353 | licence statement (GPL) |
| `rsp-hle/src/alist.c` | 31976 | GPL-2.0-or-later |
| `rsp-hle/src/alist.h` | 6151 | GPL-2.0-or-later |
| `rsp-hle/src/alist_audio.c` | 9545 | GPL-2.0-or-later |
| `rsp-hle/src/alist_naudio.c` | 11359 | GPL-2.0-or-later |
| `rsp-hle/src/alist_nead.c` | 17817 | GPL-2.0-or-later |
| `rsp-hle/src/arithmetics.h` | 1895 | GPL-2.0-or-later |
| `rsp-hle/src/audio.c` | 7015 | GPL-2.0-or-later |
| `rsp-hle/src/audio.h` | 2119 | GPL-2.0-or-later |
| `rsp-hle/src/cicx105.c` | 2514 | GPL-2.0-or-later |
| `rsp-hle/src/common.h` | 1840 | GPL-2.0-or-later |
| `rsp-hle/src/hle.c` | 18389 | GPL-2.0-or-later |
| `rsp-hle/src/hle.h` | 2317 | GPL-2.0-or-later |
| `rsp-hle/src/hle_external.h` | 2412 | GPL-2.0-or-later |
| `rsp-hle/src/hle_internal.h` | 3126 | GPL-2.0-or-later |
| `rsp-hle/src/hvqm.c` | 11132 | GPL-2.0-or-later |
| `rsp-hle/src/jpeg.c` | 20563 | GPL-2.0-or-later |
| `rsp-hle/src/memory.c` | 2824 | GPL-2.0-or-later |
| `rsp-hle/src/memory.h` | 6272 | GPL-2.0-or-later |
| `rsp-hle/src/mp3.c` | 30865 | GPL-2.0-or-later |
| `rsp-hle/src/musyx.c` | 34297 | GPL-2.0-or-later |
| `rsp-hle/src/osal_dynamiclib.h` | 1910 | GPL-2.0-or-later |
| `rsp-hle/src/plugin.c` | 17466 | GPL-2.0-or-later |
| `rsp-hle/src/re2.c` | 8431 | GPL-2.0-or-later |
| `rsp-hle/src/ucodes.h` | 5086 | GPL-2.0-or-later |

## Update, 13 Nov 2026: paraLLEl-RDP + cxd4 are in (build 4)

The renderer is now **paraLLEl-RDP** (MIT, `Sources/MUPEN64/parallel-rdp`, parallel-rdp-standalone `388d70f`) on
**MoltenVK** v1.4.2 (Apache-2.0, `ThirdParty/moltenvk`, device builds only), with **cxd4's RSP interpreter**
(CC0, `Sources/MUPEN64/rsp-cxd4`, `b8e747b`) for graphics tasks; rsp-hle keeps audio. All vendored unmodified,
compiled only through our units in `glue/rdp` (cxd4: signal handlers and `srand` neutralised by macros in
`cxd4_unit.c`; paraLLEl: `volk_rename.h` first). Without Vulkan (simulator, Mac tests) the glue still falls back
to the VI scan-out above. Measurements: `docs/n64-rdp-spike.md`. In Release only the hidden speed test reaches it
(About › long-press the version line); N64 games stay Debug-only (`N64_ENABLED`).

**Build 5:** N64 games play in Release through this renderer (asynchronous RDP, 640 x 480 VI output, persistent
pipeline cache in Application Support); `N64_ENABLED` is gone. Details: `docs/n64-rdp-spike.md` §10.
