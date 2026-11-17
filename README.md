# Relics: Games

A retro game player made for iPhone Duo's two screens, which plays just as well on iPhone and iPad.
It plays NES, SNES, Game Boy, Game Boy Color, Game Boy Advance, Mega Drive, Nintendo DS and Nintendo 64 games you own.
It includes a few free homebrew demos (see `Licenses/demos-credits.txt`). It includes no commercial games, no console
system software, and never downloads games.

On the App Store as **Relics: Games** by IQ Labs. Tag `v1.0-build9` is the exact source of version 1.0 (build 9).

## Licence

Relics: Games is free software: you can redistribute it and/or modify it under the terms of the GNU General Public
License, version 3 or (at your option) any later version. See `COPYING`. Third-party components and their licences are
listed in `Licenses/README.md`; source archives of the bundled demos and MoltenVK are in `release-sources/`.

## Building

Xcode with XcodeGen: `xcodegen generate`, then build the `DuoEmulator` scheme. Signing settings go in a local
`Local.xcconfig` (not in the repo). The emulator cores are vendored under `Packages/CoreKit/Sources`.

Relics: Games is not affiliated with, endorsed or sponsored by Nintendo or Sega.

Contact: gordon@iqlabs.app
