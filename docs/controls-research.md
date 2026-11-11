# Foldback: touch controls research

Research for the layout editor, the generic "6-Button Arcade" layout, auto-fire, combo zones, D-pad diagonal
tuning and per-button haptics. Compiled 11 November 2026 from web pages only (no downloads, no code run).
It builds on `docs/research.md` §4 (love/hate) and the current controller spec in `docs/design.md` §2, and
does not repeat them.

Method notes. Reddit itself cannot be fetched, and the mirrors that used to work now fail, so Reddit points
come from search excerpts and say so. Google Play listings return only a title to the fetch tool, so Android
feature claims for My Boy!, John GBAC, Pizza Boy, ClassicBoy and M64Plus FZ come from third-party listings,
skin creators' pages or memory, and are marked **UNVERIFIED** where I could not confirm them. Defaults quoted for
RetroArch and PPSSPP were read directly from their source on GitHub, so they are the most solid numbers here.

A naming warning for us: `design.md` §2.1 uses "Turbo" for the fast-forward chevron. In every emulator below,
"turbo" means **auto-fire** (a held button repeating). This document says "auto-fire" for repeat presses and
"fast-forward" for speed, and recommends the app does the same (§4, item 11).

---

## 1. Summary table

| App (platform) | Layout editing | D-pad model | Combos / multi-press | Auto-fire | Haptics | Per-game / per-orientation | Sharing |
|---|---|---|---|---|---|---|---|
| **Delta** (iOS) | None in-app. You change layouts by swapping `.deltaskin` files; the community web editors make them | 3x3 grid, corners = diagonals | Skin items with several `inputs` (e.g. A+B); "Hold Button" from the pause menu | None (open requests #339, #277) | One on/off toggle covering buttons and stick | Skin per system, per orientation, per game, and a separate skin for "controller connected" (1.7) | `.deltaskin` files; big community |
| **RetroArch** (iOS/Android) | No in-app editor; global scale, X/Y offset, separation and aspect per orientation; web "RetroPad Editor" | `dpad_area` 8-way by angle; "D-Pad Diagonal Sensitivity" 80 % | `a|b` descriptors; "ABXY Overlap Sensitivity" 50 % | Yes: period 6 frames, duty half, modes | "Vibrate on Key Press" (on by default on iOS/Android) | Overrides per core / per game / per content directory | `.cfg` + images |
| **PPSSPP** (iOS/Android) | Full in-app editor: Move / Resize modes, **Snap** with **Grid** 2-256, per-button visibility | 8-way, 45° sectors, 4-way inside 20 % radius, 5 % dead zone, "Sticky D-Pad", "Disable D-Pad diagonals" | Custom buttons bind any set of keys, with "Toggle mode" and "Repeat mode" | "Repeat mode" on custom buttons; rapid-fire since 1.10 | "Haptic Feedback" on/off, fires on press only | Per-game config | Config files (not a sharing format) |
| **Lemuroid** (Android) | Global size and vertical position; up to 45° rotation for complex pads; no per-button moves | Radial; "diagonal zones have a smaller activation area" | Secondary dials round the primary control; slide between controls | Not found | Vibration, no intensity setting (#1146) | Per-system "Edit Controls" | None |
| **Provenance** (iOS) | Skins (Delta and Manic formats), free since 3.2.0 | Depends on skin | Planned "Modifier Combos" epic (#2816) | Planned per-button turbo, 2-30 Hz (#2819) | Not documented | Not documented | Imports `.deltaskin` / Manic skins |
| **Manic EMU** (iOS) | DeltaSkin-compatible skins plus `flex` (in-game layout settings) and `functionLayout` | Depends on skin | Skin items as in Delta | Not found | `haptics` function button | Screen position and size presets for DS/3DS | Skin files; skin sound effects (`sound.caf`) |
| **Gamma** (iOS) | Custom skins | Depends on skin | Not found | Not found | Not found | Portrait and landscape skins | Skin files |
| **Folium** (iOS) | Custom screen layouts (some cores); skins | Not documented | Not found | Not found | Present, users say they cannot turn it off | Per core | Skins |
| **My Boy!** (Android) | Position and size of every control and the video; layout profiles | UNVERIFIED | A+B combo key confirmed by a user review; others requested | UNVERIFIED | UNVERIFIED | Profiles | UNVERIFIED |
| **John GBAC / NESS** (Android) | UNVERIFIED: layout editing, skins | UNVERIFIED | UNVERIFIED: combo keys | UNVERIFIED: rapid-fire keys | UNVERIFIED | UNVERIFIED | Skins (UNVERIFIED) |
| **Pizza Boy GBA/GBC** (Android) | In-game "Edit layout"; movable, reactive skin buttons; image "stickers" | UNVERIFIED | UNVERIFIED | UNVERIFIED | UNVERIFIED | UNVERIFIED | Full-skin packs (itch.io) |
| **ClassicBoy** (Android) | On-screen buttons; gesture and tilt controllers (premium) | Tilt can drive the D-pad | UNVERIFIED | "Turbo" here means game speed | UNVERIFIED | UNVERIFIED | UNVERIFIED |
| **M64Plus FZ** (Android) | UNVERIFIED: touch profiles editor, auto-hide | UNVERIFIED | UNVERIFIED | UNVERIFIED | UNVERIFIED | UNVERIFIED | UNVERIFIED |

---

## 2. App by app

### 2.1 Delta (iOS)

**Skin format.** A `.deltaskin` is a renamed zip with `info.json` and art. Each representation (iPhone
`standard`/`edgeToEdge`, iPad `standard`/`splitView`) has orientations, each with `assets`, `items`, `screens`,
`mappingSize`, an orientation-level `extendedEdges` (default touch padding: `top`, `bottom`, `left`, `right`)
and `translucent`, which opts the skin into Delta's opacity slider
([community docs](https://noah978.gitbook.io/delta-docs/skins)). Each item has `inputs`, a `frame` in points,
and an optional per-item `extendedEdges` override. Putting several inputs in one item makes a **combined
input**; the docs use `["a","b","start","select"]` for a soft reset. D-pads take a dictionary of `up/down/left/right`
and the frame is **split into a 3x3 grid**, with corner cells pressing two directions; the docs say to map the
D-pad with no padding. A `thumbstick` object (image, width, height) feeds `analogStick*` inputs. Special inputs:
`menu`, `quickSave`, `quickLoad`, `fastForward`, `toggleFastForward`.

**Geometry note (my calculation, not from Delta).** On a 3x3 grid, a thumb on the rim of the pad gets a
diagonal for about 51° of each 90° quadrant and a cardinal for only about 39°, because the corner cells are
as big as the edge cells. Near the centre it gets nothing directional. So Delta's diagonals are generous at the
rim, and its real problem is size: issue
[#318](https://github.com/rileytestut/Delta/issues/318) asks to "increase the touch targets for all of the
cores" because down, down-right, right rolls "are really hard to hit".

**Settings.** "Controller Opacity" (only for skins marked translucent); "Touch & Haptics" is a single toggle for
buttons and stick, hidden on iPad; no intensity setting
([Delta user guide](https://faq.deltaemulator.com/llms-full.txt)). Per-game "Preferred game skin" (1.7), a skin
for when a controller is connected (system-wide or per game), `menuInsets` for phone-case controllers, "Skin
Debugging" that shows hitboxes and can ignore `extendedEdges` (1.6), "Hold Button" from the pause menu, animated
skins and screen repositioning (2.0)
([guide](https://faq.deltaemulator.com/llms-full.txt);
[Retro Dodo](https://retrododo.com/delta-ios-emulation-app-is-getting-animated-skins-screen-repositioning/)).
Delta 2.0 (October 2026) added Mega Drive with skins that "recreate the classic Genesis controller look" and
iPhone Duo skins "optimised for each pose"
([Retro Dodo](https://retrododo.com/delta-emulator-gets-huge-2-0-update-and-iphone-duo-support/)). Whether a
6-button Mega Drive skin ships is UNVERIFIED. Third-party Duo skins are already selling ("Crystal Shell", £2.99
each; [Retro Dodo](https://retrododo.com/stunning-transparent-skins-for-delta-emulator-on-iphone-duo-are-now-here/)),
so **Delta is our direct Duo competitor on controls**.

**Editors.** No in-app editor. The community web editor `delta-emu-ui-editor` (Next.js; opens and exports
`.deltaskin`, or loads `info.json` and assets separately) is the main tool found; the original GitHub location
is UNVERIFIED (found via a mirror). Per-game skins are powerful but fiddly: one developer built a custom skin for
a single game, rotating the D-pad and "mapping empty space to the nearest button"
([Ginger Beard Man](https://blog.gingerbeardman.com/2024/04/18/per-game-skins-in-the-delta-classic-video-game-emulator-for-ios)).

**Haptics.** Praised in reviews (research.md §4), but issue
[#57](https://github.com/rileytestut/Delta/issues/57) calls them "vague ... almost Android-like", "Definitely
feels like something, but not a button click", and holds up MAME4iOS's click haptic as the model.

### 2.2 RetroArch (iOS and Android)

**Overlay format** ([libretro docs](https://docs.libretro.com/development/retroarch/input/overlay)): each
descriptor is `button,x,y,hitbox,range_x,range_y` with `radial` or `rect` hitboxes. Useful ideas we should
borrow, not copy:

- `alpha_mod` (button brightens when pressed) and **`range_mod`**: the hitbox grows while held, so a thumb that
  drifts does not drop the press.
- `reach_x/y` and directional `reach_left/right/up/down`: hit area changes without moving the art.
- `exclusive` and `range_mod_exclusive`: one finger owns one button, resolving overlaps.
- `dpad_area` and `abxy_area`: 8-way zones decided by angle from the centre.
- `left|up`-style multi-button descriptors (combo buttons).
- `movable`: art follows the finger inside a bounding area.
- `next_target`: switch to a named overlay (layout pages).

**Menu settings.** Per orientation: scale, aspect adjustment, horizontal and vertical separation, X and Y
offset; plus opacity, auto-rotate, auto-scale, "Show Inputs on Overlay", "Hide Overlay When Controller is
Connected" ([menu map](https://docs.libretro.com/guides/xmb-menu-map)). From the source
([config.def.h](https://github.com/libretro/RetroArch/blob/master/config.def.h),
[strings](https://github.com/libretro/RetroArch/blob/master/intl/msg_hash_us.h)):

| Setting | Default | Meaning |
|---|---|---|
| Overlay opacity | 0.7 (0.5 on some platforms) | |
| D-Pad Diagonal Sensitivity | **80 %** | "Adjust the size of diagonal zones. Set to 100% for 8-way symmetry." So 80 % gives diagonal sectors of about 36° and cardinals of about 54° |
| ABXY Overlap Sensitivity | **50 %** | "Adjust the size of overlap zones in the face button diamond" |
| Turbo period | **6 frames** (10 Hz at 60 fps) | |
| Turbo duty cycle | 0 = half period | |
| Turbo default button | B | Turbo on the D-pad off by default |
| Vibrate on key press | **on** for iOS and Android | |

Turbo modes include "Single Button (Hold)" for arcade-style auto-fire; the guide says lengthen the period "if a
game ignores fast presses" ([turbo guide](https://docs.libretro.com/guides/turbo-fire/)), and a RetroPie user
found 9 frames worked better in some shooters
([forum](https://retropie.org.uk/forum/post/263993)).

**Editors.** The web "RetroPad Editor" builds overlays; combos "can be entered manually" in a field
([libretro forum](https://forums.libretro.com/t/retropad-editor-create-and-edit-onscreen-gamepads/38331)).

**Complaints.** Overlay D-pad touch areas "too small"; touch controls that "completely stop working randomly";
a menu button that opened the menu and then selected whatever was under the finger (fixed in 1.7.9); a developer
calling overlays "a necessary evil"
([forum](https://forums.libretro.com/t/problem-concerning-the-touch-controls/13365);
[1.6.3 iOS issues](https://forums.libretro.com/t/retroarch-1-6-3-ios-interface-issues/11532)). Mostly 2015-2019.
Global versus per-core settings overriding each other is in research.md §4.

### 2.3 PPSSPP (iOS and Android)

The most complete **in-app** editor of the lot. From the source
([TouchControlLayoutScreen.cpp](https://github.com/hrydgard/ppsspp/blob/master/UI/TouchControlLayoutScreen.cpp)):
a "Move"/"Resize" mode strip; in Resize, vertical drag changes scale (0.5-3.0) and horizontal drag changes
spacing (0.5-3.0); a **"Snap"** checkbox and a **"Grid"** slider from 2 to 256; a "Customize" screen for
per-control visibility. Custom buttons
([CustomButtonMappingScreen.cpp](https://github.com/hrydgard/ppsspp/blob/master/UI/CustomButtonMappingScreen.cpp))
have a shape, an icon, "Visible", **"Toggle mode"**, **"Repeat mode"**, and a checkbox grid of keys, so one
button can press any combination. Combo keys date from 1.2; toggle mode came in 1.12; rapid-fire on touch in
1.10; combo mapping was disabled by default in 1.16.2
([1.12 notes](https://www.ppsspp.org/news/release-1.12);
[history mirror](https://code.teampandory.com/thirdparty/ppsspp/src/commit/4221a09edfef65b36c820e401c6f16a9d901b39b/history.md)).

**D-pad maths** ([GamepadEmu.cpp](https://github.com/hrydgard/ppsspp/blob/master/UI/GamepadEmu.cpp)): dead
zone `0.05` of the pad width; released if the touch goes beyond half the width, unless "Sticky D-Pad" is on;
**4-way inside radius 0.2**, 8-way outside it with plain 45° sectors; haptic fires only on a newly pressed
direction, never on release. Settings page
([docs](https://www.ppsspp.org/docs/settings/controls)): opacity, "Auto-hide buttons after delay", "Keep
first touched button pressed when dragging" (touch gliding), "Sticky D-Pad", "Disable D-Pad diagonals", "Haptic
Feedback". A 2013 forum thread shows the developer tuning the same trade-off: diagonals made harder "to make it
harder to accidentally hit", then loosened because "it was too loose before"
([forum](https://forums.ppsspp.org/showthread.php?tid=7742)).

**Reviews.** Praise for being able to "customize the button layout with touchscreen" on a small phone; the
headline complaint is "you can't hit more than one on screen button at once"
([App Store reviews](https://apps.apple.com/us/app/ppsspp-psp-emulator/id6496972903?see-all=reviews)). Touch
gliding arrived in 1.19 ([Gadget Hacks](https://android.gadgethacks.com/news/ppsspp-finally-fixes-psp-touch-controls-on-android/)).

### 2.4 Lemuroid (Android)

A radial design: the primary control sits under the thumb and secondary keys sit round it; touch targets "no
longer tied to the drawn graphics"; size and vertical position adjustable; complex pads rotate up to 45°; you can
slide between controls, but D-pads and sticks stay locked to their finger; "the D-pad's diagonal zones have a
smaller activation area" ([1.5.0 post](https://swordfish90.github.io/lemuroid-1-5-0.html); library
"RadialGamePad"). Despite the smaller zones, a 2026 issue says "you can very easily get diagonal presses" that
spoil grid-based puzzle games, and asks for a per-system 4-way/8-way switch
([#1167](https://github.com/Swordfish90/Lemuroid/issues/1167)). Other open requests: move individual buttons
([#1013](https://github.com/Swordfish90/Lemuroid/issues/1013), with a reply about "hitting the wrong button or
extra buttons"), free per-game layouts or named layouts
([#656](https://github.com/Swordfish90/Lemuroid/issues/656)), and a vibration intensity setting because the
haptic "feels intense, like it's at maximum level"
([#1146](https://github.com/Swordfish90/Lemuroid/issues/1146)).

### 2.5 Provenance, Manic EMU, Gamma, Folium (iOS)

- **Provenance** made full Delta and Manic skin support free in 3.2.0
([release](https://newreleases.io/project/github/Provenance-Emu/Provenance/release/3.2.0)). Its developer says
the `.deltaskin` "specs are incomplete", so the decoder was built by feeding community skins to an AI model
(same source; UNVERIFIED beyond the mirror). A March 2026 ticket specifies per-button turbo at 2, 4, 8, 15 or
30 Hz, for touch and MFi, saved per game or system, with a HUD indicator
([#2819](https://github.com/Provenance-Emu/Provenance/issues/2819), closed, so presumably shipped:
UNVERIFIED), part of a "Modifier Combos" epic ([#2816](https://github.com/Provenance-Emu/Provenance/issues/2816)).
An old overlay-overhaul ticket is worth reading for its premise: "Touchscreen is basically all Thumbs" and the
left thumb "is busy with movement most often", plus a request for sticky (latching) buttons
([#718](https://github.com/Provenance-Emu/Provenance/issues/718)). A 2026 bug: touch controls stayed visible with
a DualShock 4 connected ([#3630](https://github.com/Provenance-Emu/Provenance/issues/3630)).
- **Manic EMU** reads DeltaSkin and adds function buttons: `flex` (in-game layout settings), `functionLayout`,
`haptics`, `screenScaling`, `reverseScreens`, animated switch buttons, and per-skin press sounds from `sound.caf`
([skin guide](https://manicemu.pages.dev/Homemade-Skin-Guide-EN/)). Reviewers want screen-layout presets and a
built-in skin store, and dislike touch controls "taking up the view of the screen"
([reviews](https://apps.apple.com/us/app/manic-emu-game-emulator/id6743335790?see-all=reviews)).
- **Gamma** advertises portrait and landscape controllers and user-made skins
([App Store](https://apps.apple.com/us/app/gamma-ps-1-game-emulator/id6499106870)); opacity and haptic options
not found.
- **Folium**: custom screen layouts on some cores, reported to reset on relaunch; users cannot turn the haptics off
("how to remove these terrible haptics", App Store review via search excerpt, UNVERIFIED as current)
([App Store](https://apps.apple.com/gb/app/folium/id6498623389)).

### 2.6 Android single-system apps

- **My Boy!**: listings say you can adjust the position and size of each control and the video, and save
layout and key-mapping profiles; one review says only an A+B combo exists and asks for L+A, R+A
([AppGoblin](https://appgoblin.info/apps/com.fastemulator.gba)). Turbo UNVERIFIED.
- **John GBAC / John NESS**: from memory, layout editing, skins, rapid-fire and combo keys. **UNVERIFIED** (no
page could be read).
- **Pizza Boy GBA/GBC**: in-game "Edit layout"; skin packs with "fully reactive and movable" buttons; images
placed as "stickers" for borders ([itch.io pack](https://lnkd.itch.io/pbgba-skins)). Turbo and combos UNVERIFIED.
- **ClassicBoy**: touchscreen gestures mapped to controller inputs and tilt-as-D-pad with calibration, both
premium ([developer page](https://sites.google.com/a/portableandroid.com/classicboy-zh/home)).
- **M64Plus FZ**: touch profile editor, auto-hide and stick sensitivity are what I remember; **UNVERIFIED**.

### 2.7 Newer: Apple's Touch Controller framework

Apple's `TCTouchController` presents on-screen controls as a `GCController`, with buttons, thumbsticks and
touchpads, nine anchor points per layout, Metal rendering, and a `colliderShape` of `.leftSide`/`.rightSide` so a
control answers for half the screen, because "players can't feel where their finger is" relative to the art
([WWDC session](https://developer.apple.com/videos/play/wwdc2026/358/)). The session covers no D-pad, haptics,
or player customisation. **We should not adopt it** for the controller itself (no D-pad, Apple's look, no
editor), but the anchor model and "hit area larger than art" are sound, and presenting our touch controller to
the input router as just another controller matches our `InputRouter` design.

---

## 3. What users praise and complain about (new points beyond research.md §4)

**Praise**
1. **A real editor beats skins.** PPSSPP reviewers like laying out buttons for a small phone (App Store, above);
Lemuroid users leave for apps "that give this button layout freedom" (#656).
2. **Haptics that feel like a click**, not a buzz (Delta #57, pointing to MAME4iOS).
3. **Hold Button** as an occasional-touch aid: "a really clever idea"
([Delta reviews](https://apps.apple.com/gb/app/delta-game-emulator/id1048524688?see-all=reviews)).
4. **Sliding between buttons.** A r/Delta_Emulator user moved to RetroArch because it lets you hold one button
and slide to another (search excerpt, UNVERIFIED wording).
5. **Large hit areas decoupled from the art** (Lemuroid's 1.5.0 rationale; Apple's guidance).

**Complaints**
1. **Only one button per thumb.** Delta: "i was only able to have pressed 1 button on the right side of the
screen at a time" (Delta reviews, Dec 2024); PPSSPP: "you can't hit more than one on screen button at once".
2. **Diagonals: both directions of failure.** Too hard on Delta (#318), too easy on Lemuroid (#1167). The fix is
a tunable setting with a sane default, not one magic number.
3. **No auto-fire** in Delta (#339, #277, both open).
4. **Haptics you cannot tune or turn off**: too strong (Lemuroid #1146), vague (Delta #57), cannot disable
(Folium).
5. **Fighting games on glass.** Mega Drive 3- and 6-button pads are "notoriously difficult to use on a flat
glass screen"; a blind user on AppleVis says for one fighting game "you really have to use the controler"
([AppleVis](https://applevis.com/comment/171406)). Nobody ships a well-designed generic 6-button touch layout
that I could find.
6. **Phantom and stuck input**: menu button selecting what was under the finger (RetroArch); touch controls
showing over a connected pad (Provenance #3630).
7. **Overlays covering the game** (Manic review); Duo table pose avoids this by design.
8. **Opacity bugs**: "Opacity Resets" ([Delta #237](https://github.com/rileytestut/Delta/issues/237)),
"Controller Opacity Not Working" ([#232](https://github.com/rileytestut/Delta/issues/232)).
9. **Lag** perceived on button presses ("a significant lag when pressing buttons", Delta review, May 2024).
10. **Skins are hard to find and hard to make** (Manic wants a skin store; Provenance had to reverse-engineer the
format).

---

## 4. How we beat them

The gap in one line: data-driven layouts (Delta, RetroArch) make sharing possible and an in-app editor (PPSSPP)
makes customisation usable, but nobody on iOS has both.

Ordered by priority. Numbers are proposed defaults to test on Gordon's device; anything marked "change" differs
from `design.md` §2.

### P0: must ship with the editor

1. **One layout model, edited in place.** The editor opens over the live, paused game in the current pose and
shows the real controller art. Each control has a frame in the pose's unit space, a hit inset, opacity, visibility,
binding and haptic profile. Layouts are scoped **system > pose > game**, with a clear "Using: Game Boy, table
pose, this game only" header and a one-tap "apply to all games for this system". Delta's per-game choice is
buried in a context menu; ours is in the editor.
2. **Snap and guides.** Default grid **8 pt** with a 4 pt fine grid at higher zoom; drag with two fingers or long-
press to move off-grid. Smart guides for the pose's centre line, mirror symmetry (moving the D-pad offers to
mirror the face cluster), equal spacing, the safe area and the **hinge band** (never placeable). PPSSPP's grid is a
bare 2-256 slider; ours should just feel right.
3. **Minimum sizes enforced.** Hit area never below **44 x 44 pt** (Apple HIG). Drawn size can be smaller (Start
and Select pills ~36 x 16 pt drawn) but their hit area is 44 pt. The resize handle stops at the minimum with a
haptic tick. Default face buttons **58 pt** drawn; D-pad **132 pt** across in table pose.
4. **Hit-area expansion and empty-space ownership.** Hit area = drawn shape plus **10 pt** on all sides, then the
rest of each controller half is given to the **nearest control** (a Voronoi split, clipped at 44 pt beyond the
art so the hinge and screen edges stay inert). While a control is held its hit area grows a further **15 %**
(RetroArch's `range_mod` idea). Each touch owns exactly one control or the D-pad until lifted or slid. The
editor's "show touch zones" view draws all of this, which Delta only offers as an experimental debug switch.
(`design.md` says +40 % for the D-pad; keep that for the D-pad only.)
5. **D-pad defaults (change).** Angle-based 8-way. Diagonal sector **36°** each (cardinals 54°), matching RetroArch's
long-standing 80 % default, rather than the 30° in `design.md`. Dead zone **15 %** of the radius; a **4-way ring
from 15 % to 30 %** (PPSSPP uses 20 %) so small thumb rolls near the centre never produce diagonals; 8-way beyond.
**5° hysteresis** on every sector boundary so a resting thumb cannot flicker between right and down-right. The
D-pad keeps its finger even when it slides off ("sticky", as PPSSPP and Lemuroid); it releases only on lift. User
setting "Diagonals": Off (4-way) / Narrow 24° / Standard 36° / Wide 45° (symmetric), per system with a per-game
override. Never switch it automatically: Lemuroid's puzzle-game complaint and Delta's rolling-move complaint are
opposite needs, so the player chooses.
6. **Two buttons with one thumb.** Default ON: a **combo zone** between every adjacent pair of face buttons
(RetroArch calls this overlap). Geometry: for buttons of diameter *d* whose centres are *c* apart, the zone is a
capsule on the line between the centres, **0.45 d wide and spanning the gap plus 20 % of each button**; a touch
there presses both. Plus **touch gliding**: sliding from one face button to another moves the press (PPSSPP's
"keep first touched button pressed" stays an option for players who want roll-ons that add rather than move).
This fixes the most repeated complaint on Delta and PPSSPP. The existing `design.md` "rocker zone" is this; the
editor should show and resize it.
7. **Per-button haptics that click (change).** Use Core Haptics transients, prepared ahead to cut latency:
press = intensity **0.6**, sharpness **0.85** (a click, not a buzz, answering Delta #57); release = optional,
intensity 0.25; D-pad direction change = intensity **0.4**, sharpness 0.7; combo zone = a single slightly stronger
click (0.7) rather than two; guarded keys = a double tick. Global setting **Off / Light (0.6x) / Medium / Strong
(1.3x)**, default Medium, with a per-button on/off in the editor. Honour the system "System Haptics" switch and
Low Power Mode (drop to press-only). `design.md`'s `.rigid` at 0.7 is a fine fallback.
8. **Guarded Start, Select and Menu.** Keep the **80 ms** minimum press (raise to **120 ms** in table pose, where
thumbs sweep the lower half). Place them off the thumb arcs: in table pose, **along the hinge edge** of the
controller half (the far edge from the player), not centre-bottom (change). The editor warns, with a soft red
outline, when any guarded key is placed inside a thumb's reach band (item 13, heat map). A "Lock Start/Select during
play" option needs a long-press of 500 ms, for players who never pause.
9. **Import, export, reset.** Layouts export as a small, versioned JSON file (`.foldlayout`, our own schema with a
`duo` block per pose and an `iphone`/`ipad` fallback) through the share sheet and Files; import validates bounds,
minimum sizes and bindings and shows a preview before applying. Always "Reset to default" per scope, and undo/redo
in the editor. A `.deltaskin` importer is a later nice-to-have (research.md §3); the spec is "incomplete" by
Provenance's own account, so treat it as best-effort.
10. **Physical controller connected.** Touch controller fades out (as designed); a separate, optional layout for
"controller connected" (Delta 1.7) holds only the menu and save keys. Never show both (Provenance #3630).

### P1: the features that sell it

11. **Auto-fire, per button, frame-locked.** Any face or shoulder button can be set to Auto-fire in the editor
(never the D-pad by default, as RetroArch). Rate in **emulated frames**, so fast-forward and slow-motion keep it
consistent: default **10 Hz** (3 frames on, 3 off at 60 fps, RetroArch's default), choices 5 / 7.5 / 10 / 15 / 20 /
30 Hz with a note that 30 Hz (1 on, 1 off) is ignored by some games. Two modes: **hold to fire** (default) and
**latch** (tap to start, tap to stop, like Provenance #718's sticky buttons). A small ember dot pulses on the
button art at the fire rate. A dedicated Auto-fire key is optional, never in the default layout. Name it
"Auto-fire" in UI; keep "Fast-forward" for speed (change from `design.md`'s "Turbo").
12. **The generic 6-Button Arcade layout.** For SNES and Mega Drive, available to any game:
    - Two rows of three, **arched**: each row follows the right thumb's natural arc, rotated about **12°** (rising
      to the right in table pose), lower row offset half a button to the left so the thumb rolls diagonally across
      pairs.
    - Buttons **52 pt** drawn, **6 pt** gaps, hit areas meeting at the midlines (no dead gaps).
    - Combo zones on **both vertical pairs** (top-bottom, the "light plus heavy" chord) and horizontal neighbours;
      a three-button zone in the centre of each row is off by default.
    - Mega Drive: labelled A B C on the bottom row, X Y Z above, with the core set to the 6-button pad; a
      "3-button pad" switch per game for titles that misbehave with 6 buttons (check the ares Mega Drive core for
      6-button support before promising it). SNES: Y X L top, B A R bottom (mapping preset, editable).
    - Start is guarded and placed on the hinge edge; the D-pad gets the "Standard 36°" setting plus a stronger
      hysteresis (7°) for quarter-circle motions.
    - Ship it as a layout, not a mode, so players can tweak and share it.
13. **Personal thumb-reach heat map (local only).** With the user's opt-in, the app records where their touches
land relative to each control's centre, **on device only** (no network, no analytics, as our hard rules require).
The editor overlays it: a warm cloud per control showing average offset and spread. One tap "Fit to my thumbs"
nudges each control toward the centre of its cloud and widens hit areas where the spread is large. Default table-
pose reach bands come from geometry: two arcs centred on the lower corners of the controller half with radius
about **60 % of the half's width**, the comfortable thumb zone. No other emulator does this.
14. **Opacity that works.** Opacity per control and per layout (30-100 %, default 100 % on the Duo controller half
where nothing overlays the game; 60 % for overlay layouts on ordinary iPhone landscape). Persist reliably (Delta
#237, #232). Pressed state always draws at full opacity for 120 ms so a faint layout still confirms presses.

### P2: Duo-specific and polish

15. **Use the hinge edge.** In table pose the edge of the controller half next to the hinge is far from resting
thumbs but easy for an index finger: put shoulders there (as designed), and the guarded keys and an optional
"swipe along the hinge edge" gesture to scrub rewind. Never place anything inside the hinge band itself.
16. **Book pose.** Each page gets one hand's cluster at its outer lower corner; the editor mirrors the pair for
left-handed players (`design.md`'s "swap pages") and keeps controls clear of the fold.
17. **Pose-aware copying.** "Copy this layout to book pose" maps controls by role and relative position, then
asks the user to check, rather than leaving other poses at defaults.
18. **Shareable but safe.** Layout files carry no art in v1, so sharing cannot bring in trade dress.
19. **Latency hygiene.** Process touches on the touch event, write `InputState` straight away, and fire haptics
after the state write, never before. Measure press-to-frame latency in the debug HUD; a "lag" reputation (Delta
review) is hard to undo.
20. **Accessibility.** VoiceOver labels on every control in the editor; a "Hold Button" equivalent and auto-fire
double as accessibility aids (as Delta #339 notes).

### Default numbers at a glance

| Parameter | Proposed default | Range in settings | Source of the idea |
|---|---|---|---|
| Diagonal sector | 36° | 0 (4-way), 24°, 36°, 45° | RetroArch 80 % |
| Dead zone | 15 % of D-pad radius | 5-25 % | PPSSPP 5 %, design.md 18 % |
| 4-way inner ring | 15-30 % of radius | on/off | PPSSPP 20 % |
| Sector hysteresis | 5° (7° in arcade layout) | fixed | ours |
| Hit expansion | +10 pt, then nearest-control fill | 0-20 pt | Delta `extendedEdges`, Apple collider |
| Held-button growth | +15 % | fixed | RetroArch `range_mod` |
| Combo zone | capsule 0.45 d wide | 0-0.7 d, per pair | RetroArch ABXY 50 % |
| Haptic press | intensity 0.6, sharpness 0.85 | Off / Light / Medium / Strong | Delta #57, Lemuroid #1146 |
| Auto-fire | 10 Hz, hold mode | 5-30 Hz, hold or latch | RetroArch 6-frame period |
| Snap grid | 8 pt (4 pt fine) | 4, 8, 16 pt, off | PPSSPP grid |
| Minimum hit area | 44 x 44 pt | not below | Apple HIG |
| Start/Select guard | 80 ms (120 ms in table pose) | 0-500 ms | design.md, Provenance #345 |
| Overlay opacity | 100 % on Duo controller half, 60 % over game | 30-100 % | RetroArch 0.7 |

All of these need Gordon's device check: haptics, touch latency and thumb reach cannot be judged in the
simulator.
