// Our replacement for ares' CMake-generated ares/ares.cpp (template ares/ares/ares.cpp.in, ISC).
// Not part of ares. Differences from the template: no GDB debug server (nall/gdb, which opens a
// TCP socket), no generated resource.cpp (see shim/ares/resource/resource.hpp), version strings
// filled in by hand, and our own FixedAllocator that can never hand out executable memory.
#include "../shim/ares_prelude.h"
#include <ares/ares.hpp>
#include <ares/debug/debug.cpp>
#include <ares/node/node.cpp>
#include <ares/resource/resource.hpp>

namespace ares {

Platform* platform = nullptr;
atomic<bool> _runAhead = false;

const string Name       = "ares";
const string Version    = "0b92893";
const string Copyright  = "ares team, Near et al";
const string License    = "ISC";
const string LicenseURI = "https://opensource.org/licenses/ISC";
const string Website    = "ares-emu.net";
const string WebsiteURI = "https://ares-emu.net/";
const u32    SerializerSignature = 0x31545342;  //"BST1" (little-endian)

}

// Upstream ares/memory/fixed-allocator.cpp reserves 64 MiB of *executable* memory for the
// recompilers. Only the 32X (SH-2) path references it, and only to release it; we give it an
// empty, non-executable allocator instead (the upstream file is vendored but not compiled).
namespace ares::Memory {

FixedAllocator::FixedAllocator() {}

auto FixedAllocator::get() -> bump_allocator& {
  static FixedAllocator allocator;
  return allocator._allocator;
}

}

namespace Resource::Sprite::SuperFamicom {
const unsigned char CrosshairBlue[1] = {0};
const unsigned char CrosshairGreen[1] = {0};
const unsigned char CrosshairRed[1] = {0};
}
