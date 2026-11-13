// Build unit for rsp-hle's plugin.c (vendored unmodified, excluded from direct compilation).
// Statically linked plugins share one namespace with the core, which also exports
// PluginGetVersion, and with the video plugin's RomClosed, so rsp-hle's entry points get an
// `rsphle_` prefix here. Our static plugin table (glue/src/n64_glue.c) maps the standard names to
// them. Part of Foldback (GPLv3).
#define PluginStartup rsphle_PluginStartup
#define PluginShutdown rsphle_PluginShutdown
#define PluginGetVersion rsphle_PluginGetVersion
#define DoRspCycles rsphle_DoRspCycles
#define InitiateRSP rsphle_InitiateRSP
#define RomClosed rsphle_RomClosed

#include "../../rsp-hle/src/plugin.c"
