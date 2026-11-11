# Duo Emulator: design

Status: **approved with changes by the Fable design review, 11 Nov 2026** (changes folded in; see §10). Working title **Foldback** (placeholder, no console brand; Gordon picks the
real name). Bundle id `com.iqlabs.duoemulator` (placeholder, not registered).

Read `docs/research.md` first: it sets the legal frame (guideline 4.7, 5.2.1, 4.1) and the licensing verdicts this
design relies on.

## 0. Principles

1. **Duo-first, never Duo-only.** The two halves of the iPhone Duo are the reason this app exists: game up top,
   a real controller below, like a handheld. Everything still works on an ordinary iPhone and iPad, and nothing
   requires folding. Layout branches on `DuoStage.pose` and the fold geometry, never on the hinge angle.
2. **The player's own files only.** No bundled, linked, generated or suggested commercial ROMs or BIOS. No
   in-app game downloads in v1 (that keeps us outside 4.7.1-4.7.5 entirely). Import through the Files picker,
   "Open in" and AirDrop.
3. **No trade dress.** No console logos, silhouettes, colour schemes that echo a console (no four-colour diamond,
   no grey-and-purple, no "dot matrix" bezel text), no real system fonts. Systems are named in plain text
   ("NES", "Game Boy Color") in the library's section headers and the import sheet, as Delta does, with a
   non-affiliation line in Settings > About. The controller is our own industrial design.
4. **Tactile, beautiful, simple.** The controller should feel like a well-made object: depth, light, travel,
   haptics, sound-off by default. The library should feel like a shelf, not a file browser.
