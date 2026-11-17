# App Review notes: Relics: Games 1.0

Paste the block below into App Store Connect › App Review Information › Notes. No sign-in is needed (the app has no
accounts), so leave the demo account fields empty.

---

Relics: Games is a game emulator (guideline 4.7) for game files the user already owns. It plays NES, SNES, Game Boy,
Game Boy Color, Game Boy Advance, Mega Drive, Nintendo DS and Nintendo 64 game files.

How games get in: the user imports their own files through the Files picker ("Add games" on the shelf), "Open in" from
another app, or by copying them into the app's folder in Files. The app never downloads games, has no store, catalogue,
links or search for games, and makes no network connections at all.

Nothing commercial is included: no game files (ROMs) and no console BIOS or firmware. Systems that normally need a BIOS
use free replacements or high-level emulation written by the emulator authors (no console maker's code).

Five free homebrew games are bundled so the shelf isn't empty. Each is the author's own unmodified release, shared
under an open licence, and credited in the app under About › Free demos:
- µCity 1.3 by Antonio Niño Díaz (Game Boy Color) - GPL-3.0-or-later, graphics and music CC BY-SA 4.0
- Libbet and the Magic Floor 0.08 by Damian Yerrick (Game Boy) - zlib licence
- Thwaite 0.03 by Damian Yerrick (NES) - GPL-3.0-or-later
- Concentration Room 0.02 by Damian Yerrick (NES) - GPL-3.0-or-later
- Alex vs Bus: The Race, version pre3 by M374LX (Mega Drive) - GPL-3.0-or-later, assets CC BY-SA 4.0

No network: no accounts, ads, analytics, tracking, in-app purchases or web views. Privacy: no data collected.

Open source: the app is licensed under the GNU GPL version 3 or later (it uses GPL emulator cores). Source code:
https://github.com/gogs1998/relics-games (tag v1.0-build9 is this build). Every component's licence is listed in the app under About.

How to test:
1. Open the app. The shelf shows the five free demos.
2. Tap a demo (for example "Thwaite" or "µCity") to play it. On iPhone Duo in laptop or book pose, tap once to select
   and again to play.
3. The on-screen controller plays the game. The ••• menu key opens the pause menu with save states,
   rewind, fast-forward, screen styles, "Edit controls" and Quit.
4. Optional: to import, tap "Add games" on the shelf and pick any game file from Files.

iPhone Duo: laptop pose puts the game on the upright half and the controller on the flat half; book pose splits them
across the pages; closing the device pauses and saves. Ordinary iPhones and iPads get portrait and landscape layouts.

---

Notes for us (not for ASC):
- If N64 is dropped from 1.0 (only ships if Gordon's own games pass on TestFlight), delete "and Nintendo 64" above.
- Thwaite flickers its explosions on purpose; the seizure warning is in its credits (About › Free demos).
