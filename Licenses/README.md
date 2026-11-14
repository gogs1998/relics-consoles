# Third-party licences

Relics: Games' NES and Game Boy / Game Boy Color cores, the app, its art and its test ROMs are our own.
These third-party components are compiled into the app:

| Component | Used for | Licence | Source | Modified? |
|---|---|---|---|---|
| DuoKit (from 0.1.2) | fold, hinge and pose handling for iPhone Duo | IQ Labs' own code; **must get a GPLv3-compatible licence (MIT or GPLv3) and a public repo before submission** (Corresponding Source) | https://github.com/gogs1998/iqlabs-duokit (private today) | n/a (ours) |
| mGBA (commit 662dada) | Game Boy Advance core, incl. its built-in (HLE) BIOS | MPL-2.0 (`mGBA-MPL-2.0.txt`) | https://github.com/mgba-emu/mgba | No (unmodified files in `Packages/CoreKit/Sources/MGBA/mgba`; any future change goes in `ThirdParty/mgba/patches/` and must be published) |
| inih (inside mGBA) | mGBA's config parser | BSD-3-Clause (`inih-BSD-3-Clause.txt`) | via mGBA | No |
| ares (commit 0b92893) | SNES and Mega Drive cores, nall, libco | ISC (`ares-ISC-and-bundled.txt`) | https://github.com/ares-emulator/ares | No (our stand-in headers live in `Sources/ARES/glue/shim`) |
| MAME-derived code (inside ares) | Sega Z80 decryption tables | BSD-3-Clause (in `ares-ISC-and-bundled.txt`) | via ares | No |
| qon (inside ares) | ares utility | MIT (`qon-MIT.txt`) | via ares | No |
| melonDS (commit 497aa6c) | Nintendo DS core (DS mode, interpreter) | GPL-3.0-or-later (`melonDS-GPL-3.0.txt`) | https://github.com/melonDS-emu/melonDS | No (unmodified files in `Packages/CoreKit/Sources/MELONDS/melonds`; our shims, stubs and build units in `Sources/MELONDS/glue`; see `ThirdParty/melonds/README.md`) |
| FreeBIOS (inside melonDS) | the DS's ARM9/ARM7 BIOS, an independent replacement (no Nintendo code) | BSD-2-Clause (`FreeBIOS-BSD-2-Clause.txt`) | via melonDS (`freebios/`) | No |
| mupen64plus-core (commit daae68e) | Nintendo 64 core (cached interpreter, HLE boot, no PIF ROM) and its ROM database `mupen64plus.ini` (save types; no game data) | GPL-2.0-or-later (`mupen64plus-GPL-2.0-or-later.txt`) | https://github.com/mupen64plus/mupen64plus-core | No (unmodified files in `Packages/CoreKit/Sources/MUPEN64/mupen64plus-core`; our front end, plugins and stand-ins in `Sources/MUPEN64/glue`; see `ThirdParty/mupen64/README.md`) |
| mupen64plus-rsp-hle (commit 4cdc305) | the N64's RSP, high-level (audio and other microcode tasks) | GPL-2.0-or-later (same file) | https://github.com/mupen64plus/mupen64plus-rsp-hle | No (`Sources/MUPEN64/rsp-hle`) |
| paraLLEl-RDP (parallel-rdp-standalone commit 388d70f) with Granite's Vulkan backend and volk | Nintendo 64 graphics (RDP) in Vulkan compute shaders on the GPU | MIT (`paraLLEl-RDP-MIT.txt`) | https://github.com/Themaister/parallel-rdp-standalone | No (unmodified files in `Packages/CoreKit/Sources/MUPEN64/parallel-rdp`; our build units and glue in `Sources/MUPEN64/glue/rdp`) |
| Vulkan-Headers (inside paraLLEl-RDP and MoltenVK) | Vulkan API declarations | Apache-2.0 (`MoltenVK-Apache-2.0-and-bundled.txt`) | https://github.com/KhronosGroup/Vulkan-Headers | No |
| MoltenVK v1.4.2 (prebuilt static library), incl. SPIRV-Cross and cereal | Vulkan on Metal for the N64 renderer (iPhone/iPad builds) | Apache-2.0; cereal BSD-3-Clause (`MoltenVK-Apache-2.0-and-bundled.txt`) | https://github.com/KhronosGroup/MoltenVK | No (`ThirdParty/moltenvk`, the release's unmodified `libMoltenVK.a`) |
| cxd4 RSP interpreter (mupen64plus-rsp-cxd4 commit b8e747b) | the N64's RSP for graphics microcode (low-level) | CC0 1.0 (`cxd4-CC0-1.0.txt`); its `osal_dynamiclib.h` GPL-2.0-or-later | https://github.com/mupen64plus/mupen64plus-rsp-cxd4 | No (unmodified files in `Sources/MUPEN64/rsp-cxd4`; build unit `glue/rdp/cxd4_unit.c` disables its signal-handler and `srand` calls with macros) |
| MiniZip, MD5, xxHash, CIC-NUS-6105 algorithm (inside mupen64plus-core) | zip states, ROM hashing, the 6105 cartridge challenge | zlib, zlib-style, BSD-2-Clause, BSD-2-Clause (`mupen64plus-bundled.txt`) | via mupen64plus-core | No |
| xxHash, FatFs headers, tiny-AES-c headers, blip_buf (inside melonDS) | hashing, declarations, audio resampler | BSD-2-Clause, FatFs (1-clause), Unlicense, LGPL-2.1-or-later (`melonDS-bundled.txt`) | via melonDS | No |

