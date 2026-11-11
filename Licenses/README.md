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

The same texts ship inside the app (`App/Resources/Licences/`) and are shown on the
Acknowledgements screen. No GPL, LGPL or non-commercial code is included.
