# melonDS (vendored, Nintendo DS mode only, interpreter)

- Upstream: https://github.com/melonDS-emu/melonDS
- Snapshot: commit `497aa6c` ("Use 64-bit type in SqrtDone() to fix an overflow (#2795)"), cloned into
  the gitignored `ThirdParty-src/melonDS`; never built with its own scripts.
- Licence: GPL-3.0-or-later (`LICENSE` here). Foldback is GPLv3, so the whole app is distributed under
  GPLv3 and its complete source (including this snapshot) must be offered with any public build.

## Layout (decision)

As with mGBA and ares, SwiftPM can't reach outside the package, so the vendored files live **inside
the package**, byte-identical to upstream `src/`, at `Packages/CoreKit/Sources/MELONDS/melonds/` (same
relative paths). This folder holds the licence, this README and the FreeBIOS source form.

Our own files in the `MELONDS` target (GPL-3.0 as part of Foldback):

- `glue/include/MelonDSGlue.h`, `glue/src/melonds_glue.cpp`: the C API Swift sees, plus every
  `melonDS::Platform` hook. No file access at all (every open returns "not found", so no BIOS,
  firmware, NAND or SD image can ever be read), no network or local multiplayer (packets are dropped),
  no microphone or camera. Threads, semaphores and mutexes use the C++ standard library.
- `glue/src/melonds_stubs.cpp`: stand-ins for the DSi-mode and SD-card members the NDS code names but
  only reaches with a DSi (`ConsoleType == 1`) or a homebrew SD image; this build creates neither.
  Each stand-in aborts if it is ever reached.
- `glue/units/ARM.cpp`, `NDS.cpp`, `NDSCart.cpp`: build units that compile those three upstream files
  with `dynamic_cast` defined as `static_cast` (all headers included first, so only the file body is
  affected). The casts downcast to `DSi` on DSi-only paths; `dynamic_cast` would need DSi's type info,
  which lives in the unvendored `DSi.cpp`. The three originals are excluded from direct compilation.
- `glue/shim/ARMJIT.h`, `glue/shim/ARMJIT_Memory.h`: upstream's headers run through
  `unifdef -UJIT_ENABLED`, i.e. only the non-JIT stand-ins (the stub `ARMJIT` class and the plain RAM
  arrays). `NDS.h` needs them; no JIT code is in the repository.
- `glue/shim/version.h`: replaces the CMake-generated `version.h` (template `src/version.h.in`).

