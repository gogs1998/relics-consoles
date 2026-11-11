// Our replacement for ares' <sljit.h> (thirdparty/sljit.h). Not part of ares.
//
// ares.hpp includes <sljit.h> unconditionally, but only the N64/PS1/32X recompilers use it.
// We never vendor or build sljit (the App Store forbids JIT), so this header is intentionally
// empty and does NOT define SLJIT. See shim/nall/recompiler/generic/generic.hpp.
#pragma once
