// Foldback build unit for melonDS src/NDS.cpp (compiled here instead of directly).
//
// The NDS code downcasts to DSi with dynamic_cast only on paths guarded by ConsoleType == 1, which
// never happens in this DS-only build. dynamic_cast needs DSi's type info, which lives with DSi.cpp
// (not vendored). All headers are included first (they are include-guarded), so the macro below only
// touches the body of NDS.cpp, where a static_cast is equivalent for a real DSi and is never reached.
#include <assert.h>
#include <stdio.h>
#include <string.h>
#include <inttypes.h>
#include "NDS.h"
#include "ARM.h"
#include "NDSCart.h"
#include "GBACart.h"
#include "DMA.h"
#include "FIFO.h"
#include "GPU.h"
#include "SPU.h"
#include "SPI.h"
#include "RTC.h"
#include "Wifi.h"
#include "AREngine.h"
#include "Platform.h"
#include "FreeBIOS.h"
#include "Args.h"
#include "version.h"
#include "DSi.h"
#include "DSi_SPI_TSC.h"
#include "DSi_NWifi.h"
#include "DSi_Camera.h"
#include "DSi_DSP.h"
#include "ARMJIT.h"
#include "ARMJIT_Memory.h"

#define dynamic_cast static_cast
#include "../../melonds/NDS.cpp"
#undef dynamic_cast
