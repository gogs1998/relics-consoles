# MoltenVK (Apache-2.0)

Vulkan on Metal, needed by paraLLEl-RDP (the N64 RDP renderer, `Packages/CoreKit/Sources/MUPEN64/parallel-rdp`).

- `ios-arm64/libMoltenVK.a`: the unmodified static library from the official **MoltenVK v1.4.2** release
  (`MoltenVK-ios.tar` → `MoltenVK/MoltenVK/static/MoltenVK.xcframework/ios-arm64/libMoltenVK.a`,
  https://github.com/KhronosGroup/MoltenVK/releases/tag/v1.4.2), SHA-256
  `245e7e05926c55ae97ace1b1822190139d87bda5aaefbcfd2f5156e1287f448b`. Source: https://github.com/KhronosGroup/MoltenVK/tree/v1.4.2.
- `LICENSE`: MoltenVK's Apache-2.0 licence. The library also contains SPIRV-Cross (Apache-2.0) and cereal
  (BSD-3-Clause); notices in `Licenses/MoltenVK-Apache-2.0-and-bundled.txt`.
- Linked by the app only for iPhone/iPad device builds (`OTHER_LDFLAGS[sdk=iphoneos*]` in `project.yml`): the
  release has no simulator slice, so simulator builds don't link it and the N64 RDP layer falls back to VI
  scan-out there (`glue/rdp/rdp_glue.cpp`).
- Apache-2.0 is GPLv3-compatible (not GPLv2-compatible): with MoltenVK linked, the app (and its N64 part, whose
  mupen64plus code is GPL-2.0-or-later) is distributed under GPLv3.
