// Build unit for paraLLEl-RDP's volk/volk.c (vendored unmodified in Sources/MUPEN64/parallel-rdp). volk_rename.h
// comes first so volk's function pointers don't clash with the statically linked MoltenVK. Part of Relics: Games (GPLv3).
#include "../volk_rename.h"
#include "../../../parallel-rdp/volk/volk.c"
