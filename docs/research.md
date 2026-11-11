# Duo Emulator: research brief

Owner: Gordon Shepherd (IQ Labs). Compiled 2026-11-10/11 for a Duo-first, multi-system retro emulator (Swift 6, SwiftUI, Metal, iOS 26+), also targeting ordinary iPhone and iPad. Price model undecided.

Conventions: every factual claim carries a URL. "UNVERIFIED" means I could not confirm it from a primary source during this session. Opinions and engineering recommendations are labelled as such. No ROMs, BIOS files or emulator source were downloaded; licence texts were read as web pages, and repository sizes and licence identifiers were taken from GitHub's repository metadata (the `size` field, which is the repository's on-disk git size, not the size of a source checkout).

---

## 1. App Store rules

### 1.1 Version read

I fetched https://developer.apple.com/app-store/review/guidelines/ on 2026-11-10. The page itself shows no "last updated" date. Apple's most recent announced revision is 16 October 2026 (https://developer.apple.com/news?id=vvzx6cul; coverage at https://9to5mac.com/2026/10/16/apples-new-app-store-rules-crack-down-on-ai-nudification-and-bait-and-switch-apps/), preceded by a June 2026 revision on low-quality apps (https://macrumors.com/2026/06/09/app-store-guidelines-low-quality-apps/). I therefore treat the text below as the 16 October 2026 version, but that attribution is inferred, not stated on the page.

### 1.2 Verbatim quotes

**Guideline 4.7 (Mini apps, mini games, streaming games, chatbots, plug-ins, and game emulators)**

> Apps may offer certain software that is not embedded in the binary, specifically HTML5 and JavaScript mini apps and mini games, streaming games, chatbots, and plug-ins. Additionally, retro game console and PC emulator apps can offer to download games. You are responsible for all such software offered in your app, including ensuring that such software complies with these Guidelines and all applicable laws. Software that does not comply with one or more guidelines will lead to the rejection of your app. You must also ensure that the software adheres to the additional rules that follow in 4.7.1 through 4.7.5. These additional rules are important to preserve the experience that App Store customers expect, and to help ensure user safety.

**4.7.1** Software offered in apps under this rule must:
> - follow all privacy guidelines, including but not limited to the rules set forth in Guideline 5.1 concerning collection, use, and sharing of data, and sensitive data (such as health and personal data from kids);
> - include a method for filtering objectionable material, a mechanism to report content and timely responses to concerns, and the ability to block abusive users; and
> - follow Guideline 3.1 in order to offer digital goods or services to end users.

**4.7.2** Your app may not extend or expose native platform APIs or technologies to the software without prior permission from Apple.

**4.7.3** Your app may not share data or privacy permissions to any individual software offered in your app without explicit user consent in each instance.

**4.7.4** You must provide an index of software and metadata available in your app. It must include universal links that lead to all of the software offered in your app.

**4.7.5** Your app must provide a way for users to identify software that exceeds the app's age rating, and use an age restriction mechanism based on verified or declared age to limit access by underage users.

**2.5.2**
> Apps should be self-contained in their bundles, and may not read or write data outside the designated container area, nor may they download, install, or execute code which introduces or changes features or functionality of the app, including other apps. Educational apps designed to teach, develop, or allow students to test executable code may, in limited circumstances, download code provided that such code is not used for other purposes. Such apps must make the source code provided by the app completely viewable and editable by the user.

**4.1 Copycats**
> (a) Come up with your own ideas. We know you have them, so make yours come to life. Don't simply copy the latest popular app on the App Store, or make some minor changes to another app's name or UI and pass it off as your own. In addition to risking an intellectual property infringement claim, it makes the App Store harder to navigate and just isn't fair to your fellow developers.
> (b) Submitting apps which impersonate other apps or services is considered a violation of the Developer Code of Conduct and may result in removal from the Apple Developer Program.
> (c) You cannot use another developer's icon, brand, or product name in your app's icon or name, without approval from the developer.

**5.2.1 Generally**
> Don't use protected third-party material such as trademarks, copyrighted works, or patented ideas in your app without permission, and don't include misleading, false, or copycat representations, names, or metadata in your app bundle or developer name. Apps should be submitted by the person or legal entity that owns or has licensed the intellectual property and other relevant rights.

**5.2.2 Third-Party Sites/Services**
> If your app uses, accesses, monetizes access to, or displays content from a third-party service, ensure that you are specifically permitted to do so under the service's terms of use. Authorization must be provided upon request.

