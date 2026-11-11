# mGBA (vendored, GBA core only)

- Upstream: https://github.com/mgba-emu/mgba
- Snapshot: commit `662dada` (shallow clone, approved by Gordon; the clone lives in the gitignored
  `ThirdParty-src/mgba` and was never built with its own scripts)
- Licence: Mozilla Public License 2.0 (`LICENSE` here). MPL-2.0 is file-level copyleft: the vendored
  files stay MPL-2.0 and any modified mGBA file must be published in source form. Our own files
  (the glue, the Swift wrapper) are not MPL and may stay closed.

## Layout (decision)

SwiftPM won't let a target's `path:` leave the package root, so the vendored sources live **inside the
package**, unmodified, at `Packages/CoreKit/Sources/MGBA/mgba/` (same relative paths as upstream:
`include/...`, `src/...`). This folder (`ThirdParty/mgba/`) holds only the licence, this README, the
patches and the source of generated files. The `MGBA` C target also contains our own glue:

- `Sources/MGBA/glue/include/MGBAGlue.h`, `glue/mgba_glue.c`: our small C API over mGBA's `mCore`
  (the only header Swift sees). Ours, not MPL.
- `Sources/MGBA/glue/mgba_version.c`: replaces mGBA's CMake-generated `src/core/version.c`
  (from the MPL-2.0 template `src/core/version.c.in`); it only defines the version strings.

There is no generated `flags.h`: upstream only uses it for installed headers. The feature flags are
compile defines in `Packages/CoreKit/Package.swift` (`mgbaC`): `M_CORE_GBA`, `DISABLE_THREADING`,
`MINIMAL_CORE=2`, `MGBA_STANDALONE`, `_DARWIN_C_SOURCE`, `NDEBUG` and the Darwin `HAVE_*` functions.
Not defined (so compiled out): `M_CORE_GB`, `ENABLE_VFS` (no file access at all, so no BIOS file can
ever be loaded; the built-in HLE BIOS is used), `ENABLE_DEBUGGERS`, `ENABLE_SCRIPTING`, `USE_ZLIB`,
`USE_PNG`, `USE_LZMA`, `USE_ELF`, `USE_LIBZIP`, `USE_SQLITE3`, `USE_FFMPEG`, `USE_EPOXY`, `BUILD_GL*`,
`COLOR_16_BIT` (so the renderer writes 32-bit colour, which the glue converts to BGRA).
Upstream's own warnings are silenced (`-w`) for this target only; it builds `-O2` in every configuration.

