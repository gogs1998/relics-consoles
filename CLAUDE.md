# CLAUDE.md: Duo Emulator (working title "Foldback")

A Duo-first multi-system retro game emulator for the iPhone Duo, also for ordinary iPhone and iPad.
Players load games they own through the Files picker; nothing is downloaded. Freely licensed homebrew demos may be bundled (`docs/homebrew-candidates.md`). Read
`HANDOFF.md` (state, what's verified, decisions pending), `docs/design.md` (approved design, with the
Fable review changes in §10) and `docs/research.md` (App Store 4.7, core licensing, wish lists) first.

## Hard rules
- **Never** download, bundle, generate or point to commercial ROMs or BIOS files. Test only with our
  own ROMs (`TestROMs/`, built by our own assemblers). Third-party test suites, homebrew and emulator
  cores need Gordon's approval first (lists in `docs/research.md` §6 and `HANDOFF.md`).
- **Licence (Gordon, 11 Nov 2026): the app is going GPLv3 open source** so GPL cores can be used, like Delta
  ("easy way, we're not reinventing the wheel"). Every component must be GPLv3-compatible. **Still banned:**
  non-commercial / no-derivatives licences (Snes9x, Genesis Plus GX, FinalBurn's NC parts, DuckStation's newer
  CC BY-NC-ND releases) and anything unlicensed. Public source repo is approved but create it only when a
  build is about to ship publicly (ask Gordon once more at that point). Each new core gets a Fable licence review.
  NES and GB/GBC cores are ours; GBA is mGBA
  (MPL-2.0, vendored unmodified in `Packages/CoreKit/Sources/MGBA/mgba`, any change must go in
  `ThirdParty/mgba/patches/` and be published); SNES and Mega Drive are ares (ISC, vendored unmodified in
  `Sources/ARES/ares`, our stand-ins in `glue/shim`); DS is melonDS (GPL-3.0, vendored unmodified in
  `Sources/MELONDS/melonds`, shims/stubs/build units in `glue`, patches would go in `ThirdParty/melonds/patches/`). Licence texts: `Licenses/` (repo) and
  `App/Resources/Licences/` (shown in About). Keep both in sync when a component is added.
- **Core plan:** N64 (mupen64plus + GLideN64 + rsp-hle) and DS (melonDS, own FreeBIOS) first, then PS1
  (PCSX-ReARMed, HLE BIOS), PSP (PPSSPP, no JIT), then small systems (Mednafen, Stella). GameCube/Wii is a
  post-v1 goal (`docs/gamecube-wii-feasibility.md`). Upstream sources are cloned into `ThirdParty-src/` (gitignored).
  Systems needing a BIOS must use an HLE/free replacement; never ship or point to Nintendo/Sony firmware.
- No JIT, ever (no sljit/recompilers). No firmware: SNES DSP-n/ST01x/Cx4 games are refused; the SPC700
  boot program is our own (`kBootProgram` in `ares_glue.cpp`, rewritten from the protocol after a review).
- No console logos, trade dress, silhouettes, console colour schemes or real system fonts. No console
  brand in the app name. Systems are named in plain text only ("NES", "Game Boy Color").
- No in-app game downloads (keeps us out of guideline 4.7.1-4.7.5). No network, ads, analytics, accounts.
- Test ROM headers for GB must leave $0104-$0133 zero (no boot logo). No boot ROMs.
- Branch on pose and fold geometry, never the hinge angle. No `PoseDetector`: a horizontal fold is always
  the laptop (table) layout. Nothing may require folding.

