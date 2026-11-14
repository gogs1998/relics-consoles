# Source code of the GPL demos bundled with Relics: Games

Relics: Games ships three GPL-3.0-or-later homebrew games as unmodified game files on the player's shelf. GPLv3 §6
requires the Corresponding Source to be available from the same place, so the exact upstream source archives for the
versions we ship are kept here, unmodified. This folder is not part of the app bundle.

| Demo (file in the app) | Archive here | Downloaded from | SHA-256 of the archive |
|---|---|---|---|
| µCity 1.3 by Antonio Niño Díaz (`ucity.gbc`) | `ucity-1.3.tar.gz` | https://github.com/AntonioND/ucity/archive/refs/tags/v1.3.tar.gz | `ce8b615a89b79c6237132329572abb9b8b477d9a5a72dd90114a21e95360b740` |
| Thwaite 0.03 by Damian Yerrick (`thwaite.nes`) | `thwaite-0.03.zip` | https://pineight.com/nes/thwaite-0.03.zip (the author's release; source + ROM) | `a782f6f22bac791fd30eef16933ee59d61fb83b68e3247d87b1df603c894ecd9` |
| Alex vs Bus: The Race pre-release 3 by M374LX (`alexvsbus-pre3.md`) | `alexvsbus-md-pre3.tar.gz` | https://github.com/M374LX/alexvsbus-md/archive/refs/tags/pre3.tar.gz | `85d73e40debdc1d1507e07fcb0276655b5af4598b202fd18dde8a4c985918f0c` |

The shipped game files are byte-identical to each author's own release build (checked 14 Nov 2026 by SHA-256):
`ucity.gbc` = the v1.3 GitHub release asset (`9422ee2c…`), `thwaite.nes` = the ROM inside `thwaite-0.03.zip`
(`3543ebf8…`), `alexvsbus-pre3.md` = the ROM in the pre3 GitHub release zip (`1b05f681…`).

The other two demos don't need this: Libbet 0.08 is zlib-licensed (source: https://github.com/pinobatch/libbet), and
Concentration Room 0.02's GPL licence has an exception allowing exact copies of the author's ROM without source
(source anyway: https://pineight.com/croom/).

Licences and credits for each demo: `Licenses/demos-credits.txt` (also in the app under About › Free demos).
