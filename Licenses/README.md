# Third-party licences

Foldback's NES and Game Boy / Game Boy Color cores, the app, its art and its test ROMs are our own.
These third-party components are compiled into the app:

| Component | Used for | Licence | Source | Modified? |
|---|---|---|---|---|
| mGBA (commit 662dada) | Game Boy Advance core, incl. its built-in (HLE) BIOS | MPL-2.0 (`mGBA-MPL-2.0.txt`) | https://github.com/mgba-emu/mgba | No (unmodified files in `Packages/CoreKit/Sources/MGBA/mgba`; any future change goes in `ThirdParty/mgba/patches/` and must be published) |
| inih (inside mGBA) | mGBA's config parser | BSD-3-Clause (`inih-BSD-3-Clause.txt`) | via mGBA | No |
| ares (commit 0b92893) | SNES and Mega Drive cores, nall, libco | ISC (`ares-ISC-and-bundled.txt`) | https://github.com/ares-emulator/ares | No (our stand-in headers live in `Sources/ARES/glue/shim`) |
| MAME-derived code (inside ares) | Sega Z80 decryption tables | BSD-3-Clause (in `ares-ISC-and-bundled.txt`) | via ares | No |
| qon (inside ares) | ares utility | MIT (`qon-MIT.txt`) | via ares | No |
| melonDS (commit 497aa6c) | Nintendo DS core (DS mode, interpreter) | GPL-3.0-or-later (`melonDS-GPL-3.0.txt`) | https://github.com/melonDS-emu/melonDS | No (unmodified files in `Packages/CoreKit/Sources/MELONDS/melonds`; our shims, stubs and build units in `Sources/MELONDS/glue`; see `ThirdParty/melonds/README.md`) |
| FreeBIOS (inside melonDS) | the DS's ARM9/ARM7 BIOS, an independent replacement (no Nintendo code) | BSD-2-Clause (`FreeBIOS-BSD-2-Clause.txt`) | via melonDS (`freebios/`) | No |
| mupen64plus-core (commit daae68e) | Nintendo 64 core (cached interpreter, HLE boot, no PIF ROM) and its ROM database `mupen64plus.ini` (save types; no game data) | GPL-2.0-or-later (`mupen64plus-GPL-2.0-or-later.txt`) | https://github.com/mupen64plus/mupen64plus-core | No (unmodified files in `Packages/CoreKit/Sources/MUPEN64/mupen64plus-core`; our front end, plugins and stand-ins in `Sources/MUPEN64/glue`; see `ThirdParty/mupen64/README.md`) |
| mupen64plus-rsp-hle (commit 4cdc305) | the N64's RSP, high-level (audio and other microcode tasks) | GPL-2.0-or-later (same file) | https://github.com/mupen64plus/mupen64plus-rsp-hle | No (`Sources/MUPEN64/rsp-hle`) |
| MiniZip, MD5, xxHash, CIC-NUS-6105 algorithm (inside mupen64plus-core) | zip states, ROM hashing, the 6105 cartridge challenge | zlib, zlib-style, BSD-2-Clause, BSD-2-Clause (`mupen64plus-bundled.txt`) | via mupen64plus-core | No |
| xxHash, FatFs headers, tiny-AES-c headers, blip_buf (inside melonDS) | hashing, declarations, audio resampler | BSD-2-Clause, FatFs (1-clause), Unlicense, LGPL-2.1-or-later (`melonDS-bundled.txt`) | via melonDS | No |

The same texts ship inside the app (`App/Resources/Licences/`) and are shown on the
Acknowledgements screen.

**Not included: GLideN64.** The planned N64 video plugin is licensed "under the GNU General Public
License version 2" with no "or later" option (its LICENSE file; its source files carry no licence
header), which cannot be combined into a GPLv3 app. It is not vendored. See `ThirdParty/mupen64/README.md`. The app as a whole is GPLv3 (Gordon, 11 Nov 2026), which melonDS requires; every
other component's licence is GPLv3-compatible. No non-commercial or no-derivatives code is included.