Compile settings (`melondsCXX` in `Package.swift`): `-O2 -fwrapv` (melonDS relies on wrapping signed
arithmetic, as upstream's CMake sets), `NDEBUG`, upstream warnings silenced (`-w`), C++20. Never defined,
so compiled out: `JIT_ENABLED`, `GDBSTUB_ENABLED`, `OGLRENDERER_ENABLED`, `MELONDS_EMBED_BUILD_INFO`.

## What is left out

Not vendored at all: the Qt/SDL frontend and `frontend/` (including `frontend/duckstation`), every
`ARMJIT*` file, `ARM_InstrInfo.*`, `JitBlock.h`, `dolphin/` (code emitters), `debug/` (GDB stub), all
OpenGL renderers and shaders (`GPU*_OpenGL*`, `GPU3D_Compute*`, `OpenGLSupport*`, `OpenGL_shaders/`),
DSi mode sources (`DSi*.cpp`, `DSP_HLE/`, `teakra/`, `DSi_NAND`, camera, AES, SD/MMC, NWifi; the `DSi*.h`
headers are kept because the NDS code declares DSi members), `net/` (LAN, pcap, slirp), `FATStorage.cpp`,
`FATIO.cpp` and FatFs's sources (`fatfs/*.c`; two headers kept), `tiny-AES-c/aes.c` (headers kept),
`sha1/`. (The core's microphone emulation is kept; the glue feeds it silence.)

Kept although it sounds like networking: `Wifi.cpp` / `WifiAP.cpp`, the DS's Wi-Fi *chip* registers
and melonDS's in-process fake access point. The NDS object contains the chip by value and games probe
it at boot; with the Platform hooks above nothing ever leaves the device.

## Booting without Nintendo files

`NDSArgs` defaults are used: FreeBIOS (`FreeBIOS.cpp`) for both the ARM9 and ARM7 BIOS, and
`Firmware(0)`, a firmware image generated in memory (default user settings; melonDS's own nickname).
The glue then direct-boots the cartridge (`NDS::SetupDirectBoot`), which FreeBIOS requires.

FreeBIOS: "Custom NDS ARM7/ARM9 BIOS replacement, Copyright (c) 2013, Gilead Kutnick", BSD-2-Clause.
Its readme says it "is not derived from Nintendo's BIOS implementation but has been implemented using
publically available documentation". It is the BIOS written for the DraStic emulator. `FreeBIOS_Data.h`
is the assembled image; its assembly source and Makefiles are kept here in `freebios/` (from upstream's
top-level `freebios/` folder) as the source form. Upstream's `SetupDirectBoot` copies the cartridge
header's logo bytes into the FreeBIOS image in RAM; our own test cartridge's logo area is zero.

## Patches

**None.** Every file under `Sources/MELONDS/melonds` is byte-identical to upstream `497aa6c`
(`src/`, plus the root `LICENSE`). Everything Foldback needed was done with shims, stubs and build
units (above). If a file ever has to change, save a unified diff as `patches/NNN-name.patch` here with
the reason, and list it in this section.

## Licence audit

124 vendored files:

- 105 file(s): GPL-3.0-or-later (header)
- 3 file(s): FatFs licence (1-clause BSD style, ChaN)
- 3 file(s): The Unlicense (tiny-AES-c)
- 3 file(s): BSD-2-Clause (xxHash, Yann Collet)
- 2 file(s): BSD-2-Clause (FreeBIOS, Gilead Kutnick)
- 2 file(s): no header; covered by melonDS GPL-3.0
- 2 file(s): LGPL-2.1-or-later (blip_buf, Shay Green)
- 2 file(s): blip_buf documentation / licence text
- 1 file(s): BSD-2-Clause (FreeBIOS image; source in freebios/ here)
- 1 file(s): GPL-3.0 text (repository root LICENSE)

All are GPLv3-compatible (LGPL-2.1-or-later, BSD-2-Clause, FatFs's 1-clause licence and the Unlicense
can all be combined into a GPLv3 work). `GPU3D_Texcache.*` have no header and fall under melonDS's
GPL-3.0. No non-commercial or no-derivatives code. The app's acknowledgements carry melonDS (GPL-3.0),
FreeBIOS (BSD-2-Clause) and the bundled notices (`Licenses/melonDS-bundled.txt`).

## Files

| File (under `Packages/CoreKit/Sources/MELONDS/melonds/`) | Bytes | Licence |
|---|---:|---|
| `ARCodeFile.cpp` | 10982 | GPL-3.0-or-later (header) |
| `ARCodeFile.h` | 1824 | GPL-3.0-or-later (header) |
| `ARDatabaseDAT.cpp` | 9813 | GPL-3.0-or-later (header) |
| `ARDatabaseDAT.h` | 1747 | GPL-3.0-or-later (header) |
| `AREngine.cpp` | 12107 | GPL-3.0-or-later (header) |
| `AREngine.h` | 1061 | GPL-3.0-or-later (header) |
| `ARM.cpp` | 32558 | GPL-3.0-or-later (header) |
| `ARM.h` | 10315 | GPL-3.0-or-later (header) |
| `ARMInterpreter.cpp` | 7632 | GPL-3.0-or-later (header) |
| `ARMInterpreter.h` | 1195 | GPL-3.0-or-later (header) |
| `ARMInterpreter_ALU.cpp` | 38792 | GPL-3.0-or-later (header) |
| `ARMInterpreter_ALU.h` | 3538 | GPL-3.0-or-later (header) |
| `ARMInterpreter_Branch.cpp` | 2879 | GPL-3.0-or-later (header) |
| `ARMInterpreter_Branch.h` | 1071 | GPL-3.0-or-later (header) |
| `ARMInterpreter_LoadStore.cpp` | 20873 | GPL-3.0-or-later (header) |
| `ARMInterpreter_LoadStore.h` | 2273 | GPL-3.0-or-later (header) |
| `ARM_InstrTable.h` | 66020 | GPL-3.0-or-later (header) |
| `Args.h` | 4471 | GPL-3.0-or-later (header) |
| `CP15.cpp` | 24107 | GPL-3.0-or-later (header) |
| `CRC32.cpp` | 1861 | GPL-3.0-or-later (header) |
| `CRC32.h` | 870 | GPL-3.0-or-later (header) |
| `DMA.cpp` | 18802 | GPL-3.0-or-later (header) |
| `DMA.h` | 2208 | GPL-3.0-or-later (header) |
| `DMA_Timings.cpp` | 7903 | GPL-3.0-or-later (header) |
| `DMA_Timings.h` | 2187 | GPL-3.0-or-later (header) |
| `DSi.h` | 5915 | GPL-3.0-or-later (header) |
| `DSi_AES.h` | 2861 | GPL-3.0-or-later (header) |
| `DSi_Camera.h` | 3415 | GPL-3.0-or-later (header) |
| `DSi_DSP.h` | 4930 | GPL-3.0-or-later (header) |
| `DSi_I2C.h` | 5171 | GPL-3.0-or-later (header) |
| `DSi_I2S.h` | 1386 | GPL-3.0-or-later (header) |
| `DSi_NAND.h` | 8592 | GPL-3.0-or-later (header) |
| `DSi_NDMA.h` | 2219 | GPL-3.0-or-later (header) |
| `DSi_NWifi.h` | 3527 | GPL-3.0-or-later (header) |
| `DSi_SD.h` | 6487 | GPL-3.0-or-later (header) |
| `DSi_SPI_TSC.h` | 1286 | GPL-3.0-or-later (header) |
| `DSi_TMD.h` | 3490 | GPL-3.0-or-later (header) |
| `FATIO.h` | 1134 | GPL-3.0-or-later (header) |
| `FATStorage.h` | 4081 | GPL-3.0-or-later (header) |
| `FIFO.h` | 6443 | GPL-3.0-or-later (header) |
| `FreeBIOS.cpp` | 2315 | BSD-2-Clause (FreeBIOS, Gilead Kutnick) |
| `FreeBIOS.h` | 1774 | BSD-2-Clause (FreeBIOS, Gilead Kutnick) |
| `FreeBIOS_Data.h` | 125008 | BSD-2-Clause (FreeBIOS image; source in freebios/ here) |
| `GBACart.cpp` | 24761 | GPL-3.0-or-later (header) |
| `GBACart.h` | 13301 | GPL-3.0-or-later (header) |
| `GBACartMotionPak.cpp` | 4974 | GPL-3.0-or-later (header) |
| `GPU.cpp` | 47975 | GPL-3.0-or-later (header) |
| `GPU.h` | 26079 | GPL-3.0-or-later (header) |
| `GPU2D.cpp` | 21593 | GPL-3.0-or-later (header) |
| `GPU2D.h` | 3417 | GPL-3.0-or-later (header) |
| `GPU2D_Soft.cpp` | 42085 | GPL-3.0-or-later (header) |
| `GPU2D_Soft.h` | 3014 | GPL-3.0-or-later (header) |
| `GPU3D.cpp` | 89521 | GPL-3.0-or-later (header) |
| `GPU3D.h` | 8296 | GPL-3.0-or-later (header) |
| `GPU3D_Soft.cpp` | 59705 | GPL-3.0-or-later (header) |
| `GPU3D_Soft.h` | 15594 | GPL-3.0-or-later (header) |
| `GPU3D_Texcache.cpp` | 9275 | no header; covered by melonDS GPL-3.0 |
| `GPU3D_Texcache.h` | 11703 | no header; covered by melonDS GPL-3.0 |
| `GPU_ColorOp.h` | 2565 | GPL-3.0-or-later (header) |
| `GPU_Soft.cpp` | 11842 | GPL-3.0-or-later (header) |
| `GPU_Soft.h` | 1948 | GPL-3.0-or-later (header) |
| `LICENSE` | 35147 | GPL-3.0 text (repository root LICENSE) |
| `MemConstants.h` | 1524 | GPL-3.0-or-later (header) |
| `MemRegion.h` | 936 | GPL-3.0-or-later (header) |
| `Mic.cpp` | 5285 | GPL-3.0-or-later (header) |
| `Mic.h` | 1647 | GPL-3.0-or-later (header) |
| `NDS.cpp` | 119923 | GPL-3.0-or-later (header) |
| `NDS.h` | 16668 | GPL-3.0-or-later (header) |
| `NDSCart.cpp` | 31268 | GPL-3.0-or-later (header) |
| `NDSCart.h` | 8971 | GPL-3.0-or-later (header) |
| `NDSCart/CartCommon.cpp` | 7980 | GPL-3.0-or-later (header) |
| `NDSCart/CartCommon.h` | 3681 | GPL-3.0-or-later (header) |
| `NDSCart/CartHomebrew.cpp` | 4955 | GPL-3.0-or-later (header) |
| `NDSCart/CartHomebrew.h` | 1574 | GPL-3.0-or-later (header) |
| `NDSCart/CartR4.cpp` | 12682 | GPL-3.0-or-later (header) |
| `NDSCart/CartR4.h` | 2529 | GPL-3.0-or-later (header) |
| `NDSCart/CartRetail.cpp` | 11580 | GPL-3.0-or-later (header) |
| `NDSCart/CartRetail.h` | 2455 | GPL-3.0-or-later (header) |
| `NDSCart/CartRetailBT.cpp` | 1959 | GPL-3.0-or-later (header) |
| `NDSCart/CartRetailBT.h` | 1317 | GPL-3.0-or-later (header) |
| `NDSCart/CartRetailIR.cpp` | 2447 | GPL-3.0-or-later (header) |
| `NDSCart/CartRetailIR.h` | 1537 | GPL-3.0-or-later (header) |
| `NDSCart/CartRetailNAND.cpp` | 10025 | GPL-3.0-or-later (header) |
| `NDSCart/CartRetailNAND.h` | 2005 | GPL-3.0-or-later (header) |
| `NDSCart/CartSD.cpp` | 5804 | GPL-3.0-or-later (header) |
| `NDSCart/CartSD.h` | 2611 | GPL-3.0-or-later (header) |
| `NDSCart/melonDLDI.h` | 4273 | GPL-3.0-or-later (header) |
| `NDS_Header.h` | 6462 | GPL-3.0-or-later (header) |
| `NonStupidBitfield.h` | 7791 | GPL-3.0-or-later (header) |
| `Platform.h` | 14798 | GPL-3.0-or-later (header) |
| `ROMList.cpp` | 265206 | GPL-3.0-or-later (header) |
| `ROMList.h` | 1023 | GPL-3.0-or-later (header) |
| `RTC.cpp` | 22099 | GPL-3.0-or-later (header) |
| `RTC.h` | 2497 | GPL-3.0-or-later (header) |
| `SPI.cpp` | 13807 | GPL-3.0-or-later (header) |
| `SPI.h` | 4135 | GPL-3.0-or-later (header) |
| `SPI_Firmware.cpp` | 12877 | GPL-3.0-or-later (header) |
| `SPI_Firmware.h` | 17586 | GPL-3.0-or-later (header) |
| `SPU.cpp` | 38253 | GPL-3.0-or-later (header) |
| `SPU.h` | 6461 | GPL-3.0-or-later (header) |
| `Savestate.cpp` | 10844 | GPL-3.0-or-later (header) |
| `Savestate.h` | 3116 | GPL-3.0-or-later (header) |
| `TinyVector.h` | 3117 | GPL-3.0-or-later (header) |
| `Utils.cpp` | 1817 | GPL-3.0-or-later (header) |
| `Utils.h` | 1989 | GPL-3.0-or-later (header) |
| `Wifi.cpp` | 66940 | GPL-3.0-or-later (header) |
| `Wifi.h` | 6794 | GPL-3.0-or-later (header) |
| `WifiAP.cpp` | 11538 | GPL-3.0-or-later (header) |
| `WifiAP.h` | 1544 | GPL-3.0-or-later (header) |
| `blip-buf/blip_buf.c` | 10212 | LGPL-2.1-or-later (blip_buf, Shay Green) |
| `blip-buf/blip_buf.h` | 2651 | LGPL-2.1-or-later (blip_buf, Shay Green) |
| `blip-buf/license.txt` | 26940 | blip_buf documentation / licence text |
| `blip-buf/readme.txt` | 2569 | blip_buf documentation / licence text |
| `fatfs/LICENSE.txt` | 1913 | FatFs licence (1-clause BSD style, ChaN) |
| `fatfs/ff.h` | 15876 | FatFs licence (1-clause BSD style, ChaN) |
| `fatfs/ffconf.h` | 12085 | FatFs licence (1-clause BSD style, ChaN) |
| `tiny-AES-c/aes.h` | 2772 | The Unlicense (tiny-AES-c) |
| `tiny-AES-c/aes.hpp` | 184 | The Unlicense (tiny-AES-c) |
| `tiny-AES-c/unlicense.txt` | 1211 | The Unlicense (tiny-AES-c) |
| `types.h` | 1226 | GPL-3.0-or-later (header) |
| `version.h.in` | 1225 | GPL-3.0-or-later (header) |
| `xxhash/xxh3.h` | 2394 | BSD-2-Clause (xxHash, Yann Collet) |
| `xxhash/xxhash.c` | 1855 | BSD-2-Clause (xxHash, Yann Collet) |
| `xxhash/xxhash.h` | 268319 | BSD-2-Clause (xxHash, Yann Collet) |
