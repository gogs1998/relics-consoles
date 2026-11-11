// Foldback build unit for melonDS src/NDSCart.cpp (compiled here instead of directly).
//
// The NDS code downcasts to DSi with dynamic_cast only on paths guarded by ConsoleType == 1, which
// never happens in this DS-only build. dynamic_cast needs DSi's type info, which lives with DSi.cpp
// (not vendored). All headers are included first (they are include-guarded), so the macro below only
// touches the body of NDSCart.cpp, where a static_cast is equivalent for a real DSi and is never reached.
#include <string.h>
#include <inttypes.h>
#include <assert.h>
#include "NDS.h"
#include "DSi.h"
#include "NDSCart.h"
#include "CRC32.h"
#include "Platform.h"
#include "ROMList.h"
#include "FATStorage.h"
#include "Utils.h"
#include "NDSCart/CartCommon.h"
#include "NDSCart/CartRetail.h"
#include "NDSCart/CartRetailNAND.h"
#include "NDSCart/CartRetailIR.h"
#include "NDSCart/CartRetailBT.h"
#include "NDSCart/CartHomebrew.h"
#include "NDSCart/CartR4.h"

#define dynamic_cast static_cast
#include "../../melonds/NDSCart.cpp"
#undef dynamic_cast
