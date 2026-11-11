// Our stand-in for ares' component/processor/sh2/recompiler.cpp (the SH-2 JIT). Not part of ares.
//
// Upstream sh2.cpp ends with `#include "recompiler.cpp"`. We do not vendor that file (it emits
// machine code through sljit), so the quoted include falls through to the include path and finds
// this file instead. Included inside `namespace ares { ... }` after SH2's register macros are
// undefined. With the stub `recompiler::generic::supported == false`, SH2::Accuracy::Recompiler is
// a compile-time false: every call site is either `if constexpr(Accuracy::Recompiler)` or
// short-circuited by `Accuracy::Interpreter`, so none of these can run. They abort if ever reached.
// The SH-2 is only used by the 32X add-on, which this app does not support (no 32X firmware).

auto SH2::Recompiler::invalidate(u32, u8) -> void { std::abort(); }
auto SH2::Recompiler::pool(u32) -> Pool* { std::abort(); }
auto SH2::Recompiler::block(u32) -> Block* { std::abort(); }
auto SH2::Recompiler::measure(u32) -> u8 { std::abort(); }
auto SH2::Recompiler::hash(u32, u8) -> u64 { std::abort(); }
auto SH2::Recompiler::emit(u32) -> Block* { std::abort(); }
auto SH2::Recompiler::emitInstruction(u16) -> u32 { std::abort(); }
auto SH2::Recompiler::getSR(reg) -> void { std::abort(); }
auto SH2::Recompiler::setSR(reg) -> void { std::abort(); }
auto SH2::Recompiler::isTerminal(u16) -> bool { std::abort(); }
auto SH2::Recompiler::mask(u8, u8) -> u64 { std::abort(); }
