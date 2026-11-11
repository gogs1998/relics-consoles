# HANDOFF: Duo Emulator ("Foldback")

## Update, 11 Nov 2026 (second phase, after Gordon approved the downloads)
- **Systems that play (simulator + Mac tests):** NES and Game Boy / Color (in-house), Game Boy Advance (mGBA,
  HLE BIOS), SNES and Mega Drive (ares). Master System / Game Gear / PC Engine were not attempted.
  GBA/SNES/MD are proven only with our own hand-assembled test ROMs plus Libbet (approved homebrew, GB):
  no other homebrew could be used (Tobu Tobu Girl DX, 2048-gb and Super Tilt Bro ship no prebuilt ROMs and
  building them needs toolchains that weren't approved; Super Tilt Bro also needs an unsupported mapper).
- **Accuracy:** `docs/accuracy.md`. nestest pass; blargg NES 100 pass / 11 fail; AccuracyCoin 87/147;
  blargg GB 38/58 (all CPU/timing suites pass, APU/OAM-bug edge cases fail); Mooneye 75/94; acid2 2/2.
- **Reviews (Fable):** NES core PASS WITH FIXES (all 4 applied); app shell + mGBA/ares glue PASS WITH FIXES
  (all 6 applied, incl. rewriting the SPC700 boot program, which the helper had derived from Nintendo's IPL);
  GB core fixes 1-3 applied (MBC3 RTC now ticks and saves).
- **Licences:** `Licenses/README.md` + texts; in-app About screen (library ⓘ) shows them with exact versions.
- **New screenshots:** `docs/shots/table-gba.png`, `table-snes.png`, `table-md6.png`, `book-snes.png`,
  `iphone-gba.png`, `iphone-about.png`, refreshed `iphone-library.png` / `table-library.png` (every card now
  has its own generated label).
- **TestFlight: NOT uploaded.** The upload command was refused by the session's permission system (an
  upload needs Gordon's own go-ahead in chat, not a coordinator message). Everything is committed and the
  Release build passes its no-ROM check. To upload: `cd ~/duo-emulator && xcodegen generate &&
  ~/duo-remote/Tools/upload.sh /Users/gordonshepherd/duo-emulator DuoEmulator /private/tmp/duo-emulator-upload`,
  then `rm -rf /private/tmp/duo-emulator-upload`. CURRENT_PROJECT_VERSION is 1.
- **Decisions for Gordon (new):** approve shipping our own SPC700 boot program (or drop SNES); Tobu Tobu Girl
  DX as a bundled demo (needs GBDK to build, not approved); MD 6-button pad is always presented to games (a few
  dislike it); per-system GBA rewind is shorter (big states).
- **Still open:** MD EEPROM saves (needs ares' hash database), SNES/MD/GBA RTC persistence, iPhone performance
  of the ares MD core (cycle-accurate VDP: 200-240 fps on an M4 in a debug test build), everything device-only.

---


Night of 10-11 Nov 2026. Built autonomously while Gordon slept. Nothing pushed, no App Store Connect
record, no TestFlight, bundle id not registered, nothing downloaded except what Xcode resolves for DuoKit.

## State in one paragraph
The research and design docs exist (design approved with changes by a Fable review; changes folded in,
`docs/design.md` §10). CoreKit holds a clean core protocol and two in-house cores: **NES** (6502, PPU, APU,
mappers 0/1/2/3/4/7) and **Game Boy / Game Boy Color** (SM83, PPU, APU, MBC1/2/3/5; helper-built, Fable
reviewed; must-fixes 1 and 3 applied, 2 open). The app shell has the shelf, Files import, Metal renderer with four
screen modes, AVAudioEngine audio, the Graphite and Ember touch controller in table / book / portrait /
landscape arrangements, GameController and keyboard input, save states (4 slots + auto), battery saves,
rewind and fast-forward. It runs in the simulator with our own NES and GB test carts: picture, sound and
touch input are verified there (details below). **Nothing has run on a device yet.**

## What is verified, and how
| Claim | Evidence | Where tested |
|---|---|---|
| NES CPU correct for 24 instruction groups (flags, all addressing modes, page-cross, JMP bug, BRK/RTI, stack wrap, unofficial opcodes, PPU buffer reads) | `cpu_selftest.nes` reports PASS | Mac (`swift test`) |
| Mappers 0, 1, 2, 3, 4 (incl. MMC3 scanline IRQ) bank correctly | `mmc1/uxrom/cnrom/mmc3_probe.nes` PASS | Mac |
| NES picture: split scroll via sprite-0, two nametables, attributes, sprite flips; sound non-silent; save-state round trip bit-exact | `NESCoreTests` | Mac |
| GB/GBC CPU, timer, interrupts, HALT bug, DMA/HDMA, double speed, MBCs | `gb_selftest.gb`, `gb_cgbtest.gbc` PASS, 13 GB tests | Mac |
| Speed: NES ~1,000 fps, GB ~4,500 fps on the Mac in a *debug* test build (16x / 75x real time) | `speed` tests | Mac |
| App plays the NES demo with picture | screenshots `docs/shots/` | Simulator |
| **Touch input drives the game**: holding the D-pad moved the mascot, B swapped its palette, A made it jump; Start/Select not triggered by accident | `UITests/TouchInputUITests` (XCUITest taps through the real UIKit touch surface; DEBUG readout of pressed bits) | Simulator |
| **Sound**: AVAudioEngine pulls 48,000 samples/s from the ring; peak level 0.2 (not silent); queue stays at 800-1,500 samples | `ScreenshotUITests.testAudioFlows` + `os_log` (`com.iqlabs.duoemulator:audio`) | Simulator (I could not *hear* it) |
| Release bundle carries no ROM files | build phase fails a Release build if any .nes/.gb/.gbc/.zip is inside | build script |

Simulator-only (needs Gordon on a device): how the audio actually sounds and its latency, haptics, the
feel of the controller under thumbs, MFi/Xbox/PlayStation controllers and keyboards, real Duo poses and
hinge, ProMotion pacing, battery and thermal behaviour, Files import from iCloud Drive.

## Screenshots (`docs/shots/`)
- `table-nes.png`: Duo table pose, NES test cart top, full controller bottom.
- `table-gbc.png`: Duo table pose with the Game Boy Color test cart.
- `table-menu.png`: pause menu opening on the bottom half.
- `book-nes.png`: Duo book pose (landscape): game + D-pad left page, save shelf + buttons right page.
- `iphone-nes.png`: ordinary iPhone portrait (no Duo letterbox).
- `iphone-landscape-gbc.png`: ordinary iPhone landscape.
- `table-library.png`, `iphone-library.png`: the shelf.
- `touch-table.png`: frame captured by the touch test right after D-pad/B/A presses.
All from an iPhone 17e simulator; Duo poses use DuoKit's DEBUG `-pose` fold simulator, letterboxed to the
Duo's 1.42 aspect, so the halves are ~60 % of real Duo size (things look more cramped than on hardware).

## Simulator note (shared Mac)
Two simulators were already booted (Shared iPhone 17e and Relics Duo, both idle since the previous day),
so booting my own would have broken the two-booted rule. I used the already-booted **Shared iPhone 17e**
(7D99EA24) instead, logged in SIMS.txt, and did not boot, shut down or erase anything. I uninstalled my app
from it at the end. D8C4096C was never touched.

## Decisions for Gordon
1. **Name.** "Foldback" is a placeholder (no console brand; trademark search not done). Bundle id follows.
2. **Free or paid.** Licensing is the same either way for our in-house cores; it decides which licensed
   cores are possible (research §2: mGBA MPL-2.0 and ares ISC work for paid; Snes9x/Genesis Plus GX never).
3. **Download approvals** (nothing downloaded tonight), in order of value:
   - Test suites (all for testing only, not shipping): see the table below.
   - Cores: **mGBA** for GBA (MPL-2.0), **ares** for SNES / Mega Drive / Master System / PC Engine (ISC).
4. **Bundle a homebrew demo?** e.g. Tobu Tobu Girl DX (MIT code, CC BY 4.0 art) so the shelf isn't empty
   on first launch. Needs attribution; makes App Review easier. Or keep our own test carts out of Release.
5. **Box art:** none in v1 (OpenVGDB/libretro-thumbnails licences unclear); we generate label cards.
6. **iCloud sync** of saves (v1.1) needs an iCloud container decision.

### Download list awaiting approval (name, source, licence, approx size)
| Name | Source | Licence | Size |
|---|---|---|---|
| nestest + blargg NES suites | https://github.com/christopherpow/nes-test-roms | none stated (testing only) | 5.8 MB repo |
| AccuracyCoin | https://github.com/100thCoin/AccuracyCoin | MIT | 3 MB repo |
| Holy Mapperel | https://github.com/pinobatch/holy-mapperel | zlib | 60 KB |
| allpads-nes | https://github.com/pinobatch/allpads-nes | zlib | 80 KB |
| 240p-test-mini (NES/GB) | https://github.com/pinobatch/240p-test-mini | GPL-2.0 (test only) | 2.4 MB repo |
| Mooneye test suite | https://github.com/Gekkio/mooneye-test-suite | MIT | 0.2 MB |
| dmg-acid2 / cgb-acid2 | https://github.com/mattcurrie/dmg-acid2 , .../cgb-acid2 | MIT | 32 KB ROM each |
| Mealybug Tearoom tests | https://github.com/mattcurrie/mealybug-tearoom-tests | MIT | 62 MB repo (images) |
| blargg GB tests | https://github.com/retrio/gb-test-roms | none stated (testing only) | 0.2 MB |
| c-sp game-boy-test-roms | https://github.com/c-sp/game-boy-test-roms | MIT (+ each suite's own) | release zip |
| Tobu Tobu Girl DX (demo candidate) | https://github.com/SimonLarsen/tobutobugirl-dx | MIT code, CC BY 4.0 assets | 1.9 MB repo |
| Libbet, 2048-gb, Super Tilt Bro (homebrew) | github.com/pinobatch/libbet , gb-archive/2048-gb , sgadrat/super-tilt-bro | zlib, zlib, WTFPL | 0.9 / 0.05 / 5.9 MB |
| mGBA core | https://github.com/mgba-emu/mgba | MPL-2.0 | 59 MB repo |
| ares (SNES/MD/SMS/PCE cores) | https://github.com/ares-emulator/ares | ISC (+ bundled BSD/zlib/MPL parts) | 183 MB repo |

## Known gaps and next steps
- GB review: fixes 1 (EI;HALT halt bug) and 3 (lines redrawn at the end of mode 3) are applied; **fix 2
  is still open**: the MBC3 real-time clock doesn't tick or persist (affects clock-based games). Per-pixel
  mid-line effects are still not modelled. NES: no PAL, no
  mappers beyond 0/1/2/3/4/7 (add 9/10/11/66/69 next), sprite overflow bug not modelled, DMC DMA timing
  approximate, MMC3 IRQ uses the dot-260 approximation rather than watching A12.
- Not built yet: remapping UI, cheats, zip import, iCloud sync, skins, settings screen (haptics toggle,
  audio mix setting, pixel aspect), overscan crop, `CAMetalDisplayLink` pacing, three-texture ring,
  widgets, AirPlay screen.
- Library labels are generated (stripes and a sun in the system tint) until a game has been played,
  when the auto-save screenshot becomes the artwork; a shelf of unplayed games looks samey.
- Library on Duo: tap selects then tap again plays (hero panel on the top half); might want a direct play
  gesture. Context menu has rename/remove ("Recently Deleted" folder in Files).
- The rewind snapshot is a full state every 4 frames; fine for NES/GB (~10-30 KB), would need delta
  compression for bigger systems.

## How to run
```
python3 Tools/build_test_roms.py && python3 Tools/build_gb_roms.py   # our own test ROMs
cd Packages/CoreKit && swift test --scratch-path ../../build/corekit  # cores, on the Mac
xcodegen generate && Tools/build.sh                                   # app, simulator, under the lock
Tools/uitest.sh <simulator UDID>                                      # touch, audio and screenshot tests
xcrun simctl launch <UDID> com.iqlabs.duoemulator -pose table -autoplay demo.nes
```
