**RENAMED 2026-11-17: Relics: Consoles** (home screen "Relics Consoles"); the "Relics: Games" name goes to the mini-games app. Icon C (ember
clamshell, docs/icon). Repo renamed to github.com/gogs1998/relics-consoles (old URL redirects); pages at iqlabs-apps consoles/ (games/
redirects for now; mini-games may reclaim games/ later). Build 10 = rename + icon + source link back in About + iPad landscape 74%;
NOT BUILT yet (disk < 4 GB). iPad 13" shots in docs/store/shots/ipad13. iPad sim DCDA709F is shut down; delete when done.

**PUBLIC since 2026-11-17 (Gordon: "public"): https://github.com/gogs1998/relics-games**, GitHub detects GPL-3.0, tag v1.0-build9 = the 1.0 binary.
To publish later commits: clone main to a scratch dir, drop origin, run `git filter-branch` with an env-filter setting author and committer
email to gordon@iqlabs.app, plus a tree-filter replacing Gordon's personal address in CLAUDE.md. Delete refs/original, add the GitHub
origin and check `merge-base --is-ancestor origin/main main`. The rewrite is deterministic, so it fast-forwards. Push main (never force).
Never put the personal address in a tracked file other than CLAUDE.md.

**Submitted? (2026-11-17)** Gordon said "submit" for build 9; the DUO coordinator does the submission in ASC.
**Fable pre-submit (2026-11-17): "source on request" fails GPLv3 §6(d) for App Store downloads; fix = public repo before SALE (Gordon deciding:
manual release + public on release day, or drop DS/N64). Public copy is pre-built, not pushed: scratchpad public-copy, emails rewritten to
gordon@iqlabs.app in authors AND CLAUDE.md history, tag v1.0-build9. Also: Libbet is GBC on the shelf but "Game Boy" in review notes; align.**
**First update (1.1) list, agreed with Gordon:** two-phone multiplayer; DS GPU renderer; original controller skins (own colours and
materials, never console trade dress; skin import later); tidy the controller-connected panel (empty save slots read as broken, hotkeys
behind "?"); portrait screen bezel should hug the picture (N64 wastes ~1 cm of glass, PlayerView.portraitLayout screenH).

**Build 9 (2026-11-17), the submit candidate, replacing 8:** Gordon chose to keep `gogs1998/relics-games` private "until someone asks".
Build 9 removes the dead GitHub links (About, demo credits) for "source available on request from gordon@iqlabs.app"; the store
listing and review notes were changed to match. If anyone asks for source: make the repo public (author email rewritten first).

# HANDOFF: Relics: Games (repo "duo-emulator", ASC record "Foldback")

## Ready to submit: what's left for Gordon (14 Nov 2026, v1.0 build 7)
Nothing has been sent to App Review and the public repo does not exist yet. In order:
1. **Contact email (ship-blocker).** Send the address. It goes in ONE place: `AppLinks.contactEmail` in
   `App/Library/AboutView.swift` (now `CONTACT_EMAIL_TBD`). **Done: gordon@iqlabs.app, build 8 uploaded 2026-11-15.** Build 7 carried the placeholder, so a new build (8) was
   needed after the change: Fable ruled a placeholder in the binary a 2.1 rejection. Also used on the support and privacy pages.
2. ~~DuoKit licence~~ **Done 2026-11-14:** Gordon keeps `iqlabs-duokit` private; DuoKit 0.1.2 is vendored at
   `Packages/DuoKit` and licensed GPL-3.0-or-later as part of this app (he owns it, so his other apps are unaffected).
   It goes public only inside the relics-games repo. Upstream changes: make them in iqlabs-duokit, copy back.
3. **Create the public repo `gogs1998/relics-games`** (default branch `main`, the credits link `/tree/main/release-sources`),
   push this repo, tag the submitted build's commit (e.g. `v1.0-build8`), check it loads logged out. Before pushing,
   check the history for anything that must not be public (`Local.xcconfig` and `TestSuites/` are gitignored;
   `ThirdParty-src/` too). It must be public **before** pressing Submit (Fable).