(All quotes from https://developer.apple.com/app-store/review/guidelines/, fetched 2026-11-10.)

### 1.3 What this means for us

- **Emulators are allowed; the binary must be the emulator only.** 4.7 permits "retro game console and PC emulator apps" and lets them "offer to download games". The moment we offer *any* downloadable game, 4.7.1–4.7.5 apply in full: content filtering and reporting, an index with universal links (4.7.4), and age gating based on verified or declared age (4.7.5). Recommendation: v1 offers **no in-app game downloads at all**. User-supplied files only, imported through the Files picker, AirDrop or "Open in". This keeps us out of 4.7.1–4.7.5 entirely.
- **No bundled or linked commercial ROMs.** 5.2.1 forbids using copyrighted works without permission. Linking to ROM sites would also put us in "you are responsible for all such software" territory. If we ever ship playable content in the bundle, it must be homebrew whose licence permits redistribution (see section 6), and ideally commissioned or written in-house.
- **No BIOS files.** BIOS and firmware images are copyrighted code; the same 5.2.1 reasoning applies. This favours systems whose good emulators need no BIOS (NES, SNES, GB/GBC, Mega Drive, PC Engine HuCard, 2600) or ship a high-level replacement BIOS (mGBA has an HLE BIOS for GBA, per its README feature list at https://github.com/mgba-emu/mgba — UNVERIFIED in this session's fetch, which did not quote that line). PS1 and DS need user-supplied BIOS for best compatibility; they are out of scope for v1 anyway.
- **No trade dress.** 4.1(c) and 5.2.1: no console logos, no controller artwork that copies Nintendo/Sega/Sony industrial design, no console names in the app name or icon. Plain-text system names in the description with a non-affiliation disclaimer appear to be the accepted norm (see 1.4).
- **Downloaded code (2.5.2).** Cores must be compiled into the binary. We cannot download new cores, shaders written as executable code, or Lua scripts that "introduce or change features". ROMs are treated as content under 4.7, not as code; Apple's acceptance of Delta and others confirms this in practice.
- **No JIT.** App Store apps cannot generate executable code at runtime; PPSSPP's App Store build notes that "third-party apps lack support for JIT" (https://9to5mac.com/2024/05/16/ppsspp-ios-app-store/), and Heise noted the same for Folium (https://heise.de/en/news/Nintendo-3DS-emulator-in-the-App-Store-but-for-how-much-longer-9750292.html). See section 5.
- **Do not clone.** iGBA was removed under 4.3 (spam) and 5.2 (copyright) because it was a re-skinned copy of GBA4iOS with ads (https://www.macrumors.com/2024/04/15/apple-further-explains-igba-removal/). Our UI, skins and name must be our own.

### 1.4 How shipping emulators name systems

| App | Store name | How systems are named | Disclaimer | Price model |
|---|---|---|---|---|
| Delta | "Delta - Game Emulator" | Full plain-text names in description: "Nintendo Entertainment System", "Super Nintendo Entertainment System", "Nintendo 64", "Game Boy (Color)", "Game Boy Advance", "Nintendo DS", "Sega Genesis" | "Delta is in no way affiliated with Nintendo", plus trademark notice | Free, IAP; 4.8 from 28K ratings (https://apps.apple.com/us/app/delta-game-emulator/id1048524688) |
| RetroArch | "RetroArch", subtitle "A frontend for emulators" | Long list in libretro style, e.g. "Nintendo - NES / Famicom", "Sony - PlayStation" | "RetroArch and Libretro are in no way affiliated with Nintendo" | Free; 4.3 from 1.9K (https://apps.apple.com/us/app/retroarch/id6499539433) |
| Provenance | "Provenance App" | Grouped by manufacturer (Atari, Nintendo, Sega, Sony, SNK, NEC...) | None about ROMs/BIOS visible | Free, "Provenance Plus" IAP $3.99/$39.99/$99.99; 3.3 from 755 (https://apps.apple.com/us/app/provenance-app/id1596862805) |
| Gamma | "Gamma - PS 1 Game Emulator" | "PS 1" in the title; "PlayStation(tm) 1" in description | Not affiliated with Sony, PPSSPP, Delta, Folium or RetroArch; Sony trademark notices | Free with ads, $4.99 remove-ads; 4.8 from 11K (https://apps.apple.com/us/app/gamma-game-emulator/id6499106870) |
| Manic EMU | "Manic EMU - Game Emulator", subtitle "Retro GBA NDS PSP 3DS N64" | Brand names with abbreviations, e.g. "Nintendo 3DS (3DS)", "PlayStation Portable (PSP)" | "The app does not include games, BIOS, or game data"; not affiliated with any console maker | Free, subscription $0.99/mo, $4.99/yr, $9.99 lifetime; 4.7 from 17K (https://apps.apple.com/us/app/manic-emu-game-emulator/id6743335790) |
| Folium | "Folium" | GBA, 3DS, DS; later GB/GBC, NES, SNES, PS1, Genesis per a Japanese listing mirror | "does not provide any games or system files" | Paid: $4.99 US, £2.99 UK (https://apps.apple.com/us/app/folium/id6498623389; regional prices UNVERIFIED as of today) |
| SameBoy | "SameBoy" | GB, GBC, Super Game Boy | — | Free, supporter IAP (https://timeextension.com/news/2024/05/worlds-most-accurate-game-boy-emulator-sameboy-launches-on-ios-app-store) |
| PPSSPP | "PPSSPP" plus "PPSSPP Gold" | PSP | — | Free, Gold $4.99 (https://9to5mac.com/2024/05/16/ppsspp-ios-app-store/) |

Observations:
- **Nobody I checked uses console logos on the store listing.** I did not inspect every screenshot set, so treat "no logos in screenshots" as UNVERIFIED.
- **App names mostly avoid console brands.** Exceptions such as Gamma ("PS 1") and Manic's subtitle ("GBA NDS PSP 3DS N64") use abbreviations rather than full trademarks and have survived review. This is a risk others have accepted, not a safe harbour. Recommendation: neutral app name, no console abbreviations in name or subtitle, full plain-text system names only in the description, with a non-affiliation and trademark line modelled on Delta's.
- Several apps advertise **RetroAchievements**, **iCloud/Drive/Dropbox sync**, **skins**, **shaders** and **controller support** as headline features (Manic EMU, Gamma listings above).

### 1.5 Known removals, rejections and enforcement

- **iGBA (April 2024):** approved, then removed by Apple within days for 4.3/5.2; it copied Riley Testut's GBA4iOS and added ads. Apple said it had approved the functionality before learning it was a copy (https://www.macrumors.com/2024/04/15/apple-removes-igba-from-app-store, https://www.mactrast.com/2024/04/apple-explains-why-it-removed-game-boy-emulator-igba-from-app-store/). Lesson: originality of code and UI matters as much as ROM policy. Also, its listing declared location and identifier tracking, which drew criticism (https://www.iphoneincanada.ca/2024/04/15/game-boy-emulator-igba-removed-app-store/).
- **Bimmy (April 2024):** the first NES emulator approved under the new rules, briefly $0.99 and then free; the developer pulled it himself "out of fear" of Nintendo, with no action from Apple or Nintendo (https://timeextension.com/news/2024/04/iphone-nes-emulator-pulled-from-app-store-out-of-fear, https://appleinsider.com/articles/24/04/16/fear-of-nintendos-wrath-is-keeping-emulators-off-of-the-app-store). Lesson: the legal risk is perception and chilling effect more than enforcement history.
- **Nintendo DMCA against App Store emulators:** I found **no** report of a Nintendo DMCA notice against an App Store retro emulator. Nintendo's actions have targeted Switch emulators on GitHub (8,535 repos in 2024; 401 in 2026) and the iOS Switch emulator Pomelo via GitHub, not the App Store (https://www.engadget.com/nintendo-blitzes-github-with-over-8000-emulator-related-dmca-takedowns-200021877.html, https://godisageek.com/2026/08/nintendo-401-switch-emulator-repos-dmca/, https://torrentfreak.com/nintendo-targets-pomelo-yuzu-based-ios-switch-emu-faces-circumvention-squeeze-241115/). Nintendo's legal theory rests on circumvention of encryption (Switch, 3DS), which does not apply to unencrypted 8- and 16-bit cartridge systems (same TorrentFreak source). Historical precedent: GBA4iOS was shut down after a Nintendo DMCA in 2014 (https://www.macrumors.com/2014/05/14/gba4ios-shut-down-nintendo/), but that was an enterprise-certificate sideload site, not the App Store.
- **Lessons for us:** no current-generation or encrypted systems; no BIOS; no ROM links; no Nintendo/Sega/Sony artwork; original code and UI; no ads that look like a cash-grab clone.

### 1.6 EU and Japan

- **EU:** Delta launched in the EU through AltStore PAL (an Apple-approved alternative marketplace under the DMA) on 17 April 2024, the day before its worldwide App Store release, which initially excluded the EU (https://www.macrumors.com/2024/04/17/altstore-eu-alternative-app-marketplace/, https://www.ghacks.net/2024/04/18/delta-emulator-is-now-available-on-the-ios-app-store-but-not-for-eu-users/). Delta is now on the App Store with the "An AltStore app" label (Delta listing above). Alternative marketplaces still require Apple notarisation; whether marketplace apps can use JIT is UNVERIFIED.
- **Japan:** with iOS 26.2 (December 2025), Apple complied with the Mobile Software Competition Act, allowing Apple-authorised alternative marketplaces and alternative payments in Japan (https://www.apple.com/sg/newsroom/2025/12/apple-announces-changes-to-ios-in-japan). The June 2026 guidelines generalised alternative-distribution wording to "some markets" (https://conductatlas.com/change/2026-06-09-apple-apple-app-store-review-guidelines-2759/). Japan is Nintendo's home jurisdiction; I found no Japan-specific emulator ban in the guidelines. Recommendation: no special handling, but consider legal advice before marketing in Japan.

---

## 2. Core licensing

### 2.1 The GPL and the App Store

- **FSF position (2010–2011).** The FSF argued in May 2010 (GNU Go case) that Apple's App Store Terms of Service "Usage Rules" impose additional restrictions on recipients, which GPLv2 section 6 forbids, so GPL software cannot be distributed through the App Store (https://www.fsf.org/blogs/licensing/more-about-the-app-store-gpl-enforcement). In January 2011 Apple removed VLC after VLC copyright holder Rémi Denis-Courmont complained (https://cdm.link/2011/01/as-apple-pulls-gpl-licensed-vlc-the-developers-version-of-events-what-it-means-for-free-video/, https://www.engadget.com/2011-01-09-the-gpl-the-app-store-and-you.html). Others in VideoLAN disagreed with his reading; the conflict has never been tested in court (same sources). VLC later returned after relicensing its core libraries to LGPL/MPL (UNVERIFIED from a primary source in this session).
- **Why GPL emulators ship anyway.** The GPL is enforced by copyright holders. Where the person shipping the app is the copyright holder (Riley Testut's Delta is AGPLv3, https://github.com/rileytestut/Delta), or where core authors tolerate App Store distribution, nobody with standing complains. Delta itself ships third-party cores: Nestopia, Snes9x, mupen64plus, Gambatte, visualboyadvance-m, melonDS and Genesis Plus GX (same Delta README). Whether each of those authors has given explicit consent is UNVERIFIED; it may simply be tolerance.
- **Risk for us.** IQ Labs would be a third party shipping someone else's GPL code, possibly in a paid, closed-source app. Two consequences: (1) any single copyright holder in a GPL core could file a takedown, as Denis-Courmont did with VLC; and (2) linking a GPL core into our binary makes the combined app a derivative work, so we would have to release the *entire app's* source under the GPL (and AGPL/GPLv3 add further obligations). GPL does not forbid charging money, but the source must be offered. **Recommendation: no GPL code in a closed-source app without written permission from every copyright holder.**
- **Non-commercial licences** (Snes9x, Genesis Plus GX, PicoDrive) are a separate and harder block: they forbid sale or "commercial product or activity" outright. A paid app, an app with IAP, or arguably an ad-supported app is out without permission.

### 2.2 Candidate core table

Repository sizes are GitHub's metadata `size` (git storage, rounded down to MB), fetched with the GitHub API on 2026-11-10; licence identifiers are GitHub's SPDX detection unless noted, cross-checked against libretro's core-info `license` field (https://github.com/libretro/libretro-core-info). Accuracy and performance remarks are my engineering judgement unless cited.

| Core | System(s) | Licence (verified where noted) | Repo size | Accuracy / iPhone perf (judgement) | Free app | Paid app |
|---|---|---|---|---|---|---|
| **SameBoy** | GB, GBC, SGB | Expat (MIT) for core, verified at https://raw.githubusercontent.com/LIJI32/SameBoy/master/LICENSE. **Exception: the `iOS` directory is excluded and "A written permission from Lior Halphon is required to distribute copies or substantial portions in a digital marketplace, such as Apple's App Store."** `HexFiend` dir also excluded | 24 MB (LIJI32/SameBoy) | Best-in-class accuracy; trivially fast on any A-series chip | OK (core only, not iOS frontend) | OK (core only), keep notice |
| **mGBA** | GBA, GB, GBC | MPL-2.0, verified: "It is distributed under the Mozilla Public License version 2.0" (https://github.com/mgba-emu/mgba). File-level copyleft: modified mGBA files must be published; our own files stay closed. README invites commercial licensing enquiries | 59 MB | High accuracy; GBA comfortable on iPhone without JIT (judgement) | OK | OK (publish changes to mGBA files) |
| **bsnes** | SNES | **GPLv3 or later**, verified at https://raw.githubusercontent.com/bsnes-emu/bsnes/master/LICENSE.txt. Only libco, nall, ruby and hiro are ISC-style. **The brief's assumption "bsnes ISC" is wrong for current bsnes.** | 67 MB | Cycle-accurate; heavy but fine on recent iPhones (judgement, UNVERIFIED benchmarks) | Needs GPL source release | Needs permission (author near/byuu has died; permission practically unobtainable — UNVERIFIED that no successor holds rights) |
| **ares** | NES, SNES, GB/GBC, GBA, MD/SMS/GG/MCD, PCE, NGP, WS, N64, PS1, others | ISC-style permissive for ares itself, verified at https://raw.githubusercontent.com/ares-emulator/ares/master/LICENSE; bundled third-party parts are BSD-3 (MAME-derived), zlib, Apache-2.0 (MoltenVK), MPL-2.0 (librashader), MIT, public domain | 183 MB | Accuracy-first; heavy. N64/PS1 without JIT likely too slow on phone (judgement) | OK | OK (attribution, MPL for librashader files) |
| **Snes9x** | SNES | Custom non-commercial: "for non-commercial purposes"; "Commercial users should seek permission"; some contributions "Under no circumstances will commercial rights be given" (https://raw.githubusercontent.com/snes9xgit/snes9x/master/LICENSE) | 19 MB | Good, very fast | OK if genuinely non-commercial (no IAP/ads arguable) | **No** (some code explicitly never commercial) |
| **Genesis Plus GX** | MD, SMS, GG, MCD, SG-1000 | Custom: "Redistributions may not be sold, nor may they be used in a commercial product or activity"; modified redistributions must include complete source (https://raw.githubusercontent.com/ekeeke/Genesis-Plus-GX/master/LICENSE.txt) | 271 MB (includes console port assets) | Very good; fast | OK if non-commercial, must ship source of modifications | **No** without permission |
| **PicoDrive** | MD, SMS, GG, MCD, 32X | MAME-style non-commercial: "may not be sold, nor may they be used in a commercial product or activity" (https://raw.githubusercontent.com/notaz/picodrive/master/COPYING) | 10 MB | Fast, less accurate; 32X is unique selling point | OK if non-commercial | **No** without permission |
| **BlastEm** | MD | GPLv3 (libretro info; libretro/blastem repo SPDX GPL-3.0) | 4 MB (libretro mirror) | Very accurate; heavier | GPL release | Needs permission |
| **Mesen / Mesen2 → MesenCE** | NES, SNES, GB, GBA, PCE, SMS/GG, WS | GPLv3; Mesen2 archived 4 Jun 2026, development moved to nesdev-org/MesenCE (https://github.com/SourMesen/Mesen2) | 26 MB (Mesen2), 28 MB (MesenCE) | NES accuracy reference-grade; C++ with heavy desktop UI | GPL release | Needs permission |
| **Gambatte** | GB, GBC | GPLv2 (libretro/gambatte-libretro SPDX; libretro info) | 5 MB (libretro) | Very accurate | GPL release | Needs permission |
| **Nestopia UE** | NES | GPLv2 (0ldsk00l/nestopia SPDX) | 6 MB | Accurate, fast | GPL release | Needs permission |
| **FCEUX** | NES | GPLv2 (TASEmulators/fceux SPDX) | 122 MB | Good, debugger-rich | GPL release | Needs permission |
| **QuickNES** | NES | **Conflict**: libretro info says LGPLv2.1+, but libretro/QuickNES_Core's LICENSE file is GPLv2 (https://github.com/libretro/QuickNES_Core). Treat as GPLv2 | 1 MB | Fast, less accurate | GPL release | Needs permission |
| **puNES** | NES | GPLv2 (punesemu/puNES SPDX) | 102 MB | Accurate | GPL release | Needs permission |
| **Gearboy / Gearsystem / Geargrafx** | GB/GBC; SMS/GG/SG-1000; PCE | GPLv3 (drhelius repos SPDX) | 83 / 64 / 22 MB | Good, single active author (so permission is plausible to ask for) | GPL release | Needs permission |
| **SMS Plus GX (libretro)** | SMS, GG | "GPLv2 or later"; YM core from CrabEmu GPLv2, Z80 core BSD (https://github.com/libretro/smsplus-gx) | 1 MB | Good, fast | GPL release | Needs permission |
| **Beetle (Mednafen) PCE Fast / NGP / WSwan / PSX / SuperGrafx** | PCE, NGP, WS, PS1 | GPLv2 (libretro repos SPDX) | 27 / 24 / 23 / 110 / 25 MB | Accurate; PSX heavy | GPL release | Needs permission (many Mednafen contributors) |
| **melonDS** | DS | GPLv3 (melonDS-emu/melonDS SPDX) | 12 MB | Good; needs firmware/BIOS for best results; no JIT on App Store | GPL release | Needs permission |
| **DeSmuME** | DS | GPLv2 (TASEmulators/desmume SPDX) | 98 MB | Older, slower | GPL release | Needs permission |
| **PPSSPP** | PSP | GPLv2 (LICENSE.TXT, https://raw.githubusercontent.com/hrydgard/ppsspp/master/LICENSE.TXT; "or later" not stated in the file itself) | 378 MB | Out of scope (PSP) | GPL release | Needs permission |
| **Mupen64Plus / Mupen64Plus-Next** | N64 | GPLv2 (libretro info) | 14 MB (core) | Needs dynarec for full speed; interpreter-only on App Store is borderline (see §5) | GPL release | Needs permission |
| **ParaLLEl N64** | N64 | GPLv2 (libretro info) | 55 MB | Vulkan/LLE RDP; heavy | GPL release | Needs permission |
| **Flycast** | Dreamcast | GPLv2 (flyinghead/flycast SPDX) | 117 MB | JIT-dependent; out of scope | GPL release | Needs permission |
| **Stella** | Atari 2600 | GPLv2 (stella-emu/stella SPDX) | 65 MB | Reference 2600 emulator | GPL release | Needs permission |
| **Handy** | Atari Lynx | zlib per libretro info and SourceForge; one WiiBrew source says GPL (https://sourceforge.net/projects/handy/, https://emulation.gametechwiki.com/index.php/Atari_Lynx) — partly UNVERIFIED | 1 MB | Fine | OK (zlib) | OK (zlib) if confirmed |
| **ProSystem** | Atari 7800 | GPLv2 (libretro info) | <1 MB | Fine | GPL release | Needs permission |
| **bsnes-jg** (Jolly Good) | SNES | Derived from bsnes, so GPLv3 assumed — UNVERIFIED (jgemu repo not found on GitHub) | — | As bsnes | GPL release | Needs permission |
| **DuckStation** | PS1 | **CC-BY-NC-ND**: no modified versions may be published at all (https://github.com/stenzek/duckstation) | 197 MB | Excellent, but licence forbids porting | **No** | **No** |
| **PCSX ReARMed / SwanStation** | PS1 | GPLv2 / GPLv3 (libretro SPDX) | 20 / 60 MB | PCSX ReARMed has ARM dynarec; interpreter on App Store | GPL release | Needs permission |

Summary of permissive heavyweights (verified this session): **SameBoy core (MIT, but not its iOS frontend)**, **mGBA (MPL-2.0)**, **ares (ISC-style)**. **bsnes is GPLv3, not ISC** (only its libraries libco/nall/ruby/hiro are ISC). higan's licence was not checked (UNVERIFIED; historically GPLv3).

### 2.3 Per-system recommendation

Assumes a closed-source app that may be paid. "In-house" means written from scratch in Swift (with a C hot loop only if profiling demands it).

| System | Recommendation | Reason |
|---|---|---|
| NES | **In-house** (current plan) | Well documented (nesdev wiki), excellent open test ROMs (section 6), every mature core is GPL. Mapper coverage is the long tail: NROM, MMC1, UxROM, CNROM, MMC3, AxROM cover most of the library. |
| GB / GBC | **In-house** (current plan); SameBoy core (MIT) as a reference oracle and fallback | Superb MIT test suites (Mooneye, acid2, Mealybug). SameBoy core is MIT, so it could be shipped if in-house slips, but **not** its iOS frontend code. |
| GBA | **Licensed: mGBA (MPL-2.0)** | Writing a GBA core in-house is a large job (ARM7TDMI, PPU, DMA timing). MPL-2.0 lets us ship closed source; we publish only modified mGBA files. Consider emailing endrift as the README invites commercial enquiries. |
| SNES | **Licensed: ares SNES core (ISC-style)**, or in-house later | Snes9x is non-commercial; bsnes is GPLv3. ares is the only permissive accurate option; extracting just its SNES core plus nall/libco is feasible but non-trivial C++. Performance on phone needs measurement (UNVERIFIED). |
| Mega Drive / Genesis + SMS / GG | **Licensed: ares MD/SMS/GG cores**, or in-house SMS/GG (simple Z80 system) | GPGX and PicoDrive forbid commercial use; BlastEm, Gearsystem and SMS Plus GX are GPL. SMS/GG are small enough to write in-house after NES/GB. Alternatively ask drhelius (Gearsystem, single author) for a commercial licence. |
| PC Engine | **Licensed: ares PCE core**, or ask drhelius for Geargrafx | Beetle PCE is GPL with many authors. HuCard-only first; CD needs a BIOS (System Card), so skip CD. |
| Atari 2600 | **In-house** (optional, later) | Stella is GPL. 2600 is small but notoriously timing-sensitive; good portfolio piece, low demand. |
| Neo Geo Pocket | **ares NGP core** or skip | Beetle NGP and RACE are GPL. Low demand. ares NGP needs a BIOS (UNVERIFIED); if so, skip. |
| WonderSwan | **ares WS core** or skip | Beetle WSwan GPL. Low demand; ares WS may need boot ROM (UNVERIFIED). |
| N64 | **Skip** | All mature cores GPL; full speed generally relies on a dynarec, which is unavailable on the App Store (see §5). |
| DS | **Skip** | melonDS/DeSmuME GPL; best results need firmware/BIOS; dual screens are attractive on Duo but legal and BIOS issues dominate. Revisit only with a melonDS licence from its authors. |
| PS1 | **Skip** | BIOS required for good compatibility; DuckStation is CC-BY-NC-ND; others GPL. |

---

## 3. How existing iOS emulators handle features

**Library and box art.**
- Delta and Provenance both show cover art automatically; Delta credits OpenVGDB in historical builds (UNVERIFIED). OpenEmu credits OpenVGDB for "cover art and game data", and its box art is reportedly links to GameFAQs images (https://wiki.gnome.org/Design/Playground/Games/Metadata). The OpenVGDB repository at https://github.com/OpenVGDB/OpenVGDB shows no licence and a single commit; its data licence is UNVERIFIED.
- libretro's metadata database (libretro/libretro-database) is CC-BY-SA-4.0 per GitHub metadata (836 MB). **Share-alike would apply to a redistributed derivative database**; using it to identify hashes at runtime is arguably fine but should be checked.
- libretro-thumbnails carries no image licence; its README states the art "originates from the work of each respective game's developers and publishers" (https://github.com/libretro-thumbnails/libretro-thumbnails). **Shipping or hot-linking that art is a 5.2.1 risk.** Recommendation: v1 uses generated cover cards (title text, system colour, first-frame screenshot after first play) and lets users pick their own image.

**Import.** Delta, Provenance and Manic offer the Files picker; Manic adds cloud import from Google Drive, Dropbox and OneDrive (Manic listing above); Provenance mentions a "ROM importer" and historically a built-in web server for uploads (https://github.com/Provenance-Emu/Provenance/issues/286). Delta users ask for .7z support (https://github.com/rileytestut/Delta/issues/248). Recommendation: UIDocumentPicker (multi-select, folders), "Open in"/AirDrop via document types, zip support from day one, a watched app-container "Inbox" folder visible in Files.

**Saves and sync.** Delta: save states with locking and auto-backups; Delta Sync to Google Drive and Dropbox, **no iCloud** (https://github.com/rileytestut/Delta; user discussion at https://axebps-redlib.hf.space/r/Delta_Emulator/comments/1gxo3cp/why_is_there_no_icloud_option_here). Manic and Provenance advertise iCloud sync (listings above); Gamma uses Google Drive and Dropbox. Recommendation: battery saves as standard `.sav` files in a Files-visible folder (portable to other emulators), versioned save states, CloudKit/iCloud Drive sync since we are App Store-only.

**Controllers.** Delta supports PS4/PS5, Xbox and MFi controllers plus Bluetooth keyboards, with per-system, per-controller remapping (Delta README). Lack of remapping is a top Provenance complaint (App Store review quoted above; https://github.com/Provenance-Emu/Provenance/issues/56). Use Apple's GameController framework (GCController, GCKeyboard; https://developer.apple.com/documentation/gamecontroller).

**Skins.** Delta's `.deltaskin` is a renamed ZIP containing `info.json` plus a PDF (or small/medium/large PNG) per representation. Keys include `name`, `identifier`, `gameTypeIdentifier`, `representations` (iphone: `standard`/`edgeToEdge`; ipad: `standard`/`splitView`), per-orientation `assets`, `items` (inputs + frame + `extendedEdges`), `screens` (input/output frames, CoreImage filters), `mappingSize` and `translucent` (community documentation at https://noah978.gitbook.io/delta-docs/skins — third-party, not Apple or Testut). Community sites: Skins4Delta, delta-skins.github.io, Circa's Delta Skins, LitRitt Designs (same source). Delta has added animated skins and screen repositioning (https://retrododo.com/delta-ios-emulation-app-is-getting-animated-skins-screen-repositioning/). Recommendation: our own JSON+PDF format with an explicit `duo` representation for each pose (table, book, flat) and both displays. Importing `.deltaskin` would be a nice compatibility win; the format is a de facto community standard, but copying it exactly brushes against 4.1; implement an importer, not a clone.

**Cheats.** Delta supports per-system formats, e.g. GBA Action Replay, Code Breaker and GameShark, DS Action Replay (Delta README). NES Game Genie patches CPU reads in $8000–$FFFF with an address, replacement value and optional compare value (https://www.nesdev.org/wiki/Game_Genie). Game Boy GameShark codes are 8 hex digits `ttvvaaaa` (type, value, little-endian address) (https://bulbapedia.bulbagarden.net/wiki/Game_Shark); GB Game Genie uses `ABC-DEF-GHI` (https://www.epilogue.co/support/playing-games/cheats; decoding at https://gbdev.gg8.se/wiki/articles/Gamegenie/Shark_Cheats). Manic EMU offers an online cheat library (listing). Recommendation: built-in decoders for Game Genie (NES, GB) and GameShark (GB); no bundled cheat database in v1 (provenance of community cheat lists is unclear).

**Rewind, fast-forward.** Delta has fast-forward via pause menu or mapped button (Delta README); SameBoy iOS has rewind (Time Extension article above). A Delta issue reports audio distortion after stopping fast-forward on iOS 26 (https://github.com/rileytestut/Delta/issues/521): our audio pipeline must handle rate changes cleanly.

**Shaders and filters.** Gamma ships a CRT filter; Manic and Provenance advertise shaders (listings above). Delta skins can specify CoreImage filters per screen (skin docs above).

**Multiplayer and AirPlay.** Manic offers local, LAN, relay multiplayer and AirPlay (listing); Gamma offers local 4-player (listing). Delta AirPlay has a reported bug where the DS lower screen is not shown (Delta App Store review above). GBA link cable is a requested Delta feature (https://github.com/rileytestut/Delta/issues/485), as is nearby multiplayer (https://github.com/rileytestut/Delta/issues/215).

**RetroAchievements.** The single most-upvoted Delta feature request (https://github.com/rileytestut/Delta/issues/196); Manic, Gamma and Provenance advertise it.

**Widgets.** None of the listings I read advertise widgets (UNVERIFIED for screenshots). An opening for us: "continue playing" widget and Live Activity for long sessions.

---

## 4. What users love and hate

Direct Reddit pages could not be fetched (reddit.com blocked to the fetch tool; mirrors returned 403), so Reddit points come from search-result excerpts and are marked accordingly.

**Love**
1. **Simplicity and "just works" design.** Delta is praised for being built for iPhone and for how "you don't really need to mess with settings" (r/EmulationOniOS thread excerpt, https://reddit.birdcat.cafe/r/EmulationOniOS/comments/1c5kxyo/available_ios_emulators_megathread/kzutkbz/?context=3 — excerpt only).
2. **Haptic touch controls.** TouchArcade called Delta's haptics a standout feature (https://toucharcade.com/2024/04/19/toucharcade-game-of-the-week-delta-game-emulator/); 9to5Mac says they give "a tangible sense of a button" (https://9to5mac.com/2024/04/30/these-accessories-will-let-you-maximize-your-delta-emulator-experience/).
3. **Physical controller support.** Recommended by every reviewer for action games (Tom's Guide, https://tomsguide.com/gaming/a-retro-game-emulator-actually-stuck-around-on-ios-today-and-i-tried-it).
4. **No ads, no tracking.** Manic reviewer: "No ads, basically no lag in games" (Manic listing); Bimmy's developer stressed it had no "ads or tracking of any kind" (AppleInsider, above).
5. **Customisation.** "Everything about this emulator is so intuitive and customizable" (Manic review).
6. **Clean UI and responsive controls.** Gamma: "The UI is clean and easy to use ... very responsive with the controls" (Gamma listing).
7. **Skins ecosystem.** Community skin sites exist purely for Delta (skin docs above), and Delta keeps adding skin features (Retro Dodo, above).
8. **RetroAchievements.** Most-reacted Delta request with 41 reactions (issue #196).
9. **Breadth for enthusiasts.** RetroArch is valued for system count; one excerpt says Delta has "nowhere near the amount of emulated consoles" (megathread excerpt above).
10. **Accuracy by name.** SameBoy is marketed and covered as the "World's Most Accurate Game Boy Emulator" (Time Extension headline).
11. **Free with fair one-off unlocks.** PPSSPP Gold at $4.99 one-off; Folium a one-off purchase (9to5Mac; Heise).
12. **Fast-forward and save states** are expected baseline features (Delta README; Manic, Gamma listings).

**Hate**
1. **Intrusive ads.** Gamma: ads "egregiously long, the kind you can't get out of until 2 minutes later" (Gamma listing review, June 2024).
2. **Data collection.** iGBA and Gamma both drew criticism for declaring location/usage tracking (iPhone in Canada; https://retrododo.com/gamma-brings-ps1-emulation-to-iphone-and-ipad/).
3. **Clones and cash-grabs.** iGBA called a ripoff overlaid with ads (MacRumors, above).
4. **No controller remapping.** Provenance: "no convenient way of remapping controller binds" (Provenance review); a long-standing Provenance issue (#56).
5. **Bad screen layouts.** Provenance: "The layout of the screens are god awful" (Provenance review).
6. **Fixed touch-control positions.** Delta reviewer wants to rearrange buttons "anywhere on the screen" (Delta review); Provenance issue #25.
7. **Accidental Start/Select presses** (https://github.com/Provenance-Emu/Provenance/issues/345).
8. **Phantom input and random crashes.** Manic: "it kept making me move even without touching the controls" and crashes "randomly out of nowhere" (Manic reviews).
9. **Outdated cores and slow addition of systems.** Delta "cores are all outdated" (megathread excerpt); issues ask for updated melonDS (#514) and more accurate cores (#388).
10. **RetroArch complexity.** Global versus per-core settings overriding each other (megathread excerpt).
11. **Paywalled basics.** Provenance criticised for paid features that are free in RetroArch (megathread excerpt); Manic uses a subscription (listing).
12. **No iCloud sync in Delta** (r/Delta_Emulator thread, above).
13. **Battery drain**, especially with haptics on (9to5Mac accessories article).
14. **Dynamic Island / notch covering the game** when using a controller (https://github.com/rileytestut/Delta/issues/375).
15. **Audio glitches after fast-forward** on iOS 26 (Delta issue #521); Folium review cites "15-18 FPS with some sound stuttering" (search excerpt of the Folium listing, UNVERIFIED as current).

Product implications (judgement): no ads; no tracking; one-off purchase if paid; remappable everything; movable, resizable touch controls with a guard on Start/Select; clean audio under speed changes; iCloud sync; safe-area-aware layout including Duo hinge; RetroAchievements later (requires their API terms review).

---

## 5. Architecture recommendation

All of this section is engineering recommendation unless a URL is given.

**Core protocol (Swift).**
```swift
protocol EmulatorCore: AnyObject, Sendable {
    static var system: SystemID { get }
    var videoFormat: VideoFormat { get }        // native WxH, pixel format, pixel aspect
    var audioFormat: AudioFormat { get }        // native sample rate, channels
    var nominalFrameRate: Double { get }        // e.g. 60.0988 NES NTSC, 59.7275 GB
    func load(rom: Data, battery: Data?) throws
    func reset(hard: Bool)
    func runFrame(input: InputState, video: VideoSink, audio: AudioSink)
    func batterySave() -> Data?
    func serializeState() throws -> Data        // versioned, see below
    func deserializeState(_ data: Data) throws
    var memoryRegions: [MemoryRegion] { get }   // cheats, RetroAchievements later
}
```
`runFrame` is the only hot call. Video is written into a frontend-owned buffer (no per-frame allocation); audio samples are pushed into a lock-free single-producer/single-consumer ring.

**Threading.** One dedicated emulation thread (a `Thread` with high QoS, not a Swift concurrency task, so it is never cooperatively suspended). The core and its state are confined to that thread; the UI talks to it through a small command queue (pause, save state, load, input). Input is sampled at the start of each frame from an atomic snapshot updated by GameController and touch handlers.

**Pacing.** Two viable models:
- *Audio-clock pacing*: run frames whenever the audio ring falls below a target fill. Robust against stutter, but video frames can judder against a 60/120 Hz display.
- *Display-link pacing with dynamic rate control* (recommended): drive frames from `CAMetalDisplayLink` (https://developer.apple.com/documentation/quartzcore/cametaldisplaylink) at the display's rate, and keep audio stable by nudging the resampling ratio by up to about ±0.5% according to ring-buffer fill, as described in Arntzen's "Dynamic Rate Control for Retro Game Emulators" (https://docs.libretro.com/development/cores/dynamic-rate-control/, PDF copy https://barotto.github.io/libretro-docs/guides/ratecontrol.pdf). On ProMotion displays request 60 Hz (or 120 Hz and run a frame every other tick); for 50 Hz PAL or GB's 59.73 Hz, let DRC absorb the difference.
- Fast-forward: run N frames per tick, drop video, and either drop audio or time-stretch; reset the ring cleanly on exit (Delta issue #521 shows the failure mode).
- Rewind: keep compressed state snapshots every N frames in a ring (delta-compress against the previous snapshot).

**Metal rendering.** Upload the frame to an `MTLTexture` (shared storage on Apple silicon), draw a full-screen quad with **nearest** sampling. Integer scaling by default where it fits, with "fit" and "fill" options; correct pixel aspect ratio (e.g. NES 8:7) as a setting. Optional fragment shaders: scanline/CRT, LCD grid and ghosting for GB/GBA, colour correction for GBC/GBA. Shaders are compiled into the app (2.5.2: no downloaded shader code). On the Duo, render each display independently; the frontend decides which display shows game versus controls per pose.

**Audio.** `AVAudioEngine` with an `AVAudioSourceNode` (https://developer.apple.com/documentation/avfaudio/avaudiosourcenode) pulling from the ring buffer; resample from core rate to hardware rate in the emulation thread (a simple windowed-sinc or a band-limited synth such as blip-buf style is ample for 8-bit systems). The render callback must not allocate, lock or call Swift runtime functions that may lock; keep it in a small C or `@inline(__always)` unsafe-pointer Swift function. Configure `AVAudioSession` category `.playback` with an option to mix with others; handle interruptions and route changes by pausing emulation.

**Save-state format and versioning.** A container with: magic, container version, system ID, core ID, core state version, ROM hash (SHA-1 or CRC32 of the PRG/ROM data), timestamp, thumbnail PNG, then chunked core payload (TLV chunks keyed by component: CPU, PPU, APU, mapper, RAM). Each core owns a migration function from older state versions. Never break old states silently: if migration is impossible, refuse to load with a clear message. Battery saves are kept separately in plain `.sav` so users can move them to other emulators.

**JIT.** Not available to App Store apps (9to5Mac on PPSSPP, Heise on Folium, both above). Even for sideloaded apps on iOS 26, JIT now needs debugger-based workarounds that TXM devices (A15+/M2+) restrict further (https://newreleases.io/project/github/OatmealDome/dolphin-ios/release/v5.0.0b1). Implications: all our cores are interpreters. That is fine for every 8- and 16-bit system and for GBA. N64 interpreters can be borderline at full speed even on fast phones (UNVERIFIED benchmarks); GameCube, PS2 and later are effectively impossible. This aligns with skipping N64/DS/PS1.

**Swift versus C for cores.**
- Swift pros: one language, memory safety, Swift 6 concurrency checking around the core boundary, easier testing.
- Swift risks: ARC retain/release traffic, bounds checks, exclusivity checks and existential dispatch in the hot loop. Mitigations: core state as a `final class` or `~Copyable` struct holding `UnsafeMutableRawPointer`-backed memory; `@inline(__always)` on bus reads and writes; `-Ounchecked` or targeted `withUnsafeMutableBufferPointer` in hot paths; avoid protocols and closures inside the per-cycle loop; switch-based opcode dispatch.
- NES and GB at cycle level need roughly 1.8 M and 4.2 M CPU cycles per second plus PPU dots; well within budget for optimised Swift (judgement). If profiling shows otherwise, move just the CPU/PPU step into a C target and keep everything else in Swift.
- Licensed C/C++ cores (mGBA, ares) sit behind a thin C shim and a Swift adapter implementing `EmulatorCore`.

---

## 6. Homebrew and test ROM wish list (for Gordon to approve later)

Nothing has been downloaded. Sizes are GitHub repository sizes (metadata), which overstate the ROM files themselves. Licences are GitHub SPDX detection plus README checks where noted.

### 6.1 NES test ROMs

| Name | Source | Licence | Approx. size |
|---|---|---|---|
| nestest (kevtris) | listed at https://www.nesdev.org/wiki/Emulator_tests ; archived in https://github.com/christopherpow/nes-test-roms | None stated; freely circulated (UNVERIFIED) | ~24 KB ROM + log (UNVERIFIED) |
| blargg's NES suites (instr_test-v5, instr_timing, cpu_interrupts_v2, ppu_vbl_nmi, ppu_sprite_hit, sprite_overflow_tests, apu_test, oam_read, mmc3_test_2, etc.) | https://www.nesdev.org/wiki/Emulator_tests ; collection repo https://github.com/christopherpow/nes-test-roms | No licence stated on nesdev page or collection repo (UNVERIFIED; personal testing only until clarified) | Collection repo 5.8 MB |
| AccuracyCoin (100thCoin) | https://github.com/100thCoin/AccuracyCoin | MIT (GitHub SPDX) | 3 MB repo |
| Holy Mapperel (tepples/pinobatch) | https://github.com/pinobatch/holy-mapperel | zlib (GitHub SPDX) | 60 KB repo |
| allpads-nes (controller test) | https://github.com/pinobatch/allpads-nes | zlib (GitHub SPDX) | 80 KB repo |
| Zap Ruder (Zapper test) | https://github.com/pinobatch/zap-ruder | Not detected by GitHub (UNVERIFIED) | 110 KB repo |
| 240p Test Suite, NES/GB mini ports | https://github.com/pinobatch/240p-test-mini | GPL-2.0 (GitHub SPDX). Fine for testing; redistribution in our bundle would need GPL compliance for that ROM only | 2.4 MB repo |
| 240p Test Suite (Artemio, other consoles) | https://github.com/ArtemioUrbina/240pTestSuite | Not detected by GitHub; GPL per author (UNVERIFIED) | 91 MB repo |
| Numism (platformer + emulator test) | https://github.com/pinobatch/numism | Apache-2.0 (GitHub SPDX) | 1 MB repo |

### 6.2 Game Boy / Game Boy Color test ROMs

| Name | Source | Licence | Approx. size |
|---|---|---|---|
| Mooneye Test Suite | https://github.com/Gekkio/mooneye-test-suite | MIT (GitHub SPDX) | 0.2 MB repo |
| dmg-acid2 | https://github.com/mattcurrie/dmg-acid2 | MIT (GitHub SPDX) | 1.2 MB repo (ROM 32 KB) |
| cgb-acid2 | https://github.com/mattcurrie/cgb-acid2 | MIT (GitHub SPDX) | 1.5 MB repo (ROM 32 KB) |
| Mealybug Tearoom Tests (PPU mid-scanline) | https://github.com/mattcurrie/mealybug-tearoom-tests | MIT (GitHub SPDX) | 62 MB repo (mostly reference images) |
| SameSuite (LIJI32) | https://github.com/LIJI32/SameSuite | Not detected; LICENSE file exists but was not readable via fetch (UNVERIFIED) | 0.1 MB repo |
| blargg's GB tests (cpu_instrs, instr_timing, mem_timing, dmg_sound, cgb_sound, oam_bug, halt_bug) | collection https://github.com/retrio/gb-test-roms | None stated (UNVERIFIED) | 0.2 MB repo |
| c-sp game-boy-test-roms (pre-built collection of many suites) | https://github.com/c-sp/game-boy-test-roms | MIT for the collection; bundled suites keep their own terms (UNVERIFIED per suite) | 0.2 MB repo (release zip larger) |
| BullyGB | https://github.com/Ashiepaws/BullyGB | MIT (GitHub SPDX) | 70 KB repo |
| scribbltests | https://github.com/Ashiepaws/scribbltests | MIT (GitHub SPDX) | 1 MB repo |

### 6.3 Homebrew games (candidate demo or bundled content)

| Name | System | Source | Licence | Approx. size |
|---|---|---|---|---|
| Tobu Tobu Girl / Tobu Tobu Girl DX | GB / GBC | https://github.com/SimonLarsen/tobutobugirl-dx | Code MIT; all assets CC BY 4.0 (README, verified). **Best candidate for a bundled demo** with attribution | 1.9 MB repo |
| µCity | GBC | https://github.com/AntonioND/ucity | Code GPLv3+, media CC BY-SA 4.0 (README, verified) | 2.1 MB repo |
| Libbet and the Magic Floor | GB | https://github.com/pinobatch/libbet | zlib (GitHub SPDX) | 0.9 MB repo |
| 2048-gb | GB (and SMS) | https://github.com/gb-archive/2048-gb | zlib (GitHub SPDX) | 50 KB repo |
| Petris | GBC / GG | https://github.com/bbbbbr/Petris | Not detected (UNVERIFIED) | 3.9 MB repo |
| Super Tilt Bro | NES | https://github.com/sgadrat/super-tilt-bro | WTFPL (GitHub SPDX) | 5.9 MB repo |
| Nova the Squirrel | NES | https://github.com/NovaSquirrel/NovaTheSquirrel | GPL-3.0 (GitHub SPDX) | 2.7 MB repo |
| Thwaite | NES | https://github.com/pinobatch/thwaite-nes | GPL-3.0 (GitHub SPDX) | 0.3 MB repo |
| Concentration Room | NES | https://github.com/pinobatch/croom-nes | GPL-3.0 (GitHub SPDX) | 0.2 MB repo |
| Alter Ego (Shiru port) | NES | Shiru's software page (https://shiru.untergrund.net/software.shtml) | "Freeware"; licence UNVERIFIED | ~40 KB ROM (UNVERIFIED) |

Notes: MIT/zlib/WTFPL/Apache items can be bundled with attribution. GPL ROMs (Thwaite, Nova, Concentration Room, 240p mini) can be bundled as separate data files if we also offer their source; they do not infect the app because a ROM run by an emulator is data, not linked code (judgement, not legal advice). For a paid closed-source app, prefer Tobu Tobu Girl DX, Libbet, Super Tilt Bro and 2048-gb.

---

## 7. Open questions for Gordon

1. Free or paid? If any non-commercial or GPL code is wanted, the answer must be "free and open source" or "obtain permission".
2. Approve contacting endrift (mGBA) about commercial terms, and drhelius (Gearsystem/Geargrafx) about a non-GPL licence.
3. Approve evaluating ares's SNES/MD cores on an iPhone for speed before committing.
4. Approve the section 6 downloads (test ROMs into a local, gitignored `testroms/` folder only).
5. Consider a short IP-lawyer review of name, icon and listing before submission.
