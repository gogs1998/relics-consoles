# Relics: Consoles roadmap

## v1.0 (build 10, LIVE by 2026-11-18)
NES, Game Boy / Game Boy Color, Game Boy Advance, SNES, Mega Drive, DS and N64, plus the iPhone Duo features and customisable controls.

## 1.1 / v2 (agreed with Gordon)
- Two-phone multiplayer over local Wi-Fi ("Wi-Fi play").
- DS GPU renderer.
- Original controller skins: our own colours and materials, never console trade dress. Skin import comes later.
- Tidy the controller-connected panel: empty save slots look broken, so move the hotkeys behind a "?".
- The portrait screen bezel should hug the picture (`PlayerView.portraitLayout` screenH).
- A "hide demos" switch.
- "More from Relics" cross-promo (on branch v1.1 in `~/duo-emulator-1.1`; needs rebasing onto the rename).
- **Check layout on older iOS (found 2026-11-18, sim only):** on an iOS 27.0 iPhone simulator the stage canvas is smaller than the
  screen. The shelf is cut off about 80% of the way down, and the landscape controls bunch in against the picture. iOS 27.1 is
  fine (the 1.0 shots). Deployment target is iOS 26, so check on 26.x and 27.0 (DuoStage bounds 390x763 = safe area, then inset again?).
- **Store screenshots reshoot (Gordon 2026-11-18: "first one look crap").** Lead with an action shot that fills the screen and has
  filled save slots (Thwaite), not the µCity title screen with empty "+" slots. Drop the DS test-pattern shot until a real DS
  homebrew is approved. Shoot book pose upright. Redo the iPhone and iPad first shots too.
- **Face buttons too close** (Gordon 2026-11-18): A, B and the small "+" between them are cramped in the default layout. Space
  them out, and check against thumb size on a real iPhone.
- Put the new sell copy in (docs/store/listing.md "NEXT COPY") and the promo text, which can go in now without a version.
- **Movable screen** (Gordon 2026-11-19: "could we maybe make the screen moveable too?"). In the controller editor, the game
  screen gets a handle like the buttons: drag to move it, pinch to resize it, per game and pose, saved with the layout
  (`SavedLayout` gains an optional screen frame, so old saves still load). Snap back to the default with Reset.
- Make Libbet's system label match: it's GBC on the shelf but "Game Boy" in the review notes.

## New systems (Gordon 2026-11-18: "lets add all including sony")
**1.1, quick wins on the ares engine we already vendor (ISC):** Master System, Game Gear, PC Engine (HuCard). Cartridge
games should need no firmware; confirm for each before building. Mainly layouts (laptop, book, flat), our own test ROMs and testing.

**Next big update, Sony:**
- **PS1:** PCSX-ReARMed (GPL-2.0-or-later) with its free HLE BIOS, never Sony firmware. Interpreter or no-JIT build.
  Needs a Fable licence review. Disc images: .cue/.bin and .chd from the user's own discs.
- **PSP:** PPSSPP (GPL-2.0-or-later), no-JIT build (it already runs on iOS without JIT). No firmware needed. Fable licence review.
  This is a system Delta doesn't have.

**Blocked: on the list but not buildable under the current rules:**
- **3DS:** speed needs JIT (no App Store JIT; our hard rule), and most games need console keys or system files from the
  player's own 3DS (firmware rule). Revisit only if Apple allows JIT or a no-key path appears.
- **Neo Geo:** needs SNK's BIOS (no free replacement); FinalBurn is non-commercial (banned). Only possible via player-imported BIOS.
- **Sega CD, Saturn, 32X:** need Sega BIOS files (32X boot ROMs too). Only possible via player-imported BIOS.
- **Dreamcast:** BIOS plus JIT for speed.
- **Player-imported BIOS** would unlock Neo Geo, Sega CD, Saturn and 32X, but it changes the no-firmware rule and adds App Review
  risk. Gordon's decision, not made. The recommendation is no for now.

## Later (no version set)
- **iPhone as controller** (Gordon, 2026-11-17: "add it to later roadmap maybe standalone"). Your iPhone becomes the gamepad
  over local Wi-Fi for Relics: Consoles running on an iPad, or on a future Mac version. It reuses the Wi-Fi play networking
  from the multiplayer work. It might be a separate companion app rather than a mode inside Consoles; that's undecided.
  Keep it local-network only, with no internet traffic, so the app stays offline (China ICP rule). Nothing to build yet.
- Relics: Consoles on Mac.
- v3 on Apple TV.
- GameCube (see `docs/gamecube-wii-feasibility.md`).