4. **Support URL and privacy-policy URL** (ASC won't submit without them): pages in the Relics pattern; copy in
   `docs/store/privacy-and-age-rating.md`.
5. **ASC:** price £3.99; paste the copy from `docs/store/listing.md` (name, subtitle, promo, description, keywords) and
   the review notes from `docs/store/review-notes.md`; App Privacy = Data Not Collected; age rating questionnaire as in
   `docs/store/privacy-and-age-rating.md` (expect 4+, accept 9+).
6. **Screenshots:** upload `docs/store/shots/` (Duo inner, Duo outer, iPhone 6.9"); also in side-session-notes duo-shots/games/.
7. **N64 decision:** the copy lists Nintendo 64. If Gordon's own N64 games didn't pass on TestFlight, delete the N64
   lines in the listing/review notes AND remove the N64 core, mupen64plus.ini, MoltenVK and the N64 About rows from the
   build (a dormant core is a 2.3.1 problem).
8. **Gordon's OK to submit.** Nobody submits without it.

## Update, 14 Nov 2026 (release prep, build 7)
Commits 5becb5b, 4c06a58, 97d7671, eed8236, 7e8a6dd (+ the build-7 HANDOFF commit):
- **Hidden N64 speed test removed** (About long-press, `N64SpeedTestView`, `N64SpeedTest`, bench ROM resource, its
  allowlist entry: the Release ROM check is back to exactly the five demos). The bench runner and ROM moved to
  `Spikes/N64RDP/` so the Mac CLI bench still builds; `Tools/build_n64_bench_rom.py` now writes there.
- **Version 1.0 (7)** in `project.yml`.
- **Licences:** cereal's BSD-3 text made verbatim from cereal `a56bad8` (the revision MoltenVK v1.4.2 pins; the old
  disclaimer named the authors). `release-sources/` holds the exact upstream source archives of µCity 1.3, Thwaite 0.03,
  Alex vs Bus pre3 and MoltenVK v1.4.2 with SHA-256s; the three shipped demo ROMs match the authors' releases byte for
  byte. Alex vs Bus credits from its `docs/Authors.md` added (fonts Telegrama/YoWorks, Press Start 2P/codeman38);
  µCity's readme lists no third-party assets. Thwaite's source URL fixed (`pineight.com/nes/thwaite-0.03.zip`).
- **About:** "Source code" row (github.com/gogs1998/relics-games) and "Contact" row from `AppLinks.contactEmail`
  (placeholder `CONTACT_EMAIL_TBD`, one constant). DuoKit credited as our own.
- **Privacy manifest:** SystemBootTime 35F9.1 added (frame pacing uses mach_absolute_time / CACurrentMediaTime).
- **Store docs:** `docs/store/listing.md`, `review-notes.md`, `privacy-and-age-rating.md`, `compose.swift`
  (screenshot composer, exact sizes, Graphite/Ember).
- **CoreKit tests:** 104 pass (Mac). Simulator Debug build: zero warnings.
- **Fable review (one pass):** must-fixes = placeholder email in the binary, repo must be public before Submit,
  DuoKit needs a licence + public repo, support/privacy URLs; all are in "Ready to submit" above. Shoulds applied:
  promo no longer says "Made for iPhone" (MFi wording) -> "Built around iPhone Duo", "GPL version 3 or later",
  Nintendo/Sega non-affiliation line in the listing, keyword `arcade` -> `pixel`, "version pre3" in the notes,
  MoltenVK source mirrored, privacy reason added. Rulings: system names in description OK (not in name/subtitle/
  keywords/captions); DS test-cart picture in a screenshot OK if not captioned as an included game; mupen64plus.ini
  low risk; 4+ defensible, accept 9+.

**Right-side status bar.** Simulator only; Gordon has no Duo, and nothing was checked on a real one.
- **Fix (Gordon's rule, 14 Nov):** the player no longer hides the status bar on an iPhone Duo. It was
  `.statusBarHidden(true)`, which leaves a black band on the right of a real Duo. The bar is now hidden only on
  ordinary iPhones: `UIDevice` idiom is phone AND `!PlayerView.isDuo(stage)`, where isDuo means a real division region
  that DuoKit isn't simulating, or the hinge reports closed. This is the same rule as Phones. DSPlayerView has no
  `statusBarHidden` of its own. `persistentSystemOverlays(.hidden)` stays: it hides the home indicator only.
- **Layout:** every layout is placed with absolute rects inside the `DuoStageReader` GeometryReader, which respects the
  safe area. That covers the shelf, every player pose, DS, the N64 deck, the table tray, book, landscape, the editor and
  the menus. No content uses `ignoresSafeArea` (only the background and the sleep veil do), `UIScreen` or global
  coordinates. A trailing inset therefore shrinks the stage rather than covering controls.
- **Checked** on the shared iPhone 17e with the new DEBUG `-fakeTrailingInset 54`, which draws a red band in the trailing
  safe area. Everything stops at the band in table, flat, book and landscape: the N64 C buttons, the C stick, A/B/Z and
  the R tab; the DS X/A, R and touch screen; the NES quick-slot tray; the shelf's "Add games" button.
- **Not checked:** the real Duo simulator. 3 simulators were already booted against a limit of 2, the only booted Duo
  sim belongs to Relics and is off-limits, and the disk was under 4 GB. I created "Games Duo" (7C3DCA79) but never
  booted it. Not yet confirmed: that a Duo reports the right-edge bar as a trailing safe-area inset, including on the
  outer display. When a slot frees up, run `-forceFold YES -logStage YES` on Games Duo; it logs the real insets.

**Screenshots** are composed by `docs/store/compose.swift` from iPhone 17e simulator captures of the bundled demos.
The Duo **inner** shots were retaken 2026-11-17 on the real iPhone Duo simulator (Relics Duo BD9038FF, unfolded, `--display=LCD-1`, `-forceFold YES`; the 84 pt right-edge status bar is clear of everything). The **outer** shots are still the earlier 17e-based ones: the outer display only lights when the sim is folded, which only Gordon can do.
- **Duo inner, 2007x2853:** `docs/store/shots/duo-inner/` holds 6 shots: table µCity, table Thwaite with the quick-slot
  thumbnails, table DS (our own test cart; the caption doesn't claim a game), book Alex vs Bus, flat Libbet, and the
  shelf in table pose.
- **Duo outer, 1398x2034:** `docs/store/shots/duo-outer/` holds 3 shots: the shelf, "Close it to pause and save" (the
  sleep veil), and Settings. A closed Duo shows the sleep veil over a game, so no outer shot shows live play.
- **iPhone 6.9", 1320x2868:** `docs/store/shots/iphone69/` holds 5 shots: µCity, Thwaite, landscape Alex vs Bus, the
  layout editor, and the shelf with only the 5 demos.
- **Copies** of the Duo shots are in side-session-notes `duo-shots/games/inner` and `duo-shots/games/outer`.

**TestFlight build 7: NOT uploaded yet.** The disk sat at 3.7 to 3.9 GB for 40 minutes, and the rule is not to archive
below 4 GB. Everything for build 7 is committed. To upload: `cd ~/duo-emulator && xcodegen generate && rm -rf build &&
~/duo-remote/Tools/upload.sh /Users/gordonshepherd/duo-emulator DuoEmulator /private/tmp/relics-b7`, then
`rm -rf /private/tmp/relics-b7`.

**Tests:** app unit tests 33 pass (Shared iPhone 17e). CoreKit 104 pass. Release device check: zero warnings (only the
appintentsmetadataprocessor tool line), ROM allowlist passes with exactly the five demos.

---

## Update, 13 Nov 2026 (build 6: big N64 deck, C stick option, bigger C buttons)
**Build 6 uploaded to TestFlight** (internal only, archive CFBundleVersion 6; never submitted for review).
Gordon asked "did n64 not have 2 sticks" after trying build 5, then sent a rival's portrait layout he likes.
- **New N64 deck** (portrait and Duo table, `N64Layout.deck`): the layout ideas only, in our own Graphite/Ember (no console
  colours). L and R are wide tabs in the top corners, with rewind / menu / fast-forward small between them. The stick is
  top left (about 36 % of the width) with the D-pad, as big, under it. **A, B and Z are three big ember face buttons**
  (Z top, B left, A lower right; Z is no longer a shoulder on the deck, though book and landscape keep it as one). The
  C buttons are a tight diamond bottom right (`cCluster(spread: 0.75)`, about 60 pt each on a phone). Start is small in
  the middle. No vent slots on the N64 deck.
- **C stick option:** `Control.Kind.cStick`, a digital second stick for C up/down/left/right (`CStickMath` in
  `TouchSurface.swift`): engages at 40 % of the radius and lets go inside 30 %; eight 45-degree sectors, so diagonals
  press two C buttons; a held direction keeps 8 extra degrees; lifting the thumb releases it and the knob springs
  back. It is drawn in sand with four arrows (`CStickView`), VoiceOver "C stick". Every N64 layout carries both the
  cluster and the stick in the same place, and `N64Layout.camera(_:cStick:)` shows one of them. Old saved layouts get a
  stick made over their cluster (`withCStick`). The editor keeps both, so moving one never loses the other's place;
  the hidden one is just not drawn.
- **The choice:** `LayoutOptions.cStick` in `LayoutStore` (`<system>-options[-game].json`, game, then system, then
  default **C buttons**). The switch is in the layout editor: **pause menu › Edit controls ›** (no control selected)
  **Camera: C buttons / C stick › Done**. The editor's scope chip (This game / All games) decides where it's saved.
  DEBUG `-n64CStick YES|NO` forces it.
- **C button sizes** (old → new): portrait phone deck 39 → 60 pt; Duo table guesses 384x270 37.5 → 45, 330x250
  33.7 → 41 (the only deck under 44); landscape 852-wide 33.5 → 44, 667-wide (SE) 21 → 32 (the margin is ~103 pt);
  book right page 422x140 29.5 → 44, 260x120 24 → 39. Book and landscape fit the cluster with a small solver
  (`fitCluster` / `cameraControls`: from 44 pt down to the old size, nudged until nothing touches).
- **Saved layouts:** anyone with a saved N64 portrait/table layout from build 5 keeps it (Z still a shoulder there)
  until they tap Reset in the editor; new players get the new deck.
- **Tests:** app unit tests (33 pass) for the C-stick mapping (thresholds, hysteresis, diagonals, release), camera swap, old
  layouts, option resolution, sizes; N64 UI tests for the C stick in portrait/table/landscape/book and the editor
  switch. The C-stick UI tests don't assert the press: XCUITest kept reading a stale `debug.touchInput` after a drag
  on it, though the app's `everPressed` did hold C up + C right (checked by log and a mid-drag screenshot with both
  arrows lit). Release device check: zero warnings. **Simulator only** (Shared iPhone 17e; N64 shows through the VI fallback): shots `docs/shots/iphone-n64.png`,
  `iphone-n64-cstick.png`, `table-n64.png`, `table-n64-cstick.png`, `iphone-landscape-n64.png`,
  `iphone-landscape-n64-cstick.png`, `book-n64.png`, `book-n64-cstick.png`, `editor-n64-cstick.png`. **Needs
  Gordon's device:** how the C stick feels for the camera, whether 40 %/30 % is right, and thumb reach on the new deck.

---

## Update, 13 Nov 2026 (build 5: N64 unhidden, paraLLEl-RDP in normal play)
Gordon's decision: N64 ships in the first App Store release **if his own games work** through TestFlight. Build 5 is
for that test (internal TestFlight only, never App Review).
- **N64 in Release:** `N64_ENABLED`, the Release Info.plist UTType stripping and the "isn't available in this version
  yet" import path are gone. N64 is in the import error's system list, the empty shelf and About.
- **Renderer in play** (device only): paraLLEl-RDP on MoltenVK + cxd4, **asynchronous** RDP
  (`N64System(synchronousRDP: false)` in `EmulatorSession.makeCore`; flip to true if a game's framebuffer effects
  look wrong). 640 x 480 VI output → Metal (layout treats it as 320 x 240, 4:3). The frame boundary now waits for the
  RDP timeline, so save states never see in-flight GPU writes and no GPU work is submitted while asleep.
- **Pipeline cache:** `Application Support/N64 Renderer/vulkan-pipelines.bin` (backup-excluded), our header
  (`glue/include/N64PipelineCache.h`) + Vulkan header checked before use, any mismatch deletes it; a `.loading`
  sentinel discards a cache that crashed/hung the driver last time. Saved on pause (`EmulatorCore.prepareForSuspend`)
  and game close. No explicit pre-warm (paraLLEl compiles specialised pipelines async with an ubershader fallback).
- **Robustness:** `n64_renderer` / `N64System.renderer` (rdp / viUnavailable / viFailed); a device failure shows a
  notice over the game (`PlayerModel.notice`) instead of a black screen. Without the renderer the RDP stream is still
  consumed and SyncFull still raises the DP interrupt (games don't hang).
- **Rewind off for N64** (`EmulatorCore.supportsRewind`; 8 MB-RDRAM gzip states): the rewind keys show a toast.
  The auto-save load is deferred to wake if the app went to the background while a game was starting.
- **Tests:** CoreKit 104 pass (new: VI fallback status, pipeline-cache round trip + every-byte corruption/mismatch).
  Release device check zero warnings, ROM allowlist passes. **Simulator only:** Shared iPhone 17e, `-autoplay
  n64_demo.z64` shows our test cart through the VI fallback, no notice (expected there). **All real N64 rendering,
  the pipeline cache, sound and the stick feel are device-only and untested by us.**
- **Fable review:** 1 must-fix (state save/load not at an RDP-idle point in async mode: fixed by waiting for the
  timeline at every frame boundary) + shoulds applied (auto-resume while backgrounded, poison-cache sentinel, cache
  load try/catch + 16 MB cap, `g_h` cleared last in `n64_destroy`, fd leak, RDP partial command dropped on reset).
  Not done: the speed test still runs outside `coreGate` (hidden, TestFlight-only; goes with it).
- **Release prep MUST remove** the hidden N64 speed test (About › long-press the version line, `N64SpeedTestView`,
  `N64SpeedTest`, the bench ROM and its allowlist entry in `project.yml`). CLAUDE.md's N64 lines (VI-only video,
  "N64 hidden") are now stale and want updating.

---

## Update, 13 Nov 2026 (v1 feature batch: sleep, pose editor, table tray, RTC, mappers, zip, settings)
Goal: v1 App Store-ready at £3.99 (NES, GB/GBC, GBA, SNES, MD, DS; N64 hidden until v2). Commits b21c34f..b8f3d87.
- **Close-to-sleep (all systems):** `PlayerModel.sleep/wake(_:)` with reasons `.lidClosed` (DuoKit `stage.isClosed`,
  the hinge's closed posture, never the angle) and `.background` (willResignActive / didBecomeActive). Sleep releases
  touches, stops FF/rewind, pauses core + audio, writes the auto-state and battery under a background task
  (`BackgroundSave`); wake resumes the in-memory session only when no reason is left and no menu/editor/sheet is open.
  "Sleeping" veil while the lid is closed. DEBUG `-lidCycle 3,8` fakes a close/open.
- **Pose-aware editor:** `LayoutPose` (table/book/portrait/landscape → areas); header says "Duo table layout" etc.;
  "Copy from" another pose's saved layout through a shared unit space (`LayoutCopier`), real sizes when the file has the
  new optional `SavedLayout.areaSize`. Header wraps on narrow book pages. DEBUG `-editControls YES`.
- **Table pose bottom screen (one-screen systems):** `ControllerLayout.tableDeck` + `tableTray`: a recessed tray of
  three quick slots with thumbnails along the hinge (tap empty = save, tap full = load with **Undo** in the toast,
  hold = Save/Load menu), rewind/FF either side, L/R in the corners, menu key between Select and Start
  (`QuickSlotTray.swift`). Only users without a saved table layout see the new defaults.
- **GB fix 2 done:** MBC3 RTC follows the wall clock (pause/FF/rewind don't skew it), 48-byte VBA-M/BGB/mGBA footer
  (44-byte read), states get an optional trailing `RTCW` stamp (clock carts only; old states still load) so loading
  catches up real time.
- **NES mappers 9, 10, 11, 66, 69** (`NESCore/Cartridge.swift`) with our own probes (`TestROMs/nes/mappers.py` →
  `mmc2/mmc4/colordreams/gxrom/fme7_probe.nes`). FME-7's 5B sound chip is **not** emulated (Gimmick! etc. lose music).
- **Zip import:** `CoreKit/ZipArchive` (Apple Compression, raw DEFLATE; stored/deflate; CRC/size checked; streams to a
  temp file). One game per zip; none/several/Zip64/encrypted refused with a message. Picker accepts .zip; Inbox too.
  Not added as a CFBundleDocumentType (no "Open in" for zips yet). Import runs on the main thread (a big zip blocks UI briefly).
- **Settings** (shelf gear + pause menu): haptics, game volume, default screen filter (resets per-system picks),
  FF speed 2/3/4/8x, auto-save (off = no auto-state and the old one is deleted; battery saves always kept).
  `AppSettings.swift`, `SettingsView.swift`. DEBUG `-openSettings YES`.
- **Tests:** CoreKit 101 pass (new: RTC wall clock/state/footer/paused-time, 5 mapper probes + state determinism +
  FME-7 counter, zip). App unit tests 29 pass (copier, table tray clearance, zip import, settings). Release device
  build zero warnings. **Fable review:** 2 must-fixes (stale auto-state rolling back battery saves when auto-save is
  toggled; RTC losing paused time) + 7 shoulds, all applied in b8f3d87.
- **Simulator only** (Shared iPhone 17e, reused; 3 sims were booted): shots `docs/shots/table-sleep.png`,
  `editor-table-pose.png`, `editor-book-pose.png`, `book-nes.png`, `table-nes-quickslots.png`,
  `table-gba-quickslots.png`, `table-fme7-probe.png`, `iphone-settings.png`. **Needs Gordon's Duo/device:** real
  fold-to-sleep (does iOS report `.closed` before backgrounding?), haptics/volume/audio, tray reach under thumbs.

---

## Update, 13 Nov 2026 (N64 RDP spike: paraLLEl-RDP + MoltenVK + cxd4, throwaway)
- **Findings: `docs/n64-rdp-spike.md`.** M4 Mac mini, our own bench ROM (`Spikes/N64RDP/rom/`): busy load (2,000
  textured Z-buffered tris, 2x fill, our RSP microcode) **153 fps** synchronous, stress load (4,000 tris, 3x fill)
  **107 fps** (131 async); full speed is 60. CPU-bound (R4300 interpreter + cxd4), GPU 1.7 ms. iPhone estimate
  ~70-105 fps busy on A15-A18 Pro. Recommendation: **v2, provisionally**, pending Gordon's device run (doc §8:
  `Spikes/N64RDP/ios`, `xcodegen generate`, scheme N64Bench, Run on the plugged-in iPhone).
- Licences: paraLLEl-RDP/Granite/volk MIT, Vulkan-Headers + MoltenVK Apache-2.0 (GPLv3-only combination, fine),
  cxd4 CC0. Sources in `ThirdParty-src/` (gitignored). Not wired into the app: `n64_glue.c` hooks are
  `#ifdef N64_RDP_SPIKE` only; Release check passes with zero warnings.

---

## Update, 13 Nov 2026 (build 3 on TestFlight: N64 hidden, demo shelf)
- **Build 3 uploaded to TestFlight** (internal only; Gordon approved; NOT submitted for review). Archive checked:
  CFBundleVersion 3, no N64 document types in Info.plist, the five demos in `Demos/`.
- **N64 hidden in Release:** Swift flag `N64_ENABLED` (Debug only, `project.yml`) via `SystemID.isAvailableInThisBuild`
  (`GameStore.swift`): import refuses N64 with "…is a Nintendo 64 game. Nintendo 64 isn't available in this version
  yet.", the picker omits .z64/.n64/.v64, old N64 shelf records are hidden. The Release post-build script strips the
  N64 UTTypes from the built Info.plist (and fails if any remain). The mupen64plus code and `mupen64plus.ini` still
  ship in the binary (unreachable), so its licence rows stay in About.
- **Demo shelf:** `App/Resources/Demos/` (folder reference) = µCity 1.3 (`ucity.gbc`), Libbet 0.08 (`libbet.gb`),
  Thwaite 0.03 (`thwaite.nes`), Concentration Room 0.02 (`croom.nes`), Alex vs Bus pre3 (`alexvsbus-pre3.md`), all
  the authors' unmodified builds (GB logo / "SEGA" header bytes left as-is on Fable's ruling). `GameStore.seedDemos()`
  copies each into Games/<system>/ once (record `demo: true`, card says "· Free demo"); ids kept in
  `Documents/.seeded-demos.json` so a deleted demo never returns. Release ROM check now allows exactly these five
  files by path + SHA-256 (and requires all five); any other ROM fails the build. Credits/licences:
  `Licenses/demos-credits.txt`, `GPL-3.0.txt`, `CC-BY-SA-4.0.txt` (+ copies in `App/Resources/Licences/`), About has a
  "Free demos" row, a GPLv3 notice for the app and new wording ("includes a few free homebrew demos… no Nintendo or
  Sega system software"). Tobu Tobu Girl not included.
- **Verified:** CoreKit `swift test` 92 pass; Release device build zero warnings. **Simulator only** (Shared iPhone
  17e, reused because 2 sims were booted; app uninstalled after): the five demos appear (shelf 20 = 15 test carts + 5),
  Thwaite launches to its title screen, a removed demo is not re-seeded. Not tested: the demos on a device, audio.
- **Fable licence review: PASS WITH FIXES.** Nothing blocks internal TestFlight. Applied now: GPLv3 notice in About,
  "no Nintendo or Sega system software", CC BY-SA URIs in the credits, removed an unbacked "3-year offer on request"
  line. Rulings: melonDS/FreeBIOS fine; mupen64plus + CIC-6105 + ini low risk; ship logo/SEGA header bytes unmodified;
  everything GPLv3-compatible. **Must do before any external/public build:**
  1. Publish the app's source (incl. CoreKit, DuoKit under a GPL-compatible licence) and put the repo URL in About.
  2. Mirror the exact source archives of µCity v1.3, Thwaite 0.03 and Alex vs Bus pre3 in our public repo/releases
     (GPLv3 §6d) and cite that URL; add a contact email.
  3. Check µCity's and Alex vs Bus's upstream readmes for third-party asset credits to carry over (CC BY-SA).
  Should: ask Yerrick, Niño Díaz and M374LX for a written OK (App Store vs GPL/CC BY-SA DRM tension); consider
  dropping N64Core + `mupen64plus.ini` from Release (guideline 2.3.1 dormant features; ~3,000 commercial titles in
  the ini); list the demos in App Review notes; check the age rating.

---

## Update, 13 Nov 2026 (Nintendo 64: mupen64plus + rsp-hle, no RDP renderer yet)
- **Licence finding (blocker for the plan):** GLideN64 (`a04081a`) is **GPL-2.0-only**: its LICENSE says "licensed
  under the GNU General Public License version 2" with no "or later", and its core sources have no headers. That can't
  go into the GPLv3 app, so **GLideN64 is not vendored**. mupen64plus-core (`daae68e`) and rsp-hle (`4cdc305`) are
  GPL-2.0-or-later (every file's header), so they're fine; their bundled MiniZip/MD5 (zlib), xxHash and the
  CIC-6105 algorithm (BSD-2) are too. Details and the alternatives: `ThirdParty/mupen64/README.md`.
- **What plays:** the core runs any N64 ROM (CPU, RSP-HLE audio, saves, controllers), but the picture is our own **VI
  scan-out** of RDRAM: CPU-drawn framebuffers show (our test cart), **RDP graphics (all real 3D/2D games) don't**.
  A real renderer needs Gordon's decision + a download: paraLLEl-RDP (MIT) on MoltenVK (Apache-2.0) with cxd4's
  RSP interpreter for graphics tasks is the clean no-JIT option; or a relicence grant from GLideN64's authors.
- **Core:** vendored byte-identical (200 files) in `Packages/CoreKit/Sources/MUPEN64/`; no patches. Cached interpreter
  only, no recompiler file in the repo, HLE boot (no PIF ROM), no M64P_PARALLEL/OSD/netplay/debugger/libpng/SDL.
  Our glue: front end that parks the core's own loop at each vertical interrupt (frame stepping and synchronous
  save states at the same point), static plugin tables behind `osal_dynlib_getproc`, our video/audio/input plugins,
  an SDL stand-in header, osal/vidext/eventloop/screenshot stand-ins, build units for `main.c` and rsp-hle's
  `plugin.c` (renamed entry points). One N64 machine per process (`coreGate`).
- **Swift:** `N64Core.N64System` (320x240, 60/50 Hz, 48 kHz mono, 2 ports, analog via new
  `EmulatorCore.setAnalog`), `SystemID.n64`, `.z64/.n64/.v64` detection + byte-order normalisation, InputState
  `.z/.cUp/.cDown/.cLeft/.cRight`. Battery = "N64B" blob (EEPROM, SRAM, FlashRAM, Controller Pak files).
  **Controller Pak works and persists** (both pads have one; the test writes it, a fresh machine reads it back).
- **App:** import of N64 files (64 MB limit); N64 layouts for every area (portrait/table deck, book left/right,
  landscape margins) in `App/Controller/N64Layouts.swift`; new `.stick` control: true analog (no snapping),
  sensitivity (range), dead zone, optional outer full-tilt ring, optional re-centre-under-thumb, knob follows the
  thumb; settings in the layout editor's panel for N64 (and saved with the layout; old layout files still load).
  The landscape editor now keeps every control off the game rect (all systems). Physical pads: left stick =
  analog (radial dead zone 0.12), right stick = C buttons via new remappable `rightStick*` inputs, triggers = Z;
  keyboard X/Z/A = A/B/Z, IJKL = C. N64 rewind snapshots every 3 s (states are gzip files).
- **Verified on the Mac (`swift test`, 92 pass):** boots `n64_demo.z64` (ours, `Tools/build_n64_roms.py`) with HLE
  boot; non-black frame; A/B/Z/C/L/R/Start/D-pad and the analog stick reach the game; 400 Hz tone at 48 kHz
  (game rate 32 kHz); save state round trip deterministic (also via `StateContainer`; junk/truncated rejected,
  machine untouched); EEPROM + Controller Pak battery round trip; reset; one-machine rule. **Speed: ~390-430 fps**
  (6.5-7x real time) in release and debug (C is -O2 in both) for our light cart; save state 75 KB in ~15 ms.
- **Verified in the simulator** (Shared iPhone 17e, reused: 2-3 sims already booted): `N64UITests` (5) pass: touch
  stick reaches full right with no vertical drift, A reaches the latch, no control intersects the game in portrait,
  landscape and table; the editor shows the four stick settings. App unit tests incl. `N64LayoutTests`.
  Shots: `docs/shots/iphone-n64.png`, `iphone-landscape-n64.png`, `table-n64.png`, `book-n64.png`, `editor-n64.png`.
- **Fixed on the way (all systems):** `AudioOutput.resume()` could start an AVAudioEngine with no source node when the
  app became active before the core had started, which raises an Objective-C exception (one UI-test crash); it now
  waits for the graph.
- **Needs Gordon's device:** iPhone speed of the interpreter with a real game (unknown until a renderer exists),
  how the stick feels (sensitivity/dead-zone defaults are guesses), audio, a real controller's sticks.
- **Open:** the RDP renderer (above); the mandatory **Fable licence review** of mupen64plus/rsp-hle has not been run
  (flag `n64_cic_nus_6105.c` as the firmware-adjacent file); 64DD, Transfer Pak, Rumble Pak (the pad has a
  Controller Pak), VRU and per-game controller-pak/rumble choice are not exposed; 4-player is 2 ports.

---

## Update, 11 Nov 2026 (Nintendo DS: melonDS)
- **Core:** melonDS commit `497aa6c` (GPL-3.0; the app is GPLv3 now) vendored byte-identical in
  `Packages/CoreKit/Sources/MELONDS/melonds` (DS mode only; no frontend, DSi, network, OpenGL, JIT or GDB
  sources). Built as the interpreter only: `JIT_ENABLED` never defined and no JIT file in the repo. No patches:
  shims (`glue/shim`: non-JIT `ARMJIT*.h` via `unifdef`, `version.h`), DSi/SD-card stand-ins that abort if
  ever reached (`glue/src/melonds_stubs.cpp`), and three build units that compile `ARM.cpp`, `NDS.cpp`,
  `NDSCart.cpp` with `dynamic_cast` → `static_cast` (DSi-only downcasts). Details: `ThirdParty/melonds/README.md`.
- **No Nintendo files:** FreeBIOS (BSD-2-Clause, Gilead Kutnick 2013, the DraStic BIOS, "not derived from
  Nintendo's BIOS", source kept in `ThirdParty/melonds/freebios/`) + firmware generated in memory + direct boot.
  The glue's melonDS file hooks all return "not found".
- **Swift:** `DSCore.DSSystem`; protocol extended backwards-compatibly with `screens: [ScreenRegion]` and
  `setTouch(_:)` (defaults for every other core). Framebuffer 256x384 (top over touch screen). `SystemID.ds`,
  `.nds` + header (CRC-16) detection, import limit raised to 512 MB for DS (files are mapped, not read).
- **App:** DS layouts in `App/Player/DSPlayerView.swift`. Table: top screen on the top half; touch screen centred
  on the bottom half with controls in three new areas around it (`dsTableLeft/Right/Below`, so the editor can't
  drag anything over it). Book: one screen per page, controls under each. Portrait: stacked, deck below.
  Landscape: side by side, overlay controls in the margins (the stylus layer sits above them). Stylus input
  only on the touch screen's rect (`DSTouchPad` → `InputLatch.stylus`). `-holdStylus x,y` DEBUG argument.
- **Verified on the Mac (`swift test`, 83 tests pass, 7 DS):** boots our own `ds_demo.nds` (built by
  `Tools/build_ds_roms.py`) with no BIOS files; both screens render; keys, X/Y and the stylus reach the game;
  a 440 Hz PSG tone at 48 kHz; save-state round trip byte-identical (also via `StateContainer` and into a fresh
  core); junk/truncated states rejected with the machine untouched; EEPROM battery save round trip and reset.
  Speed of the interpreter on this Mac: **~570-590 fps in release** (~9.7x real time), ~540 in the debug test
  build. Our cart busy-loops both CPUs and draws no 3D, so real 3D games will be much slower.
- **Verified in the simulator** (Shared iPhone 17e, reused because two sims were booted): `DSUITests` (6)
  pass: the table-pose tap on the touch screen arrives with the right coordinates, no control intersects it,
  the layout editor moves a DS button and saves it; app unit tests incl. `DSLayoutTests` pass. Shots:
  `docs/shots/table-ds.png`, `table-ds-stylus.png` (stylus held + A: touch screen green, square red),
  `iphone-ds.png`, `iphone-landscape-ds.png`, `book-ds.png` (landscape).
- **Needs Gordon's device:** iPhone speed (interpreter, no JIT; 3D-heavy games may not hold 60 fps on the
  software renderer), audio quality, how the stylus feels and whether thumbs fit the narrow table-pose columns
  on a real Duo, rewind (DS states are ~4.5 MB: one every 60 frames, ~5 s reach).
- **Not done / open:** no commercial-style test (we can't download homebrew); DSi-enhanced games run in DS
  mode, DSi-only ones are refused; no microphone, Wi-Fi or local multiplayer; RTC set from the clock at boot only;
  the firmware's user name is melonDS's default; save type for unknown games is melonDS's guess (8 KB EEPROM)
  unless the game is in melonDS's ROM list; the mandatory **Fable licence review of this core has not been run**.

---

## Update, 11 Nov 2026 (phase 3: controls and controllers)
Build 1 (b97a765) went to TestFlight via the coordinator. Since then:
- **Research:** `docs/controls-research.md` (Delta, RetroArch, Provenance, Gamma, Folium, PPSSPP, Lemuroid,
  Android single-system apps, Manic EMU; praise/complaints; "How we beat them").
- **Layout editor** (pause menu › Edit controls): drag, pinch or slider to resize, per-control opacity,
  haptic strength, auto-fire and show/hide; snap to an 8 pt grid; presets; scope "All games" or "This game";
  reset; import/export a `.foldlayout` JSON file; Done saves, Cancel discards everything (reset and import
  included). Layouts are per system and per area (Duo table, portrait, book left page, book right page,
  landscape), optionally per game; stored in Application Support/Layouts. Controls are clamped to their
  area, so nothing can cover the game in table pose. Layout-wide: diagonal width (Off/Narrow/Normal/Wide),
  auto-fire rate (5-30/s), overall haptics. VoiceOver can move/resize with actions.
- **6-Button Arcade preset** (SNES: Y X L over B A R; Mega Drive: X Y Z over A B C), two arched, staggered
  rows plus a "x3" zone per row (hideable). Two-button systems get an A+B zone between the buttons.
- **Physical controllers:** hot-plug toast; the touch controller hides while a pad plays ("Keep touch controls
  visible" in Controllers); Duo table pose shows a companion on the bottom screen (save slots, rewind / fast-
  forward, menu, hotkey list): chosen over stretching the game across both halves because the hinge would cut
  the picture. Book: game takes the whole left page, companion on the right (the hinge never crosses the
  picture; full-canvas would). Portrait: bigger screen + compact companion. Landscape iPhone/iPad: edge-to-edge,
  integer-scaled when the screen mode is Auto, with a small corner menu key.
- **Mapping** (pause menu › Controllers): per-system controller and keyboard remapping (press-to-assign),
  hotkey combos (defaults: Home or Options+Menu = menu, Options+L1/R1 = load/save slot 1, Options+L2/R2 or
  L2/R2 alone = rewind/fast-forward), left stick as D-pad with a dead-zone slider, player assignment for a
  second pad on NES / SNES / Mega Drive (cores now have a second port), rumble on save/load where supported.
  A modifier that is also a button (Options = Select) waits 180 ms so combos never leak a Select press; a quick
  tap still sends Select.
- **Tests:** CoreKit 76 (incl. mapping engine and player-2), app unit 15 (layouts, store, import clamping,
  D-pad maths, controller path driven without hardware), UI 23 (editor drag-and-persist, arcade presets,
  controllers screen, controller layouts via `-fakeController YES`). All pass in the simulator.
- **Needs Gordon's device test:** a real Bluetooth / MFi pad (the simulator can't pair one: everything pad-side
  is unit-tested or faked), whether iOS passes the Home button to the app, controller rumble, touch haptics
  strength, thumb reach of the default and arcade layouts on the Duo.
- **Fable review:** PASS WITH FIXES, all 6 applied (settings/frames clamped on load and import; second pad
  gets player 2 at launch; landscape menu key + Options+Menu combo; no Select leak; Cancel really cancels and
  per-control hide makes the multi-press zones optional; keyboard/pad disconnect clears held keys and capture).

---

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
  is done (13 Nov 2026 batch). Per-pixel
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
