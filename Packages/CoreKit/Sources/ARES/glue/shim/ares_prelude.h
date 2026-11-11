// Included first by every translation unit of the ARES target (our own file, not ares).
//
// Compile-time guarantee that the vendored code can never create executable memory or toggle
// JIT write protection on iOS: nall's memory::map/protect are compiled with PROT_EXEC and MAP_JIT
// defined to 0, and pthread_jit_write_protect_np (unavailable on iOS) becomes a no-op.
// The only machine code ares uses outside normal compiled code is libco's aarch64 context switch,
// which is a constant in the binary's __TEXT section (signed with the app; no mprotect).
#pragma once
#include <pthread.h>
#include <sys/mman.h>
#undef PROT_EXEC
#define PROT_EXEC 0
#undef MAP_JIT
#define MAP_JIT 0
#define pthread_jit_write_protect_np(x) ((void)(x))
