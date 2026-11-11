# Homebrew bundle candidates

Web research done 2026-11-11. Nothing was downloaded. Licences were checked on the repo or LICENSE/credits file where one could be reached; anything checked only on a listing says so. The scope now allows GPL as well as permissive licences. Still excluded: NC, ND and no licence. Already shipped, so left out: Tobu Tobu Girl DX, Libbet, 2048-gb.

**The main finding: the solid list is short.** Most well-known homebrew either uses NC music or art, states no asset licence, or ships no ROM. GBA, SNES, N64 and PS1 have no verified entry yet.

## Candidates (best first)

| Game | System | Author | Family | Code licence | Asset licence | Prebuilt ROM (author) | Mapper / size | Toolchain / runtime concern | Quality |
|---|---|---|---|---|---|---|---|---|---|
| µCity | GBC | Antonio Niño Díaz | GPL | GPL-3.0+ (GBT Player is BSD-2) | CC BY-SA 4.0 | codeberg.org/SkyLyrac/ucity/releases (`ucity.gbc`; `ucity_compat.gbc` as fallback) | GBC only, battery save; MBC not stated in README, read it from the header | RGBDS, so no runtime library | Excellent; a deep SimCity-style game |
| Thwaite | NES | Damian Yerrick | GPL | GPL-3.0 (some helper files zlib-like) | No separate asset licence. Author made the art and music; extra music is Beethoven (public domain) | pineight.com/thwaite-0.03.zip (repo has no releases) | NROM (mapper 0) | ca65, author's own libraries | Very good; Missile Command-like |
| Concentration Room | NES | Damian Yerrick | GPL | GPL-3.0+, plus an exception that lets exact author builds be shared without source | Not stated separately (author-made) | pineight.com/croom/ConcentrationRoom-0.02.zip | NROM-128 (mapper 0) | ca65 | Good; polished memory game |
| Alex vs Bus: The Race | Mega Drive | M374LX | GPL | GPL-3.0+ | CC BY-SA 4.0 (assets folder) | github.com/M374LX/alexvsbus-md/releases (pre3) | Cartridge with SRAM saves; NTSC and PAL | vasm assembly, so no SGDK and no runtime library | Good; full runner, playable start to finish |
| Dusky Dungeon | GB/GBC | inverted-hat | Permissive | MIT | Art CC BY 4.0. Music from GB Studio Community Assets (MIT, credit not required). **Fonts unclear:** Gothic Pixel (Dacosta) and Romulus (Pix3M) | invertedhat.itch.io/dusky-dungeon (`DuskyDungeon-0.2.0.gb`, 512 KB) | GB Studio build, normally MBC5 | GB Studio engine (MIT) on GBDK-2020; check GBDK-2020's library licence and the two fonts | Decent early demo: one level and a boss, 4.2/5 from 8 ratings |
| Game (Boy) of Life | GB | StudioGuma / bit bang games | GPL | GPL-3.0 | CC BY-SA 4.0 | bit-bang-games.itch.io/game-boy-of-life (`life.gb`) | 32 KB, no MBC | GBDK-2020 4.2.0 plus hUGEDriver; check both licences | A toy, not a game: Conway's Life with music |
| Dessert on a Vegan Island | GB | basxto | Permissive | MIT | Per-file mix of CC0, CC BY 4.0, CC BY 3.0 and CC BY-SA 4.0. One tile licence is ambiguous | **No prebuilt ROM** | Not stated | SDCC / gbdk-n | Jam game, unfinished |
| DDNet (DS port) | DS | headshot2017 | Permissive | zlib-style Teeworlds/DDNet licence | `data/` is CC BY-SA 3.0; **the font has its own unstated licence** | **No prebuilt ROM** | **DSi mode only** | BlocksDS / libnds (zlib) | Good game, but see the BIOS note |

**Licence family** is permissive or GPL, as the brief asked.

**CC BY / BY-SA** assets need an in-app credits screen. BY-SA does not spread to the emulator itself.

**DS BIOS:** an ordinary NDS homebrew ROM normally direct-boots in melonDS or DeSmuME with their built-in replacement BIOS, without Nintendo firmware. A DSi-mode-only title like DDNet needs real DSi BIOS and NAND dumps in melonDS, so it **fails the no-BIOS rule**.

**Runtime-library licences** (for reference):
- libtonc: MIT, verified in Butano's licence folder
- libnds and BlocksDS: zlib (relicensed; an older libnds had no licence)
- SGDK: MIT, with its bundled GCC under the runtime exception
- PVSnesLib: MIT
- libdragon: Unlicense / public domain, from an aggregator and the n64brew wiki
- PSn00bSDK: MPL-2.0, and its README allows commercial use
- GBDK-2020: not checked here, so look it up before shipping any GBDK game
- Old GBDK 2.x, devkitARM's libgba, and Psy-Q (Sony proprietary): avoid

## Rejected

- **Butano Fighter** (GBA): code is zlib, but 7 of its 8 music tracks are NC, and one is also ND.
- **Varooom 3D** (GBA): models, music and voices are CC BY-NC-SA, and the eJay voice samples carry no licence.
- **Nova the Squirrel** (NES) and **Nova the Squirrel 2** (SNES): code is GPL, but the assets are CC BY-NC-SA and the author says the game may not be sold.
- **Petris** (GBC) and **Pluto's Corner** (GB): the repo LICENSE is CC BY-NC-SA 4.0, even though GitHub shows "MIT" for Petris.
- **Super Tilt Bro** (NES): code is WTFPL, but the ROM is mapper 30 (UNROM-512) or Rainbow, and many items are not freely licensed.
- **TANGLEWOOD** (MD): GPL-3.0 source, but the README forbids sharing unmodified binaries and the game is sold commercially.
- **Jump 'n Bump Genesis** (MD): code is GPL-2.0, but no asset licence is stated.
- **Mega Car Wars** (MD): MIT, but no asset licence and no ROM.
- **Town Quest** (MD), **BomberWorld** (SNES) and **Notris** (PS1): no licence at all. Notris also uses a Sony licence file the user has to extract.
- **Solar Guard** (GBA): GPL-3.0, but the OpenGameArt items and music sit under separate READMEs that I couldn't verify. Worth a second look if the README checks out.
- **minicraft-gba** (GBA): code is GPL-3.0, but it uses Notch's Minicraft assets with no licence.
- **ds-craft** (DS): MIT code, but uses Mojang textures and sounds.
- **Shock Lobster** (GB): the licence wasn't visible, and the enemy graphics are left out of the source for licensing reasons.
- **N64brew Game Jam 2024** (N64): code is MIT, but the many authors' minigame assets carry no stated licence. A per-minigame audit could rescue it; it is the best N64 lead.
- **Open Twin Dragons** (NES): code is zlib, but the README doesn't say which CC licence covers which assets, and the mapper isn't stated.
- **LAN Master / Lawn Mower** (NES, Shiru): a nesdev forum post calls them CC0, but Shiru's site calls them "freeware". The licence is inside the zip, which I didn't download.
- **AngunaDS** (DS): MIT only according to GameBrew; the Bitbucket source is unreachable.
- **Cave Story MD** and **YM2020**: art or music is copyrighted or NC.
- **engine-psx**: a Sonic fangame, so it uses Sega's IP.
