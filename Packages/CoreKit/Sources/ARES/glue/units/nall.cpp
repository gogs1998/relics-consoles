// Build unit (ours): the nall (ISC) sources ares needs. Replaces upstream nall/nall.cpp, which we
// don't vendor because it also builds nall's TCP server (tcptext). No dl.cpp (dlopen) and no
// run.cpp (process launching): ares' cores don't use them.
#include "../shim/ares_prelude.h"
#include <nall/intrinsics.hpp>
#include <nall/directory.cpp>
#include <nall/file-map.cpp>
#include <nall/inode.cpp>
#include <nall/instruction-set.cpp>
#include <nall/memory.cpp>
#include <nall/path.cpp>
#include <nall/platform.cpp>
#include <nall/random.cpp>
#include <nall/terminal.cpp>
#include <nall/thread.cpp>
