// Foldback: generated with `unifdef -UJIT_ENABLED` from melonDS src/ARMJIT_Memory.h (commit 497aa6c), so only the
// non-JIT stand-ins remain. The JIT is never built. Regenerate rather than edit.
/*
    Copyright 2016-2026 melonDS team

    This file is part of melonDS.

    melonDS is free software: you can redistribute it and/or modify it under
    the terms of the GNU General Public License as published by the Free
    Software Foundation, either version 3 of the License, or (at your option)
    any later version.

    melonDS is distributed in the hope that it will be useful, but WITHOUT ANY
    WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
    FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.

    You should have received a copy of the GNU General Public License along
    with melonDS. If not, see http://www.gnu.org/licenses/.
*/

#ifndef ARMJIT_MEMORY
#define ARMJIT_MEMORY

#include "types.h"
#include "MemConstants.h"

# include <array>

namespace melonDS
{

static constexpr u32 LargePageSize = 0x4000;
static constexpr u32 RegularPageSize = 0x1000;

constexpr u32 RoundUp(u32 size) noexcept
{
    return (size + LargePageSize - 1) & ~(LargePageSize - 1);
}

static constexpr u32 MemBlockMainRAMOffset = 0;
static constexpr u32 MemBlockSWRAMOffset = RoundUp(MainRAMMaxSize);
static constexpr u32 MemBlockARM7WRAMOffset = MemBlockSWRAMOffset + RoundUp(SharedWRAMSize);
static constexpr u32 MemBlockDTCMOffset = MemBlockARM7WRAMOffset + RoundUp(ARM7WRAMSize);
static constexpr u32 MemBlockNWRAM_AOffset = MemBlockDTCMOffset + RoundUp(DTCMPhysicalSize);
static constexpr u32 MemBlockNWRAM_BOffset = MemBlockNWRAM_AOffset + RoundUp(NWRAMSize);
static constexpr u32 MemBlockNWRAM_COffset = MemBlockNWRAM_BOffset + RoundUp(NWRAMSize);
static constexpr u32 MemoryTotalSize = MemBlockNWRAM_COffset + RoundUp(NWRAMSize);

class ARMJIT_Memory
{
public:
    enum
    {
        memregion_Other = 0,
        memregion_ITCM,
        memregion_DTCM,
        memregion_BIOS9,
        memregion_MainRAM,
        memregion_SharedWRAM,
        memregion_IO9,
        memregion_VRAM,
        memregion_BIOS7,
        memregion_WRAM7,
        memregion_IO7,
        memregion_Wifi,
        memregion_VWRAM,

        // DSi
        memregion_BIOS9DSi,
        memregion_BIOS7DSi,
        memregion_NewSharedWRAM_A,
        memregion_NewSharedWRAM_B,
        memregion_NewSharedWRAM_C,

        memregions_Count
    };

public:
    explicit ARMJIT_Memory(melonDS::NDS&) {};
    ~ARMJIT_Memory() = default;
    ARMJIT_Memory(const ARMJIT_Memory&) = delete;
    ARMJIT_Memory(ARMJIT_Memory&&) = delete;
    ARMJIT_Memory& operator=(const ARMJIT_Memory&) = delete;
    ARMJIT_Memory& operator=(ARMJIT_Memory&&) = delete;

    void Reset() noexcept {}
    void RemapDTCM(u32 newBase, u32 newSize) noexcept {}
    void RemapSWRAM() noexcept {}
    void RemapNWRAM(int num) noexcept {}
    void SetCodeProtection(int region, u32 offset, bool protect) noexcept {}

    [[nodiscard]] u8* GetMainRAM() noexcept { return MainRAM.data(); }
    [[nodiscard]] const u8* GetMainRAM() const noexcept { return MainRAM.data(); }

    [[nodiscard]] u8* GetSharedWRAM() noexcept { return SharedWRAM.data(); }
    [[nodiscard]] const u8* GetSharedWRAM() const noexcept { return SharedWRAM.data(); }

    [[nodiscard]] u8* GetARM7WRAM() noexcept { return ARM7WRAM.data(); }
    [[nodiscard]] const u8* GetARM7WRAM() const noexcept { return ARM7WRAM.data(); }

    [[nodiscard]] u8* GetARM9DTCM() noexcept { return DTCM.data(); }
    [[nodiscard]] const u8* GetARM9DTCM() const noexcept { return DTCM.data(); }

    [[nodiscard]] u8* GetNWRAM_A() noexcept { return NWRAM_A.data(); }
    [[nodiscard]] const u8* GetNWRAM_A() const noexcept { return NWRAM_A.data(); }

    [[nodiscard]] u8* GetNWRAM_B() noexcept { return NWRAM_B.data(); }
    [[nodiscard]] const u8* GetNWRAM_B() const noexcept { return NWRAM_B.data(); }

    [[nodiscard]] u8* GetNWRAM_C() noexcept { return NWRAM_C.data(); }
    [[nodiscard]] const u8* GetNWRAM_C() const noexcept { return NWRAM_C.data(); }
private:
    std::array<u8, MainRAMMaxSize> MainRAM {};
    std::array<u8, ARM7WRAMSize> ARM7WRAM {};
    std::array<u8, SharedWRAMSize> SharedWRAM {};
    std::array<u8, DTCMPhysicalSize> DTCM {};
    std::array<u8, NWRAMSize> NWRAM_A {};
    std::array<u8, NWRAMSize> NWRAM_B {};
    std::array<u8, NWRAMSize> NWRAM_C {};
};
}
#endif
