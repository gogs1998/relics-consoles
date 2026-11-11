// Our replacement for nall/recompiler/generic/generic.hpp. Not part of ares/nall.
//
// Upstream, this header wraps sljit (a JIT). The Mega Drive core always includes the SH-2 CPU
// (for the 32X add-on), whose header derives a `Recompiler` from `recompiler::generic`.
// This stub keeps that header compiling while making a recompiler impossible:
//   * `supported = false`, so SH2::Accuracy::Interpreter is true and Accuracy::Recompiler false;
//   * no code generator exists at all (no sljit, no executable memory);
//   * the SH-2 recompiler's out-of-line functions are defined in glue/units/md_sh2.cpp as aborts.
#pragma once

namespace nall::recompiler {
  struct generic {
    static constexpr bool supported = false;

    // Register operand type named in SH2::Recompiler's declarations (never used).
    struct reg { int n = 0; };

    bump_allocator& allocator;
    generic(bump_allocator& alloc) : allocator(alloc) {}
  };
}