5. **Honest emulation.** In-house cores where licensing demands it (NES, GB/GBC), licensed permissive cores where
   writing one is unrealistic (GBA via mGBA, SNES/MD via ares; both pending Gordon's approval to download). No GPL
   or non-commercial code in the binary.
6. **No ads, no tracking, no accounts.** Privacy manifest declares nothing collected.

## 1. Architecture

```
App (SwiftUI)                       CoreKit (Swift package, pure Swift, tests on the Mac)
 ├─ Library  ── GameStore ───────┐   ├─ EmulatorCore protocol, SystemID, InputState, VideoFrame, StateWriter/Reader
 ├─ Player   ── EmulatorSession ─┼─► ├─ NESCore   (6502 CPU, 2C02 PPU, 2A03 APU, mappers 0/1/2/3/4)
 │   ├─ MetalRenderer (MTKView)  │   ├─ GBCore    (SM83 CPU, DMG/CGB PPU, APU, MBC1/2/3/5)
 │   ├─ AudioOutput (AVAudioEngine)  └─ Shared: AudioResampler, RingBuffer, StateContainer
 │   ├─ TouchController (per pose)
 │   └─ InputRouter (touch + GCController + GCKeyboard → InputState)
 └─ DuoKit (pose, fold, halves; `-pose` debug override)
```

### 1.1 The core protocol (CoreKit)

```swift
public protocol EmulatorCore: AnyObject {
    static var system: SystemID { get }
    var videoSize: VideoSize { get }          // native width/height; may change (GB vs SGB later)
    var pixelAspect: Double { get }           // 1.0 square, 8/7 NES
    var frameRate: Double { get }             // 60.0988 NES NTSC, 59.7275 GB
    var audioSampleRate: Double { get }       // output rate the core resamples to (48 000)

    init(rom: Data, battery: Data?) throws    // validates header, picks mapper/MBC
    func reset()
    func runFrame(input: InputState)          // the only hot call
    var framebuffer: UnsafeBufferPointer<UInt32> { get }   // BGRA8, videoSize, owned by the core
    func drainAudio(into ring: AudioRing)     // mono Float32 at audioSampleRate
    var batteryRAM: Data? { get }             // nil if no battery
    func saveState() -> Data                  // versioned chunk stream (StateWriter)
    func loadState(_ data: Data) throws
}
```

- Cores are **not** `Sendable` and are confined to the emulation thread. Everything that crosses threads is a value
  (`InputState` is a `UInt32` bitmask per player), a lock-protected frame buffer, or the SPSC audio ring.
- No protocols, closures or allocation inside the per-cycle loop: each core is a set of `final class`es over
  `UnsafeMutablePointer` memory, with switch dispatch. Core targets build with `-Ounchecked` even in Debug, so the
  simulator plays at full speed.
- `InputState` is system-neutral: `up down left right a b x y l r start select` bits. Each core maps what it has.
- State format: `StateContainer` = magic `FBST`, container version, `SystemID`, core state version, ROM CRC32,
  timestamp, then the core payload (`StateWriter` little-endian fields, chunked per component). Loading a state
  from another ROM or an unknown version is refused with a message, never silently.

### 1.2 Threading and pacing (`EmulatorSession`)

- A dedicated `Thread` (QoS `.userInteractive`) owns the core. Commands (pause, resume, save, load, reset, speed,
  rewind on/off) arrive through a `Mutex`-guarded queue drained at frame boundaries.
- **Pacing v1:** the thread paces itself to the core's frame rate with `mach_absolute_time`, and nudges its period
  by up to 0.5 % from the audio ring's fill level (dynamic rate control, per research §5), so audio never under- or
  over-runs and video judder is at most one repeated frame a few times a minute. **v2:** `CAMetalDisplayLink`
  driven frames with the same DRC, for perfectly smooth ProMotion pacing. v1 is chosen because it is robust and
  independent of the view hierarchy (pose changes rebuild views; the session must not care).
- After each frame the thread copies the framebuffer into a triple buffer; `MetalRenderer` uploads the newest one
  at display refresh. Input is sampled from an atomic at the start of each frame.
- **Fast-forward:** 2x/4x (hold or toggle). Runs N frames per tick, presents the last, drops audio, and on exit
  clears the ring and resumes at normal fill, the failure Delta issue #521 describes.
- **Rewind:** while enabled, a snapshot every 4 frames into a ring of the last 20 s (NES state is about 12-25 KB, so
  ~3.6-7.5 MB; capped at 8 MB by bytes, not count). Holding the rewind control steps back one snapshot per display
  frame (so rewind runs at 4x) with audio muted; releasing resumes from that snapshot. Off by default on battery-saver.
- Background / interruption: pause, write battery RAM and an auto-state, stop audio engine.

### 1.3 Rendering (`MetalRenderer`)

- `MTKView` (`.bgra8Unorm`, `preferredFramesPerSecond` 60, `isPaused` false while playing), texture
  `.bgra8Unorm` shared storage, updated with `replace(region:)` from the newest frame.
- One full-screen quad with a fragment shader per **screen mode**:
  - **Auto (default):** Integer when the integer size fills at least 85 % of the available height, otherwise Sharp.
  - **Sharp:** integer pre-scale then bilinear down to the fit size ("sharp bilinear"): crisp pixels with
    no shimmer at non-integer sizes. This matters on the Duo's half-screens, where NES only fits at 1.9x.
  - **Integer:** largest whole multiple that fits, nearest sampling, letterboxed.
  - **Scanlines:** soft CRT-style horizontal lines with a gentle bloom (our own shader, compiled in).
  - **LCD:** pixel grid plus slight ghosting for handheld systems.
- Pixel aspect correction (NES 8:7) is a per-system setting, off by default (square pixels).
- The game view never sits under the hinge band, the Dynamic Island or the home indicator.

### 1.4 Audio (`AudioOutput`)

- `AVAudioEngine` + `AVAudioSourceNode` (mono Float32, 48 kHz) pulling from a lock-free SPSC ring. The render
  block is built in a `nonisolated static` helper (a closure written in a `@MainActor` method inherits main-actor
  isolation and Swift 6 traps when the render thread calls it; see the talking-computers HANDOFF).
- Cores produce samples at 48 kHz themselves: the NES APU is mixed per CPU cycle and decimated with a box filter
  plus a one-pole low-pass (and the hardware's 90/440 Hz high-passes); GB likewise.
- Underrun outputs the last sample decaying to zero (no clicks). `AVAudioSession` `.playback` + `.mixWithOthers` by default
  (players expect sound in silent mode), `.ambient` as a setting.

### 1.5 Input (`InputRouter`)

- Sources merged by OR into one `InputState` per player: touch controller, `GCController` (extended gamepad:
  D-pad and left stick, A/B/X/Y, shoulders, menu = Start, options = Select), `GCKeyboard` (arrows/WASD, Z/X/A/S,
  Return = Start, Right Shift = Select, Tab = fast-forward, Backspace = rewind, F1-F4 save slots).
- When a physical controller connects, the touch controller fades out and the game takes the whole display (on Duo
  table pose the bottom half becomes the "dock": save shelf, rewind scrubber, and a small "controller connected"
  plate). Touching the screen brings the touch controller back.
- Remapping UI is v1.1; the mapping table is data from day one.

## 2. The controller (touch)

### 2.1 Industrial design: "Graphite and Ember"

Our own handheld, not a pastiche:

- **Body:** a deep graphite slab with a very subtle vertical brushed grain (procedural, Canvas), a soft inner bevel
  where it meets the screen, and two ventilation slot arrays as a quiet signature (not speaker grilles of any
  console). Light mode is "Bone": warm off-white with graphite controls.
- **D-pad:** a single piece, rounded-square arms with a shallow dished centre, lit from the top-left. Pressing a
  direction tilts the piece 3 degrees toward it (rotation3DEffect) and darkens that arm's shadow. Eight-way: the
  diagonal zones are 30 degrees wide; a dead zone of 18 % of the radius in the centre. The touch area extends 40 %
  beyond the drawn piece. Sliding a thumb across arms switches direction without lifting.
- **Face buttons:** two (or four) domed caps in **ember** (a warm orange-red) and **sand**, with a specular
  highlight and a soft contact shadow. Pressed: the cap sinks 2 pt, the shadow tightens, the highlight dims, and a
  light haptic (`UIImpactFeedbackGenerator(.rigid)` at 0.7) fires on press only. A thumb resting between A and B
  presses both (a "rocker" zone), like real pads. Letters are etched in SF Rounded (Apple's system font for our
  own UI, not a console font).
- **Start/Select:** small pill keys, recessed into a channel. Guarded against accidental presses: they need a
  press of 80 ms or longer (research "hate" #7).
- **Menu key:** a round, recessed key with our three-dot glyph; opens the player menu (save/load slots, rewind,
  speed, screen mode, controller layout, quit).
- **Shoulders (L/R):** for future SNES/GBA, two long tabs along the top edge of the controller area.
- **Turbo / fast-forward:** a small chevron key near the menu key; hold for 2x, double-tap to latch.
- Haptics on by default with a setting; button press sounds off by default.
- Multi-touch: one touch per control, tracked by identity, so D-pad plus two buttons all work at once
  (UIKit-backed touch surface: SwiftUI gestures cannot track several fingers on independent controls reliably).

### 2.2 Per-pose layouts

All layouts come from one `ControllerLayout` value (control frames in a unit space) rendered by one
`TouchControllerView`, so skins and user layout editing (v1.1) are data, not code.

| Pose / device | Game | Controller |
|---|---|---|
| **Duo table** (horizontal fold, lid up) | The whole top half: the "screen". Sharp/Integer fit, a thin bezel with the game's title in small caps and a power LED that pulses with save activity. | The whole bottom half: a full handheld controller. D-pad left, face buttons right, Start/Select centre-bottom, menu and turbo centre-top, shoulders along the hinge edge. Nothing overlays the game. |
| **Duo book** (vertical fold, landscape) | Left page: the game, upper two-thirds. | Left page bottom: D-pad. Right page bottom: face buttons, Start/Select. Right page top: the **companion page**: four save-state slots with thumbnails, a rewind scrubber, speed, and (for future two-screen systems) the second screen. A "swap pages" setting mirrors it for left-handed players. |
| **Duo flat / ordinary iPhone portrait** | Top, full width, safe-area aware. | Below the game, the same controller as table pose drawn into the remaining space. |
| **iPhone landscape** | Centred, full height. | D-pad and face buttons as translucent (55 %) controls over the left and right margins; menu top-centre. |
| **iPad** | Portrait: as iPhone portrait, controller capped at 420 pt tall and centred. Landscape: as iPhone landscape with larger controls; Split View and Stage Manager supported by size class. | |

The controller always sits inside the near half / below the hinge band; the fold band itself is drawn as a dark
"seam" between bezel and controller so the two halves read as one object.

## 3. Library

- **Shelf, not a file list.** A grid of game cards grouped by system (plain-text headers: "NES", "Game Boy Color").
  A card is our own generated "cartridge label": a system-tinted card with the game's title set in a bold rounded
  face, the file's name as a subtitle, and, after first play, a screenshot from the auto-save as the artwork. No
  box art scraping (research §3: OpenVGDB / libretro-thumbnails licences are unclear). Users can set their own
  image later (v1.1).
- **Continue** row at the top: the last three played, opening straight into their auto-save.
- **Import:** a prominent "Add games" button and the empty state both open `.fileImporter` (multiple selection,
  `.nes`, `.gb`, `.gbc`, `.zip`). Also "Open in" / AirDrop via document types, and the app's Documents folder is
  visible in the Files app (`UIFileSharingEnabled`, `LSSupportsOpeningDocumentsInPlace`) with an Inbox that is
  scanned at launch. Files are copied into `Documents/Games/<System>/`. System is detected by header and
  extension; unknown files are rejected with a clear message. Zip support: v1.1 (needs our own inflate or
  Apple's `Compression` stream; no third-party code).
- **Empty state** explains in one sentence that the app plays games you own, and how to add them. It never names
  or links a ROM site.
- **Detail** (long press or the "i" on a card): save slots, battery save export/import, rename, delete (to a
  Recently Deleted folder for 30 days), per-game screen mode.
- **Duo table pose:** top half = the selected game's hero panel (large artwork, title, last played, slots),
  bottom half = the touch grid. **Book:** left page list, right page detail. Flat/iPhone/iPad: standard grid with
  detail sheet.
- Storage: `GameStore` is a JSON index (`library.json`) of `GameRecord { id (SHA-1 of ROM), title, system,
  fileName, added, lastPlayed, playTime }` beside the files. No Core Data.

## 4. Saves

- **Battery saves** as plain `.sav` files in `Documents/Saves/` (portable to other emulators), written on pause,
  background, quit and every 30 s if dirty.
- **Save states:** 4 manual slots + 1 auto slot per game, each a `StateContainer` file plus a PNG thumbnail.
  Auto-state written on background and quit; on next launch the game resumes from it (with an undo: "Started
  fresh instead?").
- iCloud Drive sync of `Saves/` and `States/`: v1.1 (needs entitlement decisions).

## 5. Cheats (v1.1)

Built-in decoders for NES Game Genie and GB GameShark / Game Genie, entered by hand. No bundled cheat database.

## 6. Systems and cores

| System | Core | Status tonight |
|---|---|---|
| NES | In-house `NESCore` | Build: 6502, PPU, APU (2 pulse, triangle, noise, DMC), mappers 0/1/2/3/4 |
| Game Boy / Color | In-house `GBCore` | Build if time allows after NES: SM83, PPU (DMG + CGB), APU, MBC1/3/5 |
| GBA | mGBA (MPL-2.0) | Needs download approval |
| SNES, Mega Drive, SMS/GG, PCE | ares (ISC) cores, or in-house SMS/GG | Needs download approval and a performance test |
| Atari 2600 | In-house later | — |
| N64, DS, PS1 | Skip | Licence/BIOS/JIT (research §2.3) |

## 7. Testing

- **No third-party ROMs tonight.** `Tools/asm6502.py` is a small two-pass 6502 assembler written in-repo;
  `TestROMs/` holds our own programs: `cpu_selftest` (exercises every official opcode and addressing mode, flags
  and page-crossing, writes a result code and draws PASS/FAIL), `demo` (a controllable sprite over a scrolling
  tiled background with music on the pulse and triangle channels and a sound effect on A), and mapper probes for
  MMC1, UxROM, CNROM and MMC3 (bank switching plus an MMC3 scanline IRQ split). An SM83 assembler and GB demo
  follow the same pattern.
- CoreKit unit tests (`swift test`, on the Mac) run each ROM headless for N frames and assert the result byte and a
  framebuffer hash; these become regression tests.
- Simulator: launch arguments `-pose table|book|flat` (DuoKit), `-autoplay <rom name>` (opens a bundled
  DEBUG-only test ROM straight into the player), `-autoInput "right:120,a:30"` (scripted input for screenshots).
  The test ROMs are copied into DEBUG builds only.
- Everything is simulator-only until Gordon tests on a device; the docs say so.

## 8. Settings

Screen mode, pixel aspect, haptics, button sounds, audio session (mix / exclusive), rewind on/off, auto-resume,
controller opacity (landscape), swap pages (book), About (non-affiliation line, licences, privacy).

## 9. Out of scope tonight

Skins import, remapping UI, cheats UI, iCloud sync, zip, RetroAchievements, link cable / multiplayer, AirPlay
external display, widgets, PAL timing, licensed cores.

## 10. Review changes (Fable, 11 Nov 2026)

1. **Book pose is landscape.** The physical model is one hinge parallel to the 669 pt edge: portrait canvas +
   horizontal fold = table (two 669x455 halves), landscape canvas + vertical fold = book (two 455x669 pages).
   DuoKit's simulator does not enforce this (`-pose book` in portrait gives impossible 314x951 pages), so book
   screenshots are taken with the simulator rotated to landscape, Info.plist allows landscape on iPhone, and every
   layout derives from `stage.farHalf` / `stage.nearHalf` / `stage.fold.frame` (margins included), never from
   assumed sizes.
2. **Canvas, not bounds.** Lay out inside `stage.canvas`; paint the graphite body across the full `bounds` so the
   debug letterbox reads as device body. On an iPhone simulator the halves are ~60 % of real size (iPhone 17 Pro:
   402x265 per table half), so Duo screenshots look more cramped than hardware; the iPad mini simulator is closest.
3. **Test ROMs never ship.** They live on the CoreKit *test* target and in a DEBUG-only app copy phase; a Release
   build check fails if any `.nes`/`.gb`/`.gbc` is inside any bundle.
4. **No stuck inputs.** `touchesCancelled`, controller-view teardown (pose change, background, controller
   connecting) zero the touch contribution to `InputState`. Start/Select register only if the touch *began* inside
   the pill (slides are the usual accidental press), instead of the 80 ms hold.
5. **Build order:** NROM + `cpu_selftest` + `demo` first; mappers 1-4 and their probes after. The core is constructed
   on the emulation thread from Sendable inputs (`Data`), never passed across.
6. **No PoseDetector.** A horizontal fold is always the laptop (table) layout; tent is never inferred, so the game is
   never drawn on a half that faces away.
7. Palette guard: ember is a cap colour only, never a red band on a Bone body; library card tints use the app's own
   palette, not console colours. Overscan crop (8 px top/bottom) is a per-system setting. Trademark search before
   the name is fixed.