Not vendored: GB/SM83 core (except `src/gb/audio.c`, the GBA's PSG), debugger, scripting, `feature/`,
GL renderer, `gba/extra` (proxy, battlechip), `gba/sio` lockstep/dolphin, frontends, tests, and all of
`src/third-party` except inih (needed by `util/configuration.c`, which `mCoreConfig` uses).

## Patches

**None.** Every vendored file is byte-identical to upstream `662dada`. If one ever has to change, save a
unified diff against the pristine file as `patches/NNN-name.patch` and list it here (MPL-2.0 requires
publishing modified files).

## Generated sources

`src/gba/hle-bios.c` (the HLE BIOS image as a C array) is generated upstream from
`generated-sources/hle-bios.s` (MPL-2.0) by `generated-sources/hle-bios.make`. Both are kept here as
the source form of that file.

## Licence audit

170 vendored files (73 `.c`, 97 `.h`, about 1.8 MB):

- 164 files: MPL-2.0 header.
- `src/gba/hle-bios.c`: MPL-2.0 (generated from `hle-bios.s`, which carries the MPL-2.0 header).
- `src/util/gbk-table.c`: no header (a GBK to Unicode data table); covered by the repository's MPL-2.0.
- `src/util/crc32.c`: Gary S. Brown's CRC-32 ("You may use this program, or code or tables extracted
  from it, as desired without restriction"); permissive.
- `src/util/hash.c`: MurmurHash3, public domain (Austin Appleby).
- `src/third-party/inih/ini.c`, `ini.h`: BSD-3-Clause (Ben Hoyt), text in `LICENSE-inih.txt`
  (its attribution must appear in the app's acknowledgements).

No GPL, LGPL or non-commercial code. The app's acknowledgements need: mGBA (MPL-2.0, with a link to
the source of the files we ship), inih (BSD-3-Clause notice).

## Files

| File (under `Packages/CoreKit/Sources/MGBA/mgba/`) | Bytes | Licence |
|---|---:|---|
| `include/mgba-util/audio-buffer.h` | 1246 | MPL-2.0 (header) |
| `include/mgba-util/audio-resampler.h` | 1200 | MPL-2.0 (header) |
| `include/mgba-util/circle-buffer.h` | 1588 | MPL-2.0 (header) |
| `include/mgba-util/common.h` | 12589 | MPL-2.0 (header) |
| `include/mgba-util/configuration.h` | 2088 | MPL-2.0 (header) |
| `include/mgba-util/crc32.h` | 584 | MPL-2.0 (header) |
| `include/mgba-util/dllexports.h` | 523 | MPL-2.0 (header) |
| `include/mgba-util/formatting.h` | 890 | MPL-2.0 (header) |
| `include/mgba-util/geometry.h` | 704 | MPL-2.0 (header) |
| `include/mgba-util/hash.h` | 411 | MPL-2.0 (header) |
| `include/mgba-util/image.h` | 10663 | MPL-2.0 (header) |
| `include/mgba-util/interpolator.h` | 1226 | MPL-2.0 (header) |
| `include/mgba-util/math.h` | 3996 | MPL-2.0 (header) |
| `include/mgba-util/md5.h` | 952 | MPL-2.0 (header) |
| `include/mgba-util/memory.h` | 443 | MPL-2.0 (header) |
| `include/mgba-util/patch.h` | 638 | MPL-2.0 (header) |
| `include/mgba-util/patch/fast.h` | 874 | MPL-2.0 (header) |
| `include/mgba-util/patch/ips.h` | 415 | MPL-2.0 (header) |
| `include/mgba-util/patch/ups.h` | 415 | MPL-2.0 (header) |
| `include/mgba-util/sha1.h` | 796 | MPL-2.0 (header) |
| `include/mgba-util/string.h` | 1930 | MPL-2.0 (header) |
| `include/mgba-util/table.h` | 4219 | MPL-2.0 (header) |
| `include/mgba-util/threading.h` | 2498 | MPL-2.0 (header) |
| `include/mgba-util/vector.h` | 4475 | MPL-2.0 (header) |
| `include/mgba-util/vfs.h` | 3583 | MPL-2.0 (header) |
| `include/mgba/core/bitmap-cache.h` | 1956 | MPL-2.0 (header) |
| `include/mgba/core/cache-set.h` | 1087 | MPL-2.0 (header) |
| `include/mgba/core/cheats.h` | 3205 | MPL-2.0 (header) |
| `include/mgba/core/config.h` | 4236 | MPL-2.0 (header) |
| `include/mgba/core/core.h` | 8825 | MPL-2.0 (header) |
| `include/mgba/core/cpu.h` | 833 | MPL-2.0 (header) |
| `include/mgba/core/input.h` | 4062 | MPL-2.0 (header) |
| `include/mgba/core/interface.h` | 4748 | MPL-2.0 (header) |
| `include/mgba/core/log.h` | 2586 | MPL-2.0 (header) |
| `include/mgba/core/map-cache.h` | 2692 | MPL-2.0 (header) |
| `include/mgba/core/serialize.h` | 1834 | MPL-2.0 (header) |
| `include/mgba/core/sync.h` | 1307 | MPL-2.0 (header) |
| `include/mgba/core/tile-cache.h` | 2017 | MPL-2.0 (header) |
| `include/mgba/core/timing.h` | 1600 | MPL-2.0 (header) |
| `include/mgba/core/version.h` | 740 | MPL-2.0 (header) |
| `include/mgba/debugger/debugger.h` | 7751 | MPL-2.0 (header) |
| `include/mgba/feature/video-logger.h` | 4821 | MPL-2.0 (header) |
| `include/mgba/gb/interface.h` | 2581 | MPL-2.0 (header) |
| `include/mgba/gba/core.h` | 480 | MPL-2.0 (header) |
| `include/mgba/gba/interface.h` | 4703 | MPL-2.0 (header) |
| `include/mgba/internal/arm/arm.h` | 5022 | MPL-2.0 (header) |
| `include/mgba/internal/arm/debugger/debugger.h` | 1497 | MPL-2.0 (header) |
| `include/mgba/internal/arm/decoder-inlines.h` | 820 | MPL-2.0 (header) |
| `include/mgba/internal/arm/decoder.h` | 6107 | MPL-2.0 (header) |
| `include/mgba/internal/arm/emitter-arm.h` | 21774 | MPL-2.0 (header) |
| `include/mgba/internal/arm/emitter-inlines.h` | 635 | MPL-2.0 (header) |
| `include/mgba/internal/arm/emitter-thumb.h` | 5331 | MPL-2.0 (header) |
| `include/mgba/internal/arm/isa-arm.h` | 551 | MPL-2.0 (header) |
| `include/mgba/internal/arm/isa-inlines.h` | 6292 | MPL-2.0 (header) |
| `include/mgba/internal/arm/isa-thumb.h` | 495 | MPL-2.0 (header) |
| `include/mgba/internal/arm/macros.h` | 484 | MPL-2.0 (header) |
| `include/mgba/internal/debugger/cli-debugger.h` | 3036 | MPL-2.0 (header) |
| `include/mgba/internal/debugger/symbols.h` | 992 | MPL-2.0 (header) |
| `include/mgba/internal/defines.h` | 854 | MPL-2.0 (header) |
| `include/mgba/internal/gb/audio.h` | 6783 | MPL-2.0 (header) |
| `include/mgba/internal/gb/gb.h` | 4143 | MPL-2.0 (header) |
| `include/mgba/internal/gb/io.h` | 2634 | MPL-2.0 (header) |
| `include/mgba/internal/gb/memory.h` | 8383 | MPL-2.0 (header) |
| `include/mgba/internal/gb/serialize.h` | 14771 | MPL-2.0 (header) |
| `include/mgba/internal/gb/sio.h` | 1169 | MPL-2.0 (header) |
| `include/mgba/internal/gb/timer.h` | 1038 | MPL-2.0 (header) |
| `include/mgba/internal/gb/video.h` | 5561 | MPL-2.0 (header) |
| `include/mgba/internal/gba/audio.h` | 6927 | MPL-2.0 (header) |
| `include/mgba/internal/gba/bios.h` | 2199 | MPL-2.0 (header) |
| `include/mgba/internal/gba/cart/ereader.h` | 3547 | MPL-2.0 (header) |
| `include/mgba/internal/gba/cart/gpio.h` | 2821 | MPL-2.0 (header) |
| `include/mgba/internal/gba/cart/matrix.h` | 916 | MPL-2.0 (header) |
| `include/mgba/internal/gba/cart/unlicensed.h` | 1938 | MPL-2.0 (header) |
| `include/mgba/internal/gba/cheats.h` | 4154 | MPL-2.0 (header) |
| `include/mgba/internal/gba/debugger/cli.h` | 597 | MPL-2.0 (header) |
| `include/mgba/internal/gba/dma.h` | 2022 | MPL-2.0 (header) |
| `include/mgba/internal/gba/gba.h` | 4429 | MPL-2.0 (header) |
| `include/mgba/internal/gba/input.h` | 686 | MPL-2.0 (header) |
| `include/mgba/internal/gba/io.h` | 4902 | MPL-2.0 (header) |
| `include/mgba/internal/gba/memory.h` | 5138 | MPL-2.0 (header) |
| `include/mgba/internal/gba/overrides.h` | 558 | MPL-2.0 (header) |
| `include/mgba/internal/gba/renderers/cache-set.h` | 628 | MPL-2.0 (header) |
| `include/mgba/internal/gba/renderers/common.h` | 635 | MPL-2.0 (header) |
| `include/mgba/internal/gba/renderers/proxy.h` | 928 | MPL-2.0 (header) |
| `include/mgba/internal/gba/renderers/video-software.h` | 3251 | MPL-2.0 (header) |
| `include/mgba/internal/gba/savedata.h` | 3546 | MPL-2.0 (header) |
| `include/mgba/internal/gba/serialize.h` | 15644 | MPL-2.0 (header) |
| `include/mgba/internal/gba/sharkport.h` | 947 | MPL-2.0 (header) |
| `include/mgba/internal/gba/sio.h` | 2755 | MPL-2.0 (header) |
| `include/mgba/internal/gba/sio/gbp.h` | 895 | MPL-2.0 (header) |
| `include/mgba/internal/gba/timer.h` | 965 | MPL-2.0 (header) |
| `include/mgba/internal/gba/video.h` | 7500 | MPL-2.0 (header) |
| `src/arm/arm.c` | 7340 | MPL-2.0 (header) |
| `src/arm/decoder-arm.c` | 20313 | MPL-2.0 (header) |
| `src/arm/decoder-thumb.c` | 13627 | MPL-2.0 (header) |
| `src/arm/decoder.c` | 15324 | MPL-2.0 (header) |
| `src/arm/isa-arm.c` | 32480 | MPL-2.0 (header) |
| `src/arm/isa-thumb.c` | 15420 | MPL-2.0 (header) |
| `src/core/bitmap-cache.c` | 5953 | MPL-2.0 (header) |
| `src/core/cache-set.c` | 3071 | MPL-2.0 (header) |
| `src/core/cheats.c` | 21736 | MPL-2.0 (header) |
| `src/core/config.c` | 18720 | MPL-2.0 (header) |
| `src/core/core.c` | 13844 | MPL-2.0 (header) |
| `src/core/interface.c` | 4562 | MPL-2.0 (header) |
| `src/core/log.c` | 7704 | MPL-2.0 (header) |
| `src/core/map-cache.c` | 8313 | MPL-2.0 (header) |
| `src/core/serialize.c` | 15793 | MPL-2.0 (header) |
| `src/core/sync.c` | 3307 | MPL-2.0 (header) |
| `src/core/tile-cache.c` | 9771 | MPL-2.0 (header) |
| `src/core/timing.c` | 3758 | MPL-2.0 (header) |
| `src/gb/audio.c` | 39158 | MPL-2.0 (header) |
| `src/gba/audio.c` | 20244 | MPL-2.0 (header) |
| `src/gba/bios.c` | 31030 | MPL-2.0 (header) |
| `src/gba/cart/ereader.c` | 46888 | MPL-2.0 (header) |
| `src/gba/cart/gpio.c` | 16920 | MPL-2.0 (header) |
| `src/gba/cart/matrix.c` | 4243 | MPL-2.0 (header) |
| `src/gba/cart/unlicensed.c` | 9244 | MPL-2.0 (header) |
| `src/gba/cart/vfame.c` | 10264 | MPL-2.0 (header) |
| `src/gba/cheats.c` | 10757 | MPL-2.0 (header) |
| `src/gba/cheats/codebreaker.c` | 9214 | MPL-2.0 (header) |
| `src/gba/cheats/gameshark.c` | 11224 | MPL-2.0 (header) |
| `src/gba/cheats/gameshark.h` | 1111 | MPL-2.0 (header) |
| `src/gba/cheats/parv3.c` | 13873 | MPL-2.0 (header) |
| `src/gba/cheats/parv3.h` | 610 | MPL-2.0 (header) |
| `src/gba/core.c` | 65488 | MPL-2.0 (header) |
| `src/gba/dma.c` | 14934 | MPL-2.0 (header) |
| `src/gba/gba.c` | 30196 | MPL-2.0 (header) |
| `src/gba/hle-bios.c` | 7186 | MPL-2.0 (generated from hle-bios.s, MPL-2.0 header; no header of its own) |
| `src/gba/hle-bios.h` | 390 | MPL-2.0 (header) |
| `src/gba/input.c` | 657 | MPL-2.0 (header) |
| `src/gba/io.c` | 31729 | MPL-2.0 (header) |
| `src/gba/memory.c` | 65084 | MPL-2.0 (header) |
| `src/gba/overrides.c` | 15346 | MPL-2.0 (header) |
| `src/gba/renderers/cache-set.c` | 10688 | MPL-2.0 (header) |
| `src/gba/renderers/common.c` | 1951 | MPL-2.0 (header) |
| `src/gba/renderers/software-bg.c` | 7646 | MPL-2.0 (header) |
| `src/gba/renderers/software-mode0.c` | 17283 | MPL-2.0 (header) |
| `src/gba/renderers/software-obj.c` | 16508 | MPL-2.0 (header) |
| `src/gba/renderers/software-private.h` | 13265 | MPL-2.0 (header) |
| `src/gba/renderers/video-software.c` | 44491 | MPL-2.0 (header) |
| `src/gba/savedata.c` | 26055 | MPL-2.0 (header) |
| `src/gba/serialize.c` | 9745 | MPL-2.0 (header) |
| `src/gba/sharkport.c` | 8895 | MPL-2.0 (header) |
| `src/gba/sio.c` | 14865 | MPL-2.0 (header) |
| `src/gba/sio/gbp.c` | 4971 | MPL-2.0 (header) |
| `src/gba/timer.c` | 5731 | MPL-2.0 (header) |
| `src/gba/video.c` | 15763 | MPL-2.0 (header) |
| `src/third-party/inih/ini.c` | 7882 | BSD-3-Clause (Ben Hoyt; see LICENSE-inih.txt) |
| `src/third-party/inih/ini.h` | 4997 | BSD-3-Clause (Ben Hoyt; see LICENSE-inih.txt) |
| `src/util/audio-buffer.c` | 2501 | MPL-2.0 (header) |
| `src/util/audio-resampler.c` | 3197 | MPL-2.0 (header) |
| `src/util/circle-buffer.c` | 7884 | MPL-2.0 (header) |
| `src/util/configuration.c` | 7319 | MPL-2.0 (header) |
| `src/util/crc32.c` | 6110 | Gary S. Brown CRC-32: 'use ... without restriction' (permissive) |
| `src/util/formatting.c` | 2164 | MPL-2.0 (header) |
| `src/util/gbk-table.c` | 192662 | no header; data table, covered by the repository's MPL-2.0 LICENSE |
| `src/util/hash.c` | 2097 | MurmurHash3, public domain (Austin Appleby) |
| `src/util/interpolator.c` | 3660 | MPL-2.0 (header) |
| `src/util/md5.c` | 7134 | MPL-2.0 (header) |
| `src/util/memory.c` | 430 | MPL-2.0 (header) |
| `src/util/patch-fast.c` | 3573 | MPL-2.0 (header) |
| `src/util/patch-ips.c` | 2333 | MPL-2.0 (header) |
| `src/util/patch-ups.c` | 7891 | MPL-2.0 (header) |
| `src/util/patch.c` | 584 | MPL-2.0 (header) |
| `src/util/sha1.c` | 7143 | MPL-2.0 (header) |
| `src/util/string.c` | 14218 | MPL-2.0 (header) |
| `src/util/table.c` | 21091 | MPL-2.0 (header) |
| `src/util/vector.c` | 669 | MPL-2.0 (header) |
| `src/util/vfs.c` | 7598 | MPL-2.0 (header) |
| `src/util/vfs/vfs-mem.c` | 7681 | MPL-2.0 (header) |
