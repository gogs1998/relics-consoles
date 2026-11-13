# New systems: what players love, hate and ask for (DS, N64, PS1, PSP)

Web research, 13 Nov 2026; complements `research.md` §3-4. Numbers after issues are GitHub reaction totals. Reddit points are search excerpts only.

## Nintendo DS

| Love | Hate | Requests |
|---|---|---|
| Free placement and sizing of both screens in portrait and landscape (DraStic; [retropie](https://retropie.org.uk/forum/post/58245), [GBAtemp review](https://gbatemp.net/threads/drastic-ds-emulator-for-android-devices-review.352632/post-4746915)) | Phone noise cancelling removes "blow" input, so Phantom Hourglass and Spirit Tracks get stuck ([Delta #421](https://github.com/rileytestut/Delta/issues/421), 5) | A "blow" button that plays a sample (Delta #421; melonDS already supports this) |
| DraStic's speed and its higher-resolution 3D ([GBAtemp](https://gbatemp.net/threads/drastic-ds-emulator-for-android-devices-review.352632/post-4746915)) | Notch or Dynamic Island covering the screen when a controller is used ([Delta #375](https://github.com/rileytestut/Delta/issues/375), 5) | Internal-resolution setting, "want clarity 3D scenes" ([Delta #406](https://github.com/rileytestut/Delta/issues/406)) |
| melonDS accuracy; DraStic's loss from Google Play in Feb 2025 pushed users to it ([Time Extension](https://www.timeextension.com/news/2025/02/nintendo-ds-emulator-drastic-pulled-from-google-play-store)) | Firmware dumps rejected (128 KB firmware not accepted, [Delta #442](https://github.com/rileytestut/Delta/issues/442)); DSi needs BIOS files ([Joey's guide](https://www.joeysretrohandhelds.com/guides/melondualds-android-setup-guide/)) | Adjustable screen gap ([melonDS #1451](https://github.com/melonDS-emu/melonDS/issues/1451), 31) |
| | On-screen buttons cover stylus-only games ([retropie](https://retropie.org.uk/forum/post/51892)) | Layout editor that takes exact size values and has a grid ([melonDS-android #1428](https://github.com/rafaelvcaetano/melonDS-android/issues/1428)) |
| | Screen swap reportedly paywalled in Delta (Reddit excerpt, [r/Delta_Emulator](https://axebps-redlib.hf.space/r/Delta_Emulator/comments/1itj3vl/switchswap_ds_skin)) | Local wireless multiplayer ([melonDS-android #1493](https://github.com/rafaelvcaetano/melonDS-android/issues/1493), 10; Delta added online play, [9to5Mac](https://9to5mac.com/2025/03/31/delta-emulator-nintendo-ds-online-multiplayer/)) |

**Competitive note:** Delta is already shipping iPhone Duo DS closed-lid skins ([Delta #575](https://github.com/rileytestut/Delta/issues/575), Oct 2026). PPSSPP merged Duo inset support ([#22788](https://github.com/hrydgard/ppsspp/issues/22788)). Duo support alone is no longer a moat.

## Nintendo 64

| Love | Hate | Requests |
|---|---|---|
| Runs well on iOS through Mupen64Plus ports (Delta, Provenance, RetroArch; [GameRevolution](https://www.gamerevolution.com/guides/675653-is-there-a-n64-emulator-for-ios-in-2021)) | Touch stick far too sensitive ([Delta #380](https://github.com/rileytestut/Delta/issues/380), 7, Delta's most-reacted N64 issue) | Stick sensitivity and dead-zone settings (#380) |
| GLideN64 is the fix most often recommended for broken graphics ([Reddit excerpt](https://redlib.hackliberty.org/r/RetroArch/comments/1fk9js5/why_is_it_doing_this_on_ios/lnwztnw/?context=3)) | Stick snaps to 45 degrees, making games "almost impossible" ([Delta #580](https://github.com/rileytestut/Delta/issues/580)) | Widescreen output when the game or a hack renders at 16:9 ([Delta #88](https://github.com/rileytestut/Delta/issues/88)) |
| M64Plus FZ's ready-made accuracy profiles ([gamebrain summary](https://gamebrain.co/game/m64plus-fz-emulator)) | Touch controls cover about a third of a 6-inch screen; C-buttons are awkward (Reddit excerpt, [r/n64](https://pol1.lr.ggtyler.dev/r/n64/comments/1cceiv1/n64_on_ios_is_awesome)) | Right stick as C-buttons (same thread; mapping bugs in [libretro forum](https://forums.libretro.com/t/is-n64-input-bugged-on-android/50660)) |
| | Controller Pak broken, Blast Corps can't be played ([Delta #180](https://github.com/rileytestut/Delta/issues/180)) | Transfer Pak ([Provenance #2736](https://github.com/Provenance-Emu/Provenance/issues/2736)); upscaling and overclock ([#1957](https://github.com/Provenance-Emu/Provenance/issues/1957)) |
| | Glitches that depend on the plugin (Paper Mario, Banjo flicker; [HeldGames](https://heldgames.com/guides/n64-emulation-handheld)); widescreen hack "very glitchy" ([Batocera](https://wiki.batocera.org/systems:n64)) | RetroAchievements: 4 separate issues on M64Plus FZ ([#1232](https://github.com/mupen64plus-ae/mupen64plus-ae/issues/1232), 7) |

## PlayStation (PS1)

| Love | Hate | Requests |
|---|---|---|
| DuckStation: PGXP removes wobbling polygons; widescreen for 3D games ([HeldGames](https://heldgames.com/guides/duckstation-setup-guide), [GameTechWiki](https://emulation.gametechwiki.com/index.php/PGXP)) | Gamma: ads, few settings, crashes with controllers ([Android Authority](https://www.androidauthority.com/gamma-ps1-emulator-app-store-iphone-3442283/), [Xataka](https://www.xatakaon.com/apps/breaking-down-gamma-the-new-ps1-emulator-on-the-app-store/amp)) | Upscaling and filters (Gamma had none; Xataka) |
| Multi-disc games merged into one library entry, discs swapped from the menu, one memory card shared across discs ([Joey's DuckStation guide](https://joeysretrohandhelds.com/guides/duckstation-android-setup-guide/)) | Confusion over whether a BIOS is needed (Gamma, Reddit excerpt, [r/EmulationOniOS](https://lr.in.psf.lt/r/EmulationOniOS/comments/1cq8u17/ps1_is_officially_on_ios)) | Per-game memory cards, plus import and export (added to Gamma after demand, [App Store](https://apps.apple.com/us/app/gamma-ps-1-game-emulator/id6499106870)) |
| Per-game memory cards plus a card editor (DuckStation) | Region-specific games freeze after the BIOS screen ([Provenance #923](https://github.com/Provenance-Emu/Provenance/issues/923)); broken analog input ([#826](https://github.com/Provenance-Emu/Provenance/issues/826)) | CHD support (PCSX-ReARMed had a $200 bounty, now done: [#170](https://github.com/libretro/pcsx_rearmed/issues/170), [#137](https://github.com/libretro/pcsx_rearmed/issues/137)) |
| | LibCrypt games (FF IX, Spyro 2/3) fail without .sbi files; multi-disc PBP with SBI unresolved ([RetroPie](https://retropie.org.uk/forum/post/35496)) | Save files users can reach; Android scoped storage blocks this (Joey's guide) |

## PSP

| Love | Hate | Requests |
|---|---|---|
| PPSSPP runs most games at full speed on recent iPhones without JIT ([PPSSPP iOS docs](https://www.ppsspp.org/docs/reference/ios-support)) | Stutter on an iPhone 15 Pro Max (Reddit excerpt, [r/EmulationOniOS](https://redlib.hackliberty.org/r/EmulationOniOS/comments/1d6da2y/lets_go)); no JIT costs battery (PPSSPP docs) | Easier file transfer: Wi-Fi upload was only added in 1.20; before that Finder or USB was needed (PPSSPP docs) |
| Free app; Gold is a cosmetic one-off purchase ([PPSSPP news](https://ppsspp.org/news/live-on-app-store/)) | Racing games "clunky" on touch; crashes when loading a save ([justuseapp reviews](https://justuseapp.com/en/app/6496972903/ppsspp-psp-emulator/reviews)) **(thin)** | Ad hoc multiplayer that just works: relay servers since 1.20.1; P2P setup stays fiddly ([PPSSPP multiplayer](https://www.ppsspp.org/docs/multiplayer/quickstart), [forum](https://forums.ppsspp.org/showthread.php?pid=125475)) |
| Texture scaling and upscaling (well known, **not re-verified for iOS**) | No camera on iOS; microphone only added in 1.21 (PPSSPP docs) | |

Gaps: few readable App Store reviews for N64, PSP, Folium or Manic.

## Top 10 things that would make players pick us (ranked)

1. **N64 touch stick with real analog feel.** Adjustable sensitivity and dead zone, no 8-way snapping, optional right-hand C-stick. This is Delta's top N64 complaint (#380, #580).
2. **Best DS screen layouts on Duo and ordinary iPhone.** Free size and position, swap screens (free, not paywalled), adjustable gap, auto-hiding controls for stylus-only games. Delta already has Duo lid skins, so we have to beat it.
3. **DS 3D upscaling.** Our build uses melonDS's software renderer, which rules this out; it needs a GPU or Metal renderer path. DraStic's main draw (#406).
4. **DS "blow" button and closed-lid action** (#421, #575).
5. **PS1 multi-disc done right.** One library entry, swap in the menu, shared per-game memory card, import and export of `.mcr`; CHD/PBP/cue support, with .sbi picked up automatically for LibCrypt.
6. **No BIOS hassle, explained.** Our HLE BIOS for PS1 and FreeBIOS for DS should work out of the box, with a plain notice for the few games that won't. It answers Gamma's BIOS confusion and Delta's rejected firmware dumps (#442).
7. **N64 Controller Pak that works** (Delta #180), with paks saved per game. Then 16:9 output for games that support widescreen (#88).
8. **PSP save data and file import that are painless.** Files picker, ISO/CSO/zip, PSP SAVEDATA visible in Files and portable to PPSSPP elsewhere.
9. **Smooth PS1 3D.** PGXP-style wobble fix and an integer upscale (PCSX-ReARMed's neon GPU supports enhancement; verify what runs without JIT).
10. **Local multiplayer later.** DS local wireless and PSP ad hoc between nearby iPhones (melonDS-android #1493, Delta #215). Conflicts with our no-network rule: a v2 decision for Gordon.
