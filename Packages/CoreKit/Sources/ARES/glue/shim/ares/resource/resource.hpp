// Our replacement for ares' generated ares/resource/resource.hpp (produced upstream by the
// `sourcery` tool from ares/resource/resource.bml). Not part of ares.
//
// The SNES light-gun controllers (Super Scope, Justifier) draw a crosshair sprite from these
// images. We never attach those controllers and don't vendor the PNGs, so the images are empty
// (definitions in glue/ares_glue.cpp); an empty image decodes to nothing.
#pragma once

namespace Resource {
namespace Sprite {
namespace SuperFamicom {
extern const unsigned char CrosshairBlue[1];
extern const unsigned char CrosshairGreen[1];
extern const unsigned char CrosshairRed[1];
}
}
}