## Bundled homebrew demos (game files, not program code)

Five freely licensed homebrew games ship as separate game files in `App/Resources/Demos/` and are copied onto the
shelf on first launch (deletable, never re-seeded). Each is the author's unmodified build. Credits, notices and
source locations: `demos-credits.txt`; full texts `GPL-3.0.txt` and `CC-BY-SA-4.0.txt`. The Release ROM check in
`project.yml` allows exactly these five files, by name and SHA-256. The exact upstream source archives of the three
GPL demos (µCity 1.3, Thwaite 0.03, Alex vs Bus pre3) are kept in `release-sources/` for GPLv3 §6.

| Demo | System | Author | Licence | Source |
|---|---|---|---|---|
| µCity 1.3 (`ucity.gbc`) | GBC | Antonio Niño Díaz | GPL-3.0-or-later code (GBT Player BSD-2-Clause), CC BY-SA 4.0 media | https://codeberg.org/SkyLyrac/ucity |
| Libbet and the Magic Floor 0.08 (`libbet.gb`) | GB | Damian Yerrick | zlib | https://github.com/pinobatch/libbet |
| Thwaite 0.03 (`thwaite.nes`) | NES | Damian Yerrick | GPL-3.0-or-later | https://github.com/pinobatch/thwaite-nes |
| Concentration Room 0.02 (`croom.nes`) | NES | Damian Yerrick | GPL-3.0-or-later + exact-copy exception | https://github.com/pinobatch/croom-nes |
| Alex vs Bus: The Race pre3 (`alexvsbus-pre3.md`) | Mega Drive | M374LX | GPL-3.0-or-later code, CC BY-SA 4.0 assets | https://github.com/M374LX/alexvsbus-md |

The same texts ship inside the app (`App/Resources/Licences/`) and are shown on the
Acknowledgements screen.

**Not included: GLideN64.** The planned N64 video plugin is licensed "under the GNU General Public
License version 2" with no "or later" option (its LICENSE file; its source files carry no licence
header), which cannot be combined into a GPLv3 app. It is not vendored. See `ThirdParty/mupen64/README.md`. The app as a whole is GPLv3 (Gordon, 11 Nov 2026), which melonDS requires; every
other component's licence is GPLv3-compatible. No non-commercial or no-derivatives code is included.

**Apache-2.0 and the GPL:** MoltenVK and Vulkan-Headers are Apache-2.0, which is compatible with GPLv3 but not
GPLv2, so the app including its N64 part (mupen64plus: GPL-2.0-or-later) is distributed under GPLv3.
