# GameCube/Wii on the App Store: feasibility (researched 2026-11-11)

Web research only. dolphin-emu.org blocked my fetcher, so Dolphin blog figures come from search excerpts. Repo facts were checked via the GitHub API.

## 1. Dolphin without JIT
- **Cached Interpreter 2.0** shipped in Release 2407/2409 (PR #12723; blog post 2024-09-04). It gave a 10–25% uplift and is "3 to 4 times faster than the interpreter". The blog adds that it "will likely not see another significant performance bump".
- DolphiniOS 5.0.0b1 (2025-10-11) found about 10% more.
- Dolphin's 2024 anniversary report calls both interpreters unusable for play. DolphiniOS 4.0.0b8 (2025-01-17) calls No-JIT mode "very slow": it needs a high-end device plus VBI Skip and CPU underclock. On an iPhone 15 Pro Max the interpreter was "basically unplayable" (OatmealDome, 2024-04-19).
- **Best measured iOS figures:** iCube's own performance doc (2026-09-17, device not named) has the Wind Waker intro at 0.59–0.61x full speed and Chibi-Robo at 0.47–0.53x. Both predate its 2026-09-19 engine rebuild. Provenance's video claims "jitless 60fps for most games" (Nintendo Wire, 2026-09-21), but no measurement backs that up.

## 2. Graphics
Mainline Dolphin has had a native Metal backend since 2022, and it is faster than MoltenVK on macOS. DolphiniOS ships Metal and also Vulkan via MoltenVK, pinned at 1.2.8 because of a bug in later versions. **Use Metal.** Graphics is solved. The CPU is the limit.

## 3. Existing iOS apps and how they get JIT
- **DolphiniOS:** sideload only. On iOS 26 it needs StikDebug 2.3.0+ (Oct 2025), because Xcode can no longer enable JIT on TXM devices (A15+/M2+). Betas in June 2026 fixed iOS 26.6 and the iOS 27 beta.
- **iCube** (Provenance's fork, renamed Sept 2025): sideload only (SideStore, AltStore, Sideloadly, TrollStore). On iOS 26 it gets JIT through TXM with a debugger attached.
- **Provenance's App Store update** with jitless GC/Wii sat 42+ days with no review decision (mjtsai, 2025-08-21). I found nothing newer.
- **Apple has never approved a GC/Wii emulator.** The April 2024 change to guideline 4.7 allowed retro emulators and game downloads but kept the JIT ban. Apple denied Dolphin's DMA request for JIT (April 2024).

## 4. EU / DMA
**No JIT path exists for emulators.** Only alternative browser engines get JIT entitlements. Apple refused to notarise UTM for EU marketplaces under rule 2.5.2 and said 4.7 "only applies to App Store apps" (June 2024). It approved UTM SE only once it was JIT-less. Delta ships without JIT on AltStore PAL. Apple also denied iSH's JIT request. In spring 2026 the FSFE reported 56 interoperability requests ignored. AltStore PAL gets you no JIT: only debugger-attach sideloading does.

## 5. Other speed routes without JIT
- **Threaded / tail-call interpreter:** this is iCube's "engine 5". It uses direct-threaded dispatch, tail calls between handlers, fused compare-and-branch, PGO and an inline block-link cache (92% hit rate on Wind Waker). Its IR tier was ~1.7x slower and was dropped. UTM SE's QEMU TCTI uses the same technique and is precedent for App Store approval.
- **On-device AOT** is impossible, because iOS won't make newly generated code executable.
- **Static recompilation:** projects exist, including DolRecomp (GC/Wii PPC→C), gcrecomp, Ring Out and an Eternal Darkness port (active 2026-10-24). Each one is per-game hand work, and the output is derived from a copyrighted game, so none of it can ship in an app.
- **Allowed middle ground:** a saved, pre-decoded block cache (data, not code) that the interpreter loads.

## 6. Firmware
GameCube needs no IPL: Dolphin HLE-boots the apploader. Dolphin also ships a free reverse-engineered DSP ROM and Apache-2.0 fonts. Wii disc games run on HLE IOS, so no NAND is needed. NAND is only for channels, WiiWare and Virtual Console. **Red flag:** Dolphin hard-codes Nintendo's Wii common key (`Source/Core/Core/IOS/IOSC.cpp` ~L579). In a paid App Store binary that invites a Nintendo/DMCA complaint. A GameCube-only build avoids the problem, because GC discs aren't encrypted.

## 7. Licence
Dolphin has been GPLv2-or-later since 2015, so GPLv3 is fine. Its LICENSES/ folder covers GPL-2.0+, BSD-3, MIT and CC0. The bundled third-party code includes mGBA (MPL-2.0), Qt and FFmpeg/OpenAL (LGPL; none needed on iOS), plus mbedTLS and the fonts (Apache-2.0, which is GPLv3-compatible). I found nothing blocking. It still needs the usual Fable licence review.

## Verdict
- **App Store (realistic):** GameCube only, jitless, Metal, with a threaded interpreter. Label it "experimental" and publish a per-game speed list. My extrapolation, not a measurement: heavy 3D games (Wind Waker class) will probably run at 50–70% on current phones. Expect full speed only on light games or with speed hacks. App Review risk is real, given that Provenance's update stalled. Leave Wii out.
- **Sideload / EU only:** full-speed GC/Wii needs JIT, which only debugger attach (StikDebug/SideStore) provides. AltStore PAL doesn't help. DolphiniOS and iCube already offer this for free.
- **Differentiator?** Not at full speed, and possibly never. Treat it as a post-v1 extra, not the headline.

**First experiment (1–2 days):** build Dolphin's Cached Interpreter with Metal for iOS, starting from DolphiniOS 5.0.0b6, and measure emulation speed (%) on Gordon's newest device. Per CLAUDE.md, run it on GC homebrew (needs Gordon's approval) or on Gordon's own discs, with Gordon running them himself. If heavy 3D stays under 60%, decide whether weeks of iCube-style threaded-interpreter work are worth it.

Sources: github.com/dolphin-emu/dolphin/pull/12723; dolphin-emu.org/blog/2024/09/04/dolphin-progress-report-release-2407-2409; github.com/OatmealDome/dolphin-ios/releases; oatmealdome.me/blog/why-dolphin-isnt-coming-to-the-app-store; heldgames.com/guides/icube-gamecube-wii-iphone-jitless; nintendowire.com/news/2026/09/21/wii-and-gamecube-games-now-playable-at-60-fps-on-ios-devices-without-jit; mjtsai.com/blog/?p=48998; macrumors.com/2024/04/05/app-store-guidelines-emulators-music-app-links; mjtsai.com/blog/2024/06/14/utm-blocked-outside-app-store-via-notarization; ish.app/blog/ish-jit-and-eu; news.ycombinator.com/item?id=47847124 (FSFE); github.com/ExpansionPak/DolRecomp; Dolphin repo LICENSES/, Externals/licenses.md, Data/Sys/GC/font-licenses.txt.
