# Featuring artwork: Relics: Consoles (ready ahead of time; nothing uploaded)

Made 2026-11-18 because the 1 Dec featuring nomination is in. If Apple shortlists the app, a **Promotional Artwork** section
appears in App Store Connect and asks for specific assets at short notice. Upload only what Apple asks for.

**Scene (all original, ours):** a pixel world that sharpens from chunky 8-bit blocks on the left, through 16-bit, to smooth
low-poly on the right. A small wanderer with an ember scarf stands on the hilltop in the middle against a slatted ember sun.
It says "every era of games, one place" with no logos, no copy, and no devices, consoles, controllers or phones (Apple's
promo rules forbid hardware and Apple products), and no game art.

## Apple's spec (help.apple.com/asc/appspromoart, read 2026-11-18)
| Asset | Size | File name |
|---|---|---|
| Universal | 5244 x 2950 | `6833521756_RelicsConsoles_YYYYMMDD_AppStore_Universal.psd` |
| Apps and Games Tabs | 4320 x 1080 | `6833521756_RelicsConsoles_YYYYMMDD_AppStore_AppsGamesWatch.psd` |
| Supporting Imagery (if asked) | 4000 x 4000 | `..._AppStore_SupportingImagery`: 3-5 unaltered screenshots, use `docs/store/shots` |

- Single focus in the Art Safe Area (centre). Background fills the whole canvas. Apps/Games: key content in the upper
  two-thirds of the safe area (the app lockup sits below), so the hero is placed at 47% height there.
- No logos, text, URLs, prices, trademarks, Apple products or other hardware.
- **Format:** Apple's own PSD template at an unchanged size, each element embedded as its own Smart Object (not linked), one
  PSD per asset (or one ZIP of it), under 2 GB.

## Files
- `make_art.py`: generates the layers as SVG (`out/<size>/01-sky ... 08-sparks`, plus `00-composite`). `render.sh`:
  renders them to PNG with headless Chrome (transparent layers). Run both to rebuild. The PNG layers are gitignored.
- `composite-universal.png`, `composite-appsgames.png`: flattened previews (committed).

## When Apple asks
1. Run `python3 make_art.py && ./render.sh`.
2. Download Apple's template from "All Promotional Artwork Templates" on the guidelines site (ask Gordon before downloading).
3. In Photoshop (or Photopea, which keeps Smart Objects), place each layer PNG in order as an embedded Smart Object, then hide
   or remove the guides.
4. Save with the file name above and upload to the matching dropwell. Apple may also want a version with the hero
   placed differently; move the hero layer and re-save.

Not yet checked: the art against the template's exact guide overlays (Apple's templates are downloads).
