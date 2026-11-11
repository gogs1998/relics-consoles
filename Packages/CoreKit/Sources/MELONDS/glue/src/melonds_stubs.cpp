// Foldback stand-ins for melonDS classes whose sources are deliberately not vendored.
//
// The NDS code names a few DSi-mode and SD-card members, but only on paths that need a DSi
// (ConsoleType == 1) or a homebrew SD-card image (FATStorage). This build creates neither: the glue
// always builds an NDS and never passes SD-card arguments. If one were ever reached it stops the
// process loudly instead of running half-emulated hardware.
#include <cstdlib>

#include "DSi.h"
#include "DSi_I2S.h"
#include "DSi_SPI_TSC.h"
#include "FATStorage.h"

namespace {
[[noreturn]] void notInThisBuild() { std::abort(); }
}

namespace melonDS {

// DSi mode (DSi.cpp, DSi_I2S.cpp, DSi_SPI_TSC.cpp are not vendored).
void DSi::SoftReset() { notInThisBuild(); }
void DSi::RunNDMAs(u32) { notInThisBuild(); }
void DSi::StallNDMAs() { notInThisBuild(); }
void DSi::CheckNDMAs(u32, u32) { notInThisBuild(); }
void DSi_I2S::SampleClock(s16*) { notInThisBuild(); }

DSi_TSC::DSi_TSC(DSi& dsi) : TSC(dsi) { notInThisBuild(); }
DSi_TSC::~DSi_TSC() {}
void DSi_TSC::Reset() { notInThisBuild(); }
void DSi_TSC::DoSavestate(Savestate*) { notInThisBuild(); }
void DSi_TSC::SetTouchCoords(u16, u16) { notInThisBuild(); }
void DSi_TSC::Write(u8) { notInThisBuild(); }
void DSi_TSC::Release() { notInThisBuild(); }

// Homebrew SD-card images (FATStorage.cpp and FatFs are not vendored; the glue never makes one).
FATStorage::FATStorage(FATStorageArgs&&) noexcept { notInThisBuild(); }
FATStorage::FATStorage(FATStorage&&) noexcept { notInThisBuild(); }
FATStorage::~FATStorage() {}
bool FATStorage::InjectFile(const std::string&, u8*, u32) { notInThisBuild(); }
u32 FATStorage::ReadFile(const std::string&, u32, u32, u8*) { notInThisBuild(); }
u32 FATStorage::ReadSectors(u32, u32, u8*) const { notInThisBuild(); }
u32 FATStorage::WriteSectors(u32, u32, const u8*) { notInThisBuild(); }
u64 FATStorage::GetSectorCount() const { notInThisBuild(); }

}  // namespace melonDS
