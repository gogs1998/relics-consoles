// Our replacement for ares' thirdparty/xxhash.h. Not part of ares.
// Upstream sh2.cpp includes xxHash only for the SH-2 recompiler's block hashing, which we don't
// build (see shim/recompiler.cpp), so nothing from it is needed.
#pragma once
