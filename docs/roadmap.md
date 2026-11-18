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
- **Store screenshots reshoot (Gordon 2026-11-18: "first one look crap").** Lead with an action shot that fills the screen and has
  filled save slots (Thwaite), not the µCity title screen with empty "+" slots. Drop the DS test-pattern shot until a real DS
  homebrew is approved. Shoot book pose upright. Redo the iPhone and iPad first shots too.
- **Face buttons too close** (Gordon 2026-11-18): A, B and the small "+" between them are cramped in the default layout. Space
  them out, and check against thumb size on a real iPhone.
- Put the new sell copy in (docs/store/listing.md "NEXT COPY") and the promo text, which can go in now without a version.
- Make Libbet's system label match: it's GBC on the shelf but "Game Boy" in the review notes.

## Later (no version set)
- **iPhone as controller** (Gordon, 2026-11-17: "add it to later roadmap maybe standalone"). Your iPhone becomes the gamepad
  over local Wi-Fi for Relics: Consoles running on an iPad, or on a future Mac version. It reuses the Wi-Fi play networking
  from the multiplayer work. It might be a separate companion app rather than a mode inside Consoles; that's undecided.
  Keep it local-network only, with no internet traffic, so the app stays offline (China ICP rule). Nothing to build yet.
- Relics: Consoles on Mac.
- v3 on Apple TV.
- GameCube (see `docs/gamecube-wii-feasibility.md`).
