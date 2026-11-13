# Duo competitor scan (13 Nov 2026)

Web research only. "Sim-only" = developers say untested on hardware.

## 1. iOS emulators on iPhone Duo

- **Delta 2.0** (22 Oct 2026, one day before the Duo went on sale) is the benchmark. Its DS layout spans both halves of the inner display, it has controller skins for each Duo pose, the controls move as the hinge moves, and folding the phone shut puts the DS to sleep. Duo layouts are DS-first (9to5Mac describes only DS). Open bug #577, "GBA Skin Distorts on Fold" (2 Nov), shows the other systems are rough. It has no 3DS and no outer-display use. Sources: [9to5Mac](https://9to5mac.com/2026/10/22/retro-game-emulator-delta-looks-great-on-the-iphone-duo/), [Android Authority](https://www.androidauthority.com/delta-emulator-iphone-duo-nintendo-ds-3727110/), [Notebookcheck](https://www.notebookcheck.net/Huge-update-Emulator-turns-iPhone-Duo-into-Nintendo-DS-adds-Sega-games.1432969.0.html), [Delta issues](https://github.com/rileytestut/Delta/issues).
- **Manic EMU** has shipped Duo support in main-branch commit b5b0a1b, which made community [PR #122](https://github.com/Manic-EMU/ManicEMU/pull/122) unnecessary (closed 2 Nov). Its flex skin editor saves a separate layout for the inner screen, the outer screen and split view. GBA, DS and **3DS** skins get new inner and outer layouts that fill both screens: the only iOS emulator showing 3DS across the fold.
- **RetroArch** has feature request [#19908](https://github.com/libretro/RetroArch/issues/19908) and two open PRs. [#19985](https://github.com/libretro/RetroArch/pull/19985) fills the inner display, keeps the game above the fold in a sideways half-fold, and puts one DS/3DS screen on each half. [#20020](https://github.com/libretro/RetroArch/pull/20020) is a simpler fix (sim-only) that should land first. Neither is merged.
- **PPSSPP** has merged [PR #22788](https://github.com/hrydgard/ppsspp/pull/22788) (26 Oct, sim-only). It only moves content clear of the screen edges and the camera on the inner and outer displays. It has no layout that uses the fold.
- **Folium** (the only 3DS emulator on the App Store) has nothing for foldables, so 3DS is letterboxed. Its last update was 4 Oct ([HeldGames](https://heldgames.com/guides/iphone-duo-ds-3ds-emulation)).
- **Provenance, Gamma, DolphiniOS, iGBA-likes:** I found no Duo issues, PRs or announcements. No Duo-only emulator turned up either.
- **What users ask for:** I found no clear Reddit wish-list threads. These are the asks I could find:
  - Closing the phone to pause matters to people (HeldGames).
  - Pencil input for stylus games needs iOS 27.2 and the USB-C Pencil (HeldGames).
  - Two-player play with each person seeing their own screen, through Apple feedback reports FB25262170/79 ([#848](https://github.com/feedback-assistant/reports/issues/848), [#849](https://github.com/feedback-assistant/reports/issues/849)).
  - Local multiplayer across two devices, an old Delta request ([#401](https://github.com/rileytestut/Delta/issues/401)).

## 2. Android precedent

- **AYN Thor / Retroid:** official melonDS Android has no dual screen; the fork's presets confuse people ([#1637](https://github.com/rafaelvcaetano/melonDS-android/issues/1637)) or swap screens ([#1595](https://github.com/rafaelvcaetano/melonDS-android/discussions/1595)). DraStic is abandoned, with no Thor touch without a fork. Azahar has official second-screen 3DS (the favourite). Cemu fork often duplicates the screen; a PPSSPP fork zooms part of the game onto the bottom screen. Dual-screen launchers are alpha/beta. Complaints: ignored custom layouts, stretched bottom screen, fiddly setup ([Retro Game Corps](https://retrogamecorps.com/2025/10/27/dual-screen-android-handheld-guide/)).
- **Ayaneo Flip DS:** 3DS on two screens is the selling point. Reviewers say setup is fiddly and windows land on the wrong screen ([Time Extension](https://timeextension.com/reviews/ayaneo-flip-ds-a-great-but-costly-way-to-play-3ds-and-wii-u-in-2024), [DROIX](https://droix.net/blogs/ayaneo-flip-1s-ds-review/)).
- **Surface Duo:** RetroArch's spanned game-top/controls-bottom was praised ([Inverse](https://www.inverse.com/input/gaming/playstation-on-the-surface-duo-like-god-intended)).
- **Galaxy Fold/Flip:** Samsung's Flex Mode rule is "viewing on top, control on the bottom" ([Samsung](https://developer.samsung.com/one-ui/foldable-and-largescreen/foldable-excl-flex.html)). I found no evidence that any emulator uses it, Lemuroid included.

## 3. Apple Duo APIs (iOS 27.1 SDK)

See [slekens.dev](https://slekens.dev/en/blog/iphone-duo-xcode-27-1-six-foldable-apis/), [Classmethod](https://dev.classmethod.jp/en/articles/ios27-1-iphone-duo-new-apis/) and [examples repo](https://github.com/artemnovichkov/iPhone-Duo-by-Examples).

- **Hinge:** `onHingeChange` in SwiftUI or `UIHingeInteraction` in UIKit. It reports the posture (closed, partially open, fully open) plus a continuous angle. Apple says to use the angle for effects and interactions, not layout, and not to rely on how often or how precisely it updates. Degrees vs radians is disputed; check on device.
- **Reserved regions:** `division` marks the fold and `occlusion` marks the camera. Both work as layout guides.
- **Arrangement views:** `ArrangementView` / `UIArrangementViewController` place a primary and secondary view across the fold, as split or overlay.
- **Outer display:** only reachable during a camera capture (`CameraCaptureAccessory`). There is **no public API** for showing a game on the outer screen while you play on the inner one ([unwired-dev #1979](https://github.com/unwired-dev/product/pull/1979)).

Builds against the 27.0 SDK get no fold behaviour at all. These APIs have no game-controller hooks.

## Openings (nobody does these well yet)

1. **Fold layouts for every system, not just DS.** Delta's GBA breaks on the fold, PPSSPP only fixes edges and the camera, and RetroArch isn't merged. Hand-tuned pose layouts for NES, GB, GBA, SNES and MD are open ground.
2. **Hinge angle as an effect or input.** Nobody uses the continuous angle (CRT warm-up, lid gesture). Apple recommends it for effects; fits our CLAUDE.md rule only as optional decoration, never layout.
3. **Sleep and resume that feel like a real DS for every system.** Close to save-state and pause, open to resume instantly. Only Delta does this, and only for DS.
4. **A layout editor that knows the poses.** Manic has one per screen. Nobody offers live preview while you fold, or snaps controls to the fold and camera regions.
5. **A second screen for single-screen systems.** Save states, cheats or a zoom view on the lower half, as Thor fans liked.
6. **Book pose done properly** (tall DS, vertical games). RetroArch leaves it unchanged and Delta only covers it for DS.
7. **Zero-setup dual screen.** Android users hate fiddly presets, so auto-pick the layout from posture.
8. **Outer display / tent-pose play for two people is blocked by Apple.** File a Feedback report and don't promise it.
