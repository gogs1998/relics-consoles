// Foldback: generated with `unifdef -UJIT_ENABLED` from melonDS src/ARMJIT.h (commit 497aa6c), so only the
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

#ifndef ARMJIT_H
#define ARMJIT_H

#include <algorithm>
#include <optional>
#include <memory>
#include "types.h"
#include "MemConstants.h"
#include "Args.h"
#include "ARMJIT_Memory.h"

namespace melonDS
{
class ARM;

// This version is a stub; the methods all do nothing,
// but there's still a Memory member.
class ARMJIT
{
public:
    ARMJIT(melonDS::NDS& nds, std::optional<JITArgs>) noexcept : Memory(nds) {}
    ~ARMJIT() noexcept {}
    void InvalidateByAddr(u32) noexcept {}
    void CheckAndInvalidateWVRAM(int) noexcept {}
    void CheckAndInvalidateITCM() noexcept {}
    void Reset() noexcept {}
    void JitEnableWrite() noexcept {}
    void JitEnableExecute() noexcept {}
    void CompileBlock(ARM*) noexcept {}
    void ResetBlockCache() noexcept {}
    template <u32, int>
    void CheckAndInvalidate(u32 addr) noexcept {}

    ARMJIT_Memory Memory;
};
}

#endif // ARMJIT_H

