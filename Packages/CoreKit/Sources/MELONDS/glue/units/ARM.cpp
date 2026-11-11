// Foldback build unit for melonDS src/ARM.cpp (compiled here instead of directly).
//
// The NDS code downcasts to DSi with dynamic_cast only on paths guarded by ConsoleType == 1, which
// never happens in this DS-only build. dynamic_cast needs DSi's type info, which lives with DSi.cpp
// (not vendored). All headers are included first (they are include-guarded), so the macro below only
// touches the body of ARM.cpp, where a static_cast is equivalent for a real DSi and is never reached.
#include <stdio.h>
#include <assert.h>
#include <algorithm>
#include "NDS.h"
#include "DSi.h"
#include "ARM.h"
#include "ARMInterpreter.h"
#include "AREngine.h"
#include "ARMJIT.h"
#include "Platform.h"
#include "GPU.h"
#include "ARMJIT_Memory.h"

#define dynamic_cast static_cast
#include "../../melonds/ARM.cpp"
#undef dynamic_cast