## Toolchain
- Xcode 27.1, iOS 27.1 SDK, deployment iOS 26.0, Swift 6 strict concurrency, SwiftUI, Metal.
- XcodeGen: `project.yml`. Never hand-edit `DuoEmulator.xcodeproj` (gitignored): `xcodegen generate`.
- DuoKit `github.com/gogs1998/iqlabs-duokit` from 0.1.2 (don't fork; gaps go in `docs/DUOKIT-GAPS.md`).
- CoreKit: local package `Packages/CoreKit` (targets CoreKit, NESCore, GBCore, MGBA + GBACore, ARES + AresCore,
  MELONDS + DSCore;
  Swift cores build `-Ounchecked -enforce-exclusivity=unchecked`, C/C++ at -O2, even in Debug).
  ares keeps one console in process globals: one SNES/MD core per process (EmulatorSession's `coreGate`).
  Tests run on the Mac:
  `cd Packages/CoreKit && swift test --scratch-path ../../build/corekit`
- Test ROMs: `python3 Tools/build_test_roms.py` (NES, own 6502 assembler `Tools/asm6502.py`, art in
  `Tools/chrart.py`), `python3 Tools/build_gb_roms.py` (GB, `Tools/asm_sm83.py`), `Tools/build_gba_roms.py`,
  `Tools/build_ares_roms.py` (SNES + MD, hand-assembled), `Tools/build_ds_roms.py` (DS cart: ARM9 + ARM7 code via the
  ARM encoder in `build_gba_roms.py`, logo area zero).
- Accuracy suites (approved, gitignored, never bundled) in `TestSuites/`; harness and how to run: `docs/accuracy.md`.
- Our test-ROM outputs in `TestROMs/build/` are committed. A Debug-only build phase copies them into the app as `TestCarts/`;
  Release strips them and fails the build if any ROM file is in the bundle.
- Signing: `Local.xcconfig` (gitignored, copied from talking-computers-night) has `DEVELOPMENT_TEAM = 36UUUS8G8L`.
  Bundle id `com.iqlabs.duoemulator`; App Store Connect record "Foldback" (app id 6833521756, internal group
  "Team"). Upload only with Gordon's go-ahead: `xcodegen generate` first, then
  `~/duo-remote/Tools/upload.sh /Users/gordonshepherd/duo-emulator DuoEmulator /private/tmp/<outdir>`; delete the outdir after.
  Never submit for review.
- Build: `Tools/build.sh` (checks >= 4 GB free, takes the shared PID-file lock `/private/tmp/duo-build.lock`,
  DerivedData in `build/`). Release check: `Tools/build.sh -configuration Release -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO`.
- After any simulator run, `xcrun simctl terminate <udid> com.iqlabs.duoemulator` so no game audio keeps playing.
  Prefer headless core tests.
- Simulators: at most 2 booted Mac-wide; use your own, log it in `/private/tmp/claude-501/shared/SIMS.txt`,
  shut down and erase when done. Never touch D8C4096C. Duo layouts: DuoKit's DEBUG `-pose table|book|flat`
  on an ordinary iPhone simulator; **book pose must be shot in landscape** (rotate the simulator).

## Architecture
- `Packages/CoreKit/Sources/CoreKit`: `EmulatorCore` protocol (runFrame, framebuffer BGRA, drainAudio,
  batteryRAM, save/load state), `SystemID`, `InputState`, `CoreFactory.detect`, `AudioRing` (lock-free SPSC),
  `Decimator` (per-clock audio → 48 kHz with DC blockers and low-pass), `StateCoder` (one `sync` function
  serialises both ways, section tags), `StateContainer` (file wrapper: magic, versions, system, ROM CRC).
- `NESCore`: `NESSystem` (6502 where every bus access ticks PPU x3 + APU, so dummy reads give real timing;
  common unofficial opcodes), `PPU` (dot-based, loopy registers, sprite eval at 257, sprite-0 hit),
  `APU` (2 pulse, triangle, noise, DMC, frame counter, non-linear mixer), `Cartridge` (iNES/NES 2.0,
  bank tables) + mappers 0, 1, 2, 3, 4, 7. Palette generated from a YIQ model (ours).
- `GBCore` (helper-built, Fable-reviewed): `GBSystem` (SM83, timer, DMA/HDMA, double speed), `PPU`, `APU`,
  `Cartridge` (MBC1/2/3/5).
- Multi-screen systems: `EmulatorCore.screens` (`ScreenRegion`s inside the framebuffer, `isTouch`) and
  `setTouch(TouchPoint?)`, both defaulted for one-screen cores. `DSCore`: `DSSystem` over `Sources/MELONDS/glue`
  (C API `MelonDSGlue.h`; melonDS Platform hooks with no file/network access; FreeBIOS + generated firmware +
  direct boot; interpreter, JIT never compiled; software renderer, 3D threaded). Framebuffer 256x384 (top
  screen over touch screen); mono 48 kHz from melonDS's own resampler (the Decimator only downsamples);
  savestates are melonDS's (~4.5 MB); battery = cartridge save memory (nil until the game writes it).
  DSi mode, Wi-Fi networking, OpenGL, GDB stub are not vendored (`ThirdParty/melonds/README.md`).
- App (`App/`): `RootView` (DuoStageReader → Library or Player), `GameStore` (Documents/Games|Saves|States,
  `.library.json`, Inbox scan, import with header detection), `EmulatorSession` (dedicated thread owns the
  core, built on that thread; commands via Mutex; self-paced with ±0.5 % dynamic rate control from the audio
  ring; fast-forward x3; rewind ring of states every 4 frames capped at 8 MB), `FrameExchange` (lock + latest
  frame), `GameScreen`/`Renderer` (MTKView, one quad, `Shaders.metal`: sharp-bilinear, nearest, scanlines, LCD;
  `ScreenFit` picks integer scaling in device pixels when it fills ≥ 85 %), `AudioOutput` (AVAudioSourceNode
  built in a `nonisolated static` helper), `GamepadHub` (GCController + GCKeyboard), `ControllerModel` +
  `TouchSurface` (UIKit multi-touch, per-touch ownership) + `ControllerView` (the Graphite and Ember
  controller drawing), `PlayerView` (table / book / portrait / landscape arrangements; DS ones in
  `DSPlayerView`: `GameScreen(crop:)` per screen, `DSTouchPad` only on the touch screen's rect →
  `InputLatch.stylus`; DS table controls in areas `dsTableLeft/Right/Below` around the touch screen,
  defaults in `DSLayouts.swift`), `PlayerMenu`,
  `LibraryView` (+ `GameCard`, generated labels).

## DEBUG launch arguments
`-pose table|book|flat`, `-autoplay demo.nes` (a bundled test cart by file name), `-holdInput right,a`,
`-holdStylus 128,96` (DS stylus held at that touch-screen pixel),
`-openMenu YES`, `-freshStart YES` (ignore the auto-save), `-resetLayouts YES` (built-in touch layouts),
`-keepTouchControls YES` (the simulator may expose a virtual "Gamepad", which hides the touch controller),
`-fakeController YES` (pretend a pad is connected).
- Controls: `ControllerLayout` (presets: standard, 6-Button Arcade), `LayoutStore` (game → system → preset),
  `LayoutEditor` + `LayoutEditorArea` + `LayoutEditorPanel`; `GamepadHub` (GameController + keyboard, players,
  hotkeys via CoreKit `InputMapper`, remap capture), `ControllersSheet`, `ControllerCompanion`.

## Review policy (Gordon, 11 Nov 2026: "keep fable use, be wary about cost though")
- One tightly briefed Fable review per meaningful batch of work: give it the diff and the risks, not the repo.
- Always review third-party code, licences and anything firmware/ROM-adjacent. Skip trivial changes.
- Re-check only after a serious must-fix.

## Conventions
- Dynamic Type text styles only (`Font.rounded(_:weight:)`), never fixed point sizes for text.
- Zero warnings (the `appintentsmetadataprocessor` "Metadata extraction skipped" line is a tool message).
- VoiceOver labels on every control.
- Say what is simulator-only. Audio, haptics, controllers and real Duo poses need Gordon's device check.
- Commits: `git -c user.name="Gordon Shepherd" -c user.email=gordon@iqlabs.app commit`, ending with
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Don't push; no GitHub repo yet.
