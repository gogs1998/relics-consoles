// Foldback's front end for the vendored mupen64plus core (GPLv3, part of Foldback; not mupen64plus).
//
// - Runs the core's own emulation loop (M64CMD_EXECUTE) on a private thread and parks that thread at
//   every vertical interrupt, inside our video plugin's UpdateScreen, so the host can step it one
//   video field at a time. Save states are taken and restored at that same point, synchronously.
// - Provides the four plugins statically: the RSP is a dispatcher (glue/rdp/rsp_dispatch.c) over rsp-hle
//   (vendored, its plugin.c compiled through glue/units with renamed entry points) and cxd4's interpreter
//   for graphics tasks, plus our own video, audio and input plugins below.
//   `osal_dynlib_getproc` (the core's and rsp-hle's only way to find plugin and core functions)
//   resolves names against the tables at the bottom of this file; nothing is ever loaded at run time.
// - Video: paraLLEl-RDP on MoltenVK (glue/rdp/rdp_glue.cpp) renders the RDP and runs the VI on the GPU when
//   Vulkan is available (iPhone/iPad); otherwise (simulator, Mac tests) the video plugin scans the VI's
//   framebuffer out of RDRAM, which shows anything the CPU drew there.
#define M64P_CORE_PROTOTYPES 1

#include "Mupen64Glue.h"

#include <errno.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

#include "api/callbacks.h"
#include "api/m64p_config.h"
#include "api/m64p_frontend.h"
#include "api/m64p_plugin.h"
#include "api/m64p_types.h"
#include "main/main.h"
#include "main/rom.h"
#include "main/savestates.h"
#include "main/util.h"
#include "main/version.h"
#include "osal/dynamiclib.h"
#include "plugin/plugin.h"

#include "../rdp/n64_rdp.h"   // paraLLEl-RDP on MoltenVK + cxd4 for graphics tasks (glue/rdp)

// rsp-hle's entry points, renamed by glue/units/rsphle_plugin.c.
m64p_error rsphle_PluginStartup(m64p_dynlib_handle, void*, void (*)(void*, int, const char*));
m64p_error rsphle_PluginShutdown(void);
m64p_error rsphle_PluginGetVersion(m64p_plugin_type*, int*, int*, const char**, int*);
unsigned int rsphle_DoRspCycles(unsigned int);
void rsphle_InitiateRSP(RSP_INFO, unsigned int*);
void rsphle_RomClosed(void);

// The work and data directories, read by our osal (n64_platform.c).
char g_n64_work_dir[1024];
char g_n64_data_dir[1024];

enum { CMD_NONE, CMD_RUN, CMD_SAVE, CMD_LOAD, CMD_RESET, CMD_QUIT };
enum { TURN_HOST, TURN_CORE };
enum { AUDIO_CAP = 1 << 15 };

struct N64Handle {
    pthread_t thread;
    pthread_mutex_t lock;
    pthread_cond_t cond;
    int turn;
    int cmd;
    int result;
    bool executing;   // M64CMD_EXECUTE is running on the thread
    bool limiterOff;

    uint32_t fb[N64_SCREEN_WIDTH * N64_SCREEN_HEIGHT];
    uint32_t frames;
    BUTTONS pads[N64_MAX_PLAYERS];

    float audio[AUDIO_CAP];
    size_t audioCount;
    uint32_t audioRate;
    double audioPhase;   // position between the previous and the current source sample
    float audioPrev;

    char saveDir[1100];
    char statePath[1100];
};

static N64Handle* g_h;   // the one live machine (mupen64plus is process-global)
static GFX_INFO g_gfx;
static AUDIO_INFO g_audio;
static CONTROL* g_controls;

// MARK: handshake (the core thread parks, the host thread resumes it)

/// Core thread: hands control back to the host and waits for the next command.
static int core_park(N64Handle* h)
{
    pthread_mutex_lock(&h->lock);
    h->turn = TURN_HOST;
    pthread_cond_broadcast(&h->cond);
    while (h->turn != TURN_CORE) pthread_cond_wait(&h->cond, &h->lock);
    int cmd = h->cmd;
    h->cmd = CMD_NONE;
    pthread_mutex_unlock(&h->lock);
    return cmd;
}

/// Host thread: gives the core a command and waits until it parks again.
static void host_send(N64Handle* h, int cmd)
{
    pthread_mutex_lock(&h->lock);
    h->cmd = cmd;
    h->turn = TURN_CORE;
    pthread_cond_broadcast(&h->cond);
    while (h->turn != TURN_HOST) pthread_cond_wait(&h->cond, &h->lock);
    pthread_mutex_unlock(&h->lock);
}

static void* core_thread(void* arg)
{
    N64Handle* h = (N64Handle*)arg;
    CoreDoCommand(M64CMD_EXECUTE, 0, NULL);
    // The loop has ended (quit, or the core failed to start): release the host for good.
    pthread_mutex_lock(&h->lock);
    h->executing = false;
    h->turn = TURN_HOST;
    pthread_cond_broadcast(&h->cond);
    pthread_mutex_unlock(&h->lock);
    return NULL;
}

// MARK: video plugin (VI scan-out)

static inline uint32_t expand5(uint32_t v) { return (v << 3) | (v >> 2); }

/// Copies the framebuffer the VI is showing into `fb`, scaled to 320 x 240.
static void scan_out(N64Handle* h)
{
    if (n64rdp_scan_out(h->fb, N64_SCREEN_WIDTH, N64_SCREEN_HEIGHT)) return;   // the RDP is running (device)
    const uint32_t status = *g_gfx.VI_STATUS_REG;
    const uint32_t type = status & 3;
    const uint32_t width = *g_gfx.VI_WIDTH_REG & 0xFFF;
    if (type < 2 || width == 0) {   // blank
        for (size_t i = 0; i < N64_SCREEN_WIDTH * N64_SCREEN_HEIGHT; i++) h->fb[i] = 0xFF000000u;
        return;
    }
    const uint32_t origin = *g_gfx.VI_ORIGIN_REG & 0xFFFFFF;
    const uint32_t hs = *g_gfx.VI_H_START_REG, vs = *g_gfx.VI_V_START_REG;
    const int hStart = (int)((hs >> 16) & 0x3FF), hEnd = (int)(hs & 0x3FF);
    const int vStart = (int)((vs >> 16) & 0x3FF), vEnd = (int)(vs & 0x3FF);
    const double xScale = (double)(*g_gfx.VI_X_SCALE_REG & 0xFFF) / 1024.0;
    const double yScale = (double)(*g_gfx.VI_Y_SCALE_REG & 0xFFF) / 1024.0;
    int srcW = (int)((hEnd - hStart) * xScale + 0.5);
    int srcH = (int)(((vEnd - vStart) / 2) * yScale + 0.5);
    if (srcW <= 0 || srcW > (int)width) srcW = (int)width;
    if (srcH <= 0 || srcH > 576) srcH = width > 320 ? 480 : 240;
    const uint8_t* ram = g_gfx.RDRAM;
    const uint32_t mask = (g_gfx.RDRAM_SIZE ? *g_gfx.RDRAM_SIZE : 0x800000) - 1;
    for (int y = 0; y < N64_SCREEN_HEIGHT; y++) {
        const uint32_t sy = (uint32_t)(y * srcH / N64_SCREEN_HEIGHT);
        uint32_t* out = &h->fb[y * N64_SCREEN_WIDTH];
        for (int x = 0; x < N64_SCREEN_WIDTH; x++) {
            const uint32_t sx = (uint32_t)(x * srcW / N64_SCREEN_WIDTH);
            if (type == 2) {   // RGBA 5551; RDRAM holds host-order words, so halfwords are at addr ^ 2
                const uint32_t a = (origin + (sy * width + sx) * 2) & mask;
                uint16_t p;
                memcpy(&p, ram + (a ^ 2), 2);
                out[x] = 0xFF000000u | expand5((p >> 11) & 31) << 16 | expand5((p >> 6) & 31) << 8
                    | expand5((p >> 1) & 31);
            } else {           // RGBA 8888
                const uint32_t a = (origin + (sy * width + sx) * 4) & mask & ~3u;
                uint32_t p;
                memcpy(&p, ram + a, 4);
                out[x] = 0xFF000000u | (p >> 8);
            }
        }
    }
}

/// Called by the core at every vertical interrupt: the frame boundary.
static void v_UpdateScreen(void)
{
    N64Handle* h = g_h;
    if (h == NULL) return;
    if (!h->limiterOff) {   // the host paces frames; never let the core sleep
        main_core_state_set(M64CORE_SPEED_LIMITER, 0);
        h->limiterOff = true;
    }
    scan_out(h);
    h->frames++;
    for (;;) {
        switch (core_park(h)) {
        case CMD_RUN:
            return;
        case CMD_SAVE:
            // Synchronous: without M64P_PARALLEL the core's work queue runs the write inline.
            savestates_set_job(savestates_job_save, savestates_type_m64p, h->statePath);
            h->result = savestates_save();
            break;
        case CMD_LOAD:
            // Taken here, at the same point the state was saved, so the rest of this vertical
            // interrupt handler continues exactly as the saved machine would have.
            savestates_set_job(savestates_job_load, savestates_type_m64p, h->statePath);
            h->result = savestates_load();
            if (h->result) scan_out(h);
            break;
        case CMD_RESET:
            main_reset(1);   // applied at the next interrupt
            break;
        case CMD_QUIT:
            main_stop();
            return;
        default:
            break;
        }
    }
}

static m64p_error v_PluginGetVersion(m64p_plugin_type* type, int* version, int* api, const char** name, int* caps)
{
    if (type) *type = M64PLUGIN_GFX;
    if (version) *version = 0x010000;
    if (api) *api = GFX_API_VERSION;
    if (name) *name = "Foldback VI scan-out";
    if (caps) *caps = 0;
    return M64ERR_SUCCESS;
}
static void v_ChangeWindow(void) {}
static int v_InitiateGFX(GFX_INFO info) { g_gfx = info; return 1; }
static void v_MoveScreen(int x, int y) { (void)x; (void)y; }
static void v_ProcessDList(void) {}
static void v_ProcessRDPList(void) { n64rdp_process_rdp_list(); }
static void v_RomClosed(void) { n64rdp_gfx_shutdown(); }
static int v_RomOpen(void) { n64rdp_gfx_init(&g_gfx); return 1; }
static void v_ShowCFB(void) {}
static void v_ViStatusChanged(void) {}
static void v_ViWidthChanged(void) {}
static void v_ReadScreen2(void* dest, int* width, int* height, int front)
{
    (void)front;
    if (width) *width = N64_SCREEN_WIDTH;
    if (height) *height = N64_SCREEN_HEIGHT;
    if (dest != NULL && g_h != NULL) {   // RGB888, bottom row first (the core's screenshot format)
        uint8_t* d = (uint8_t*)dest;
        for (int y = N64_SCREEN_HEIGHT - 1; y >= 0; y--)
            for (int x = 0; x < N64_SCREEN_WIDTH; x++) {
                uint32_t p = g_h->fb[y * N64_SCREEN_WIDTH + x];
                *d++ = (uint8_t)(p >> 16); *d++ = (uint8_t)(p >> 8); *d++ = (uint8_t)p;
            }
    }
}
static void v_SetRenderingCallback(void (*callback)(int)) { (void)callback; }
static void v_ResizeVideoOutput(int w, int h) { (void)w; (void)h; }
static void v_FBRead(unsigned int addr) { (void)addr; }
static void v_FBWrite(unsigned int addr, unsigned int size) { (void)addr; (void)size; }
static void v_FBGetFrameBufferInfo(void* info) { (void)info; }

// MARK: audio plugin (AI samples → 48 kHz mono)

static uint32_t vi_clock(int systemType)
{
    switch (systemType) {
    case SYSTEM_PAL: return 49656530;
    case SYSTEM_MPAL: return 48628316;
    default: return 48681812;
    }
}

static m64p_error a_PluginGetVersion(m64p_plugin_type* type, int* version, int* api, const char** name, int* caps)
{
    if (type) *type = M64PLUGIN_AUDIO;
    if (version) *version = 0x010000;
    if (api) *api = AUDIO_API_VERSION;
    if (name) *name = "Foldback audio";
    if (caps) *caps = 0;
    return M64ERR_SUCCESS;
}
static void a_AiDacrateChanged(int systemType)
{
    if (g_h == NULL || g_audio.AI_DACRATE_REG == NULL) return;
    g_h->audioRate = vi_clock(systemType) / (*g_audio.AI_DACRATE_REG + 1);
}
static void a_AiLenChanged(void)
{
    N64Handle* h = g_h;
    if (h == NULL || h->audioRate == 0) return;
    const uint32_t len = *g_audio.AI_LEN_REG & 0x3FFF8;
    const uint32_t addr = *g_audio.AI_DRAM_ADDR_REG & 0xFFFFF8;
    const uint32_t ramSize = 0x800000;
    if (addr + len > ramSize) return;
    const double step = (double)h->audioRate / 48000.0;   // source samples per output sample
    for (uint32_t o = 0; o < len; o += 4) {
        uint32_t w;
        memcpy(&w, g_audio.RDRAM + addr + o, 4);   // host-order word: left in the high half
        const float s = ((float)(int16_t)(w >> 16) + (float)(int16_t)(w & 0xFFFF)) * (0.5f / 32768.0f);
        // linear interpolation between the previous and this sample
        while (h->audioPhase < 1.0) {
            if (h->audioCount < AUDIO_CAP)
                h->audio[h->audioCount++] = h->audioPrev + (s - h->audioPrev) * (float)h->audioPhase;
            h->audioPhase += step;
        }
        h->audioPhase -= 1.0;
        h->audioPrev = s;
    }
}
static int a_InitiateAudio(AUDIO_INFO info) { g_audio = info; return 1; }
static void a_ProcessAList(void) {}
static int a_RomOpen(void) { return 1; }
static void a_RomClosed(void) {}
static void a_SetSpeedFactor(int f) { (void)f; }
static void a_VolumeUp(void) {}
static void a_VolumeDown(void) {}
static int a_VolumeGetLevel(void) { return 100; }
static void a_VolumeSetLevel(int l) { (void)l; }
static void a_VolumeMute(void) {}
static const char* a_VolumeGetString(void) { return "100%"; }

// MARK: input plugin

static m64p_error i_PluginGetVersion(m64p_plugin_type* type, int* version, int* api, const char** name, int* caps)
{
    if (type) *type = M64PLUGIN_INPUT;
    if (version) *version = 0x010000;
    if (api) *api = INPUT_API_VERSION;
    if (name) *name = "Foldback input";
    if (caps) *caps = 0;
    return M64ERR_SUCCESS;
}
static void i_ControllerCommand(int control, unsigned char* command) { (void)control; (void)command; }
static void i_GetKeys(int control, BUTTONS* keys)
{
    if (g_h != NULL && control >= 0 && control < N64_MAX_PLAYERS) *keys = g_h->pads[control];
    else keys->Value = 0;
}
static void i_InitiateControllers(CONTROL_INFO info)
{
    g_controls = info.Controls;
    for (int i = 0; i < 4; i++) {
        // Two pads plugged in, each with a Controller Pak (the core falls back to no pak when the
        // ROM database says the game can't use one).
        info.Controls[i].Present = i < 2;
        info.Controls[i].RawData = 0;
        info.Controls[i].Plugin = PLUGIN_MEMPAK;
        info.Controls[i].Type = CONT_TYPE_STANDARD;
    }
}
static void i_ReadController(int control, unsigned char* command) { (void)control; (void)command; }
static int i_RomOpen(void) { return 1; }
static void i_RomClosed(void) {}
static void i_SDL_KeyDown(int mod, int sym) { (void)mod; (void)sym; }
static void i_SDL_KeyUp(int mod, int sym) { (void)mod; (void)sym; }

// MARK: static plugin tables (`osal_dynlib_getproc`)

typedef struct { const char* name; m64p_function fn; } ProcEntry;
#define P(n, f) { n, (m64p_function)(f) }

static const ProcEntry kCoreProcs[] = {
    P("CoreGetAPIVersions", CoreGetAPIVersions), P("CoreDoCommand", CoreDoCommand),
    P("ConfigOpenSection", ConfigOpenSection), P("ConfigDeleteSection", ConfigDeleteSection),
    P("ConfigSaveSection", ConfigSaveSection), P("ConfigSaveFile", ConfigSaveFile),
    P("ConfigSetParameter", ConfigSetParameter), P("ConfigGetParameter", ConfigGetParameter),
    P("ConfigSetDefaultInt", ConfigSetDefaultInt), P("ConfigSetDefaultFloat", ConfigSetDefaultFloat),
    P("ConfigSetDefaultBool", ConfigSetDefaultBool), P("ConfigSetDefaultString", ConfigSetDefaultString),
    P("ConfigGetParamInt", ConfigGetParamInt), P("ConfigGetParamFloat", ConfigGetParamFloat),
    P("ConfigGetParamBool", ConfigGetParamBool), P("ConfigGetParamString", ConfigGetParamString),
    P("ConfigGetSharedDataFilepath", ConfigGetSharedDataFilepath),
    P("ConfigGetUserConfigPath", ConfigGetUserConfigPath), P("ConfigGetUserDataPath", ConfigGetUserDataPath),
    P("ConfigGetUserCachePath", ConfigGetUserCachePath),
    { NULL, NULL },
};
static void rdp_InitiateRSP(RSP_INFO info, unsigned int* cycles) { n64rdp_rsp_InitiateRSP(&info, cycles); }
static const ProcEntry kRspProcs[] = {
    P("PluginStartup", rsphle_PluginStartup), P("PluginShutdown", rsphle_PluginShutdown),
    P("PluginGetVersion", rsphle_PluginGetVersion), P("DoRspCycles", n64rdp_rsp_DoRspCycles),
    P("InitiateRSP", rdp_InitiateRSP), P("RomClosed", n64rdp_rsp_RomClosed),
    { NULL, NULL },
};
static const ProcEntry kGfxProcs[] = {
    P("PluginGetVersion", v_PluginGetVersion), P("ChangeWindow", v_ChangeWindow),
    P("InitiateGFX", v_InitiateGFX), P("MoveScreen", v_MoveScreen), P("ProcessDList", v_ProcessDList),
    P("ProcessRDPList", v_ProcessRDPList), P("RomClosed", v_RomClosed), P("RomOpen", v_RomOpen),
    P("ShowCFB", v_ShowCFB), P("UpdateScreen", v_UpdateScreen), P("ViStatusChanged", v_ViStatusChanged),
    P("ViWidthChanged", v_ViWidthChanged), P("ReadScreen2", v_ReadScreen2),
    P("SetRenderingCallback", v_SetRenderingCallback), P("ResizeVideoOutput", v_ResizeVideoOutput),
    P("FBRead", v_FBRead), P("FBWrite", v_FBWrite), P("FBGetFrameBufferInfo", v_FBGetFrameBufferInfo),
    { NULL, NULL },
};
static const ProcEntry kAudioProcs[] = {
    P("PluginGetVersion", a_PluginGetVersion), P("AiDacrateChanged", a_AiDacrateChanged),
    P("AiLenChanged", a_AiLenChanged), P("InitiateAudio", a_InitiateAudio), P("ProcessAList", a_ProcessAList),
    P("RomOpen", a_RomOpen), P("RomClosed", a_RomClosed), P("SetSpeedFactor", a_SetSpeedFactor),
    P("VolumeUp", a_VolumeUp), P("VolumeDown", a_VolumeDown), P("VolumeGetLevel", a_VolumeGetLevel),
    P("VolumeSetLevel", a_VolumeSetLevel), P("VolumeMute", a_VolumeMute),
    P("VolumeGetString", a_VolumeGetString),
    { NULL, NULL },
};
static const ProcEntry kInputProcs[] = {
    P("PluginGetVersion", i_PluginGetVersion), P("ControllerCommand", i_ControllerCommand),
    P("GetKeys", i_GetKeys), P("InitiateControllers", i_InitiateControllers),
    P("ReadController", i_ReadController), P("RomOpen", i_RomOpen), P("RomClosed", i_RomClosed),
    P("SDL_KeyDown", i_SDL_KeyDown), P("SDL_KeyUp", i_SDL_KeyUp),
    { NULL, NULL },
};
#undef P

// The "library handles" are just the tables' addresses.
#define HANDLE(t) ((m64p_dynlib_handle)(void*)(t))

m64p_function osal_dynlib_getproc(m64p_dynlib_handle handle, const char* name)
{
    const ProcEntry* t = (const ProcEntry*)(void*)handle;
    if (t != kCoreProcs && t != kRspProcs && t != kGfxProcs && t != kAudioProcs && t != kInputProcs) return NULL;
    for (; t->name != NULL; t++)
        if (strcmp(t->name, name) == 0) return t->fn;
    return NULL;
}

/// rsp-hle's fallback-plugin loader: there is nothing to load (iOS forbids it, and we never would).
m64p_error osal_dynlib_open(m64p_dynlib_handle* handle, const char* path)
{
    (void)path;
    if (handle) *handle = NULL;
    return M64ERR_INPUT_NOT_FOUND;
}
m64p_error osal_dynlib_close(m64p_dynlib_handle handle) { (void)handle; return M64ERR_SUCCESS; }

// MARK: callbacks

static void debug_callback(void* ctx, int level, const char* message)
{
    (void)ctx;
#ifdef N64_GLUE_VERBOSE
    fprintf(stderr, "[mupen64plus %d] %s\n", level, message);
#else
    (void)level; (void)message;
#endif
}

static void state_callback(void* ctx, m64p_core_param param, int value)
{
    (void)ctx; (void)param; (void)value;
}

// MARK: battery blob ("N64B" v1: tag, length, bytes for each file the game wrote)

static const char* const kBatteryExts[4] = { "eep", "sra", "fla", "mpk" };

static void battery_path(const N64Handle* h, int i, char* out, size_t cap)
{
    char name[64];
    snprintf(name, sizeof(name), "%s", ROM_PARAMS.headername);
    string_replace_chars(name, ":<>\"/\\|?*", '_');   // as the core's get_save_filename does
    snprintf(out, cap, "%s%s.%s", h->saveDir, name, kBatteryExts[i]);
}

static uint8_t* read_file(const char* path, size_t* size)
{
    FILE* f = fopen(path, "rb");
    if (f == NULL) return NULL;
    fseek(f, 0, SEEK_END);
    long n = ftell(f);
    fseek(f, 0, SEEK_SET);
    uint8_t* buf = n > 0 ? (uint8_t*)malloc((size_t)n) : NULL;
    if (buf != NULL && fread(buf, 1, (size_t)n, f) != (size_t)n) { free(buf); buf = NULL; }
    fclose(f);
    *size = buf ? (size_t)n : 0;
    return buf;
}

static bool write_file(const char* path, const uint8_t* data, size_t size)
{
    FILE* f = fopen(path, "wb");
    if (f == NULL) return false;
    bool ok = fwrite(data, 1, size, f) == size;
    fclose(f);
    return ok;
}

static void put32(uint8_t* p, uint32_t v) { p[0] = (uint8_t)(v >> 24); p[1] = (uint8_t)(v >> 16); p[2] = (uint8_t)(v >> 8); p[3] = (uint8_t)v; }
static uint32_t get32(const uint8_t* p) { return (uint32_t)p[0] << 24 | (uint32_t)p[1] << 16 | (uint32_t)p[2] << 8 | p[3]; }

static void unpack_battery(const N64Handle* h, const uint8_t* blob, size_t size)
{
    if (blob == NULL || size < 8 || memcmp(blob, "N64B", 4) != 0 || get32(blob + 4) != 1) return;
    size_t o = 8;
    while (o + 8 <= size) {
        const uint8_t* tag = blob + o;
        uint32_t len = get32(blob + o + 4);
        o += 8;
        if (len > size - o) return;
        for (int i = 0; i < 4; i++) {
            if (memcmp(tag, kBatteryExts[i], 3) == 0) {
                char path[1200];
                battery_path(h, i, path, sizeof(path));
                write_file(path, blob + o, len);
            }
        }
        o += len;
    }
}

// MARK: public API

static bool ensure_dir(const char* path) { return mkdir(path, 0700) == 0 || errno == EEXIST; }

static void set_core_param(m64p_handle sec, const char* name, m64p_type type, const void* value)
{
    ConfigSetParameter(sec, name, type, value);
}

N64Handle* n64_create(const uint8_t* rom, size_t romSize, const uint8_t* battery, size_t batterySize,
                      const char* workDir, const char* dataDir)
{
    if (g_h != NULL || rom == NULL || romSize < 0x1000 || romSize > 64 * 1024 * 1024) return NULL;
    N64Handle* h = (N64Handle*)calloc(1, sizeof(N64Handle));
    if (h == NULL) return NULL;
    snprintf(g_n64_work_dir, sizeof(g_n64_work_dir), "%s/", workDir);
    snprintf(g_n64_data_dir, sizeof(g_n64_data_dir), "%s/", dataDir);
    snprintf(h->saveDir, sizeof(h->saveDir), "%ssave/", g_n64_work_dir);
    snprintf(h->statePath, sizeof(h->statePath), "%sstate.m64p", g_n64_work_dir);
    ensure_dir(workDir);
    ensure_dir(h->saveDir);
    pthread_mutex_init(&h->lock, NULL);
    pthread_cond_init(&h->cond, NULL);
    for (size_t i = 0; i < N64_SCREEN_WIDTH * N64_SCREEN_HEIGHT; i++) h->fb[i] = 0xFF000000u;

    if (CoreStartup(FRONTEND_API_VERSION, g_n64_work_dir, g_n64_data_dir, NULL, debug_callback, NULL,
                    state_callback) != M64ERR_SUCCESS) {
        free(h);
        return NULL;
    }
    m64p_handle core = NULL;
    ConfigOpenSection("Core", &core);
    int zero = 0, cached = 1;
    set_core_param(core, "R4300Emulator", M64TYPE_INT, &cached);   // cached interpreter, never a recompiler
    set_core_param(core, "OnScreenDisplay", M64TYPE_BOOL, &zero);
    set_core_param(core, "RandomizeInterrupt", M64TYPE_BOOL, &zero);   // deterministic (states, rewind)
    set_core_param(core, "SaveFilenameFormat", M64TYPE_INT, &zero);    // battery files named after the header
    set_core_param(core, "AutoStateSlotIncrement", M64TYPE_BOOL, &zero);
    set_core_param(core, "SaveSRAMPath", M64TYPE_STRING, h->saveDir);
    set_core_param(core, "SaveStatePath", M64TYPE_STRING, g_n64_work_dir);
    set_core_param(core, "SharedDataPath", M64TYPE_STRING, g_n64_data_dir);
    m64p_handle hle = NULL;
    if (ConfigOpenSection("Rsp-HLE", &hle) == M64ERR_SUCCESS) {
        const char* none = "";
        set_core_param(hle, "RspFallback", M64TYPE_STRING, none);   // never load another RSP plugin
    }

    if (CoreDoCommand(M64CMD_ROM_OPEN, (int)romSize, (void*)rom) != M64ERR_SUCCESS) {
        CoreShutdown();
        free(h);
        return NULL;
    }
    unpack_battery(h, battery, batterySize);

    rsphle_PluginStartup(HANDLE(kCoreProcs), NULL, debug_callback);
    n64rdp_rsp_startup(HANDLE(kCoreProcs), debug_callback);
    if (CoreAttachPlugin(M64PLUGIN_GFX, HANDLE(kGfxProcs)) != M64ERR_SUCCESS ||
        CoreAttachPlugin(M64PLUGIN_AUDIO, HANDLE(kAudioProcs)) != M64ERR_SUCCESS ||
        CoreAttachPlugin(M64PLUGIN_INPUT, HANDLE(kInputProcs)) != M64ERR_SUCCESS ||
        CoreAttachPlugin(M64PLUGIN_RSP, HANDLE(kRspProcs)) != M64ERR_SUCCESS) {
        CoreDetachPlugin(M64PLUGIN_GFX); CoreDetachPlugin(M64PLUGIN_AUDIO);
        CoreDetachPlugin(M64PLUGIN_INPUT); CoreDetachPlugin(M64PLUGIN_RSP);
        rsphle_PluginShutdown();
        n64rdp_rsp_shutdown();
        CoreDoCommand(M64CMD_ROM_CLOSE, 0, NULL);
        CoreShutdown();
        free(h);
        return NULL;
    }

    g_h = h;
    h->executing = true;
    h->turn = TURN_CORE;
    pthread_attr_t attr;
    pthread_attr_init(&attr);
    pthread_attr_setstacksize(&attr, 8 * 1024 * 1024);
    int err = pthread_create(&h->thread, &attr, core_thread, h);
    pthread_attr_destroy(&attr);
    if (err != 0) {
        g_h = NULL;
        h->executing = false;
    } else {
        // wait for the first vertical interrupt (or for the core to give up)
        pthread_mutex_lock(&h->lock);
        while (h->turn != TURN_HOST) pthread_cond_wait(&h->cond, &h->lock);
        pthread_mutex_unlock(&h->lock);
    }
    if (!h->executing) {
        if (err == 0) pthread_join(h->thread, NULL);
        g_h = NULL;
        CoreDetachPlugin(M64PLUGIN_GFX); CoreDetachPlugin(M64PLUGIN_AUDIO);
        CoreDetachPlugin(M64PLUGIN_INPUT); CoreDetachPlugin(M64PLUGIN_RSP);
        rsphle_PluginShutdown();
        n64rdp_rsp_shutdown();
        CoreDoCommand(M64CMD_ROM_CLOSE, 0, NULL);
        CoreShutdown();
        free(h);
        return NULL;
    }
    h->audioCount = 0;   // nothing before the first frame boundary
    h->frames = 0;
    return h;
}

void n64_destroy(N64Handle* h)
{
    if (h == NULL) return;
    if (h->executing) host_send(h, CMD_QUIT);
    pthread_join(h->thread, NULL);
    g_h = NULL;
    CoreDetachPlugin(M64PLUGIN_GFX);
    CoreDetachPlugin(M64PLUGIN_AUDIO);
    CoreDetachPlugin(M64PLUGIN_INPUT);
    CoreDetachPlugin(M64PLUGIN_RSP);
    rsphle_PluginShutdown();
    n64rdp_rsp_shutdown();
    CoreDoCommand(M64CMD_ROM_CLOSE, 0, NULL);
    CoreShutdown();
    pthread_mutex_destroy(&h->lock);
    pthread_cond_destroy(&h->cond);
    free(h);
}

void n64_reset(N64Handle* h)
{
    if (h->executing) host_send(h, CMD_RESET);
}

void n64_set_input(N64Handle* h, int port, uint32_t buttons, int8_t x, int8_t y)
{
    if (port < 0 || port >= N64_MAX_PLAYERS) return;
    BUTTONS b;
    b.Value = 0;
    b.R_DPAD = (buttons & N64_BTN_DRIGHT) != 0;
    b.L_DPAD = (buttons & N64_BTN_DLEFT) != 0;
    b.D_DPAD = (buttons & N64_BTN_DDOWN) != 0;
    b.U_DPAD = (buttons & N64_BTN_DUP) != 0;
    b.START_BUTTON = (buttons & N64_BTN_START) != 0;
    b.Z_TRIG = (buttons & N64_BTN_Z) != 0;
    b.B_BUTTON = (buttons & N64_BTN_B) != 0;
    b.A_BUTTON = (buttons & N64_BTN_A) != 0;
    b.R_CBUTTON = (buttons & N64_BTN_CRIGHT) != 0;
    b.L_CBUTTON = (buttons & N64_BTN_CLEFT) != 0;
    b.D_CBUTTON = (buttons & N64_BTN_CDOWN) != 0;
    b.U_CBUTTON = (buttons & N64_BTN_CUP) != 0;
    b.R_TRIG = (buttons & N64_BTN_R) != 0;
    b.L_TRIG = (buttons & N64_BTN_L) != 0;
    b.X_AXIS = x;
    b.Y_AXIS = y;
    h->pads[port] = b;
}

void n64_run_frame(N64Handle* h)
{
    if (h->executing) host_send(h, CMD_RUN);
}

const uint32_t* n64_framebuffer(const N64Handle* h) { return h->fb; }

double n64_frame_rate(const N64Handle* h)
{
    (void)h;
    return ROM_PARAMS.systemtype == SYSTEM_NTSC ? 60.0 : 50.0;
}

size_t n64_drain_audio(N64Handle* h, const float** out)
{
    // The host reads while the core is parked; the next frame starts writing from zero again.
    static float copy[AUDIO_CAP];
    size_t n = h->audioCount;
    memcpy(copy, h->audio, n * sizeof(float));
    h->audioCount = 0;
    *out = copy;
    return n;
}

void n64_discard_audio(N64Handle* h) { h->audioCount = 0; }

uint32_t n64_audio_rate(const N64Handle* h) { return h->audioRate; }

size_t n64_battery(N64Handle* h, uint8_t** out)
{
    uint8_t* files[4] = { NULL };
    size_t sizes[4] = { 0 };
    size_t total = 8;
    for (int i = 0; i < 4; i++) {
        char path[1200];
        battery_path(h, i, path, sizeof(path));
        files[i] = read_file(path, &sizes[i]);
        if (files[i]) total += 8 + sizes[i];
    }
    if (total == 8) { *out = NULL; return 0; }
    uint8_t* blob = (uint8_t*)malloc(total);
    if (blob == NULL) { for (int i = 0; i < 4; i++) free(files[i]); *out = NULL; return 0; }
    memcpy(blob, "N64B", 4);
    put32(blob + 4, 1);
    size_t o = 8;
    for (int i = 0; i < 4; i++) {
        if (!files[i]) continue;
        memcpy(blob + o, kBatteryExts[i], 3);
        blob[o + 3] = 0;
        put32(blob + o + 4, (uint32_t)sizes[i]);
        memcpy(blob + o + 8, files[i], sizes[i]);
        o += 8 + sizes[i];
        free(files[i]);
    }
    *out = blob;
    return total;
}

size_t n64_save_state(N64Handle* h, uint8_t** out)
{
    *out = NULL;
    if (!h->executing) return 0;
    remove(h->statePath);
    h->result = 0;
    host_send(h, CMD_SAVE);
    if (!h->result) return 0;
    size_t n = 0;
    *out = read_file(h->statePath, &n);
    remove(h->statePath);
    return n;
}

bool n64_load_state(N64Handle* h, const uint8_t* data, size_t size)
{
    // mupen64plus states are gzip files; the core checks the magic, version and every length
    // before it changes anything.
    if (!h->executing || data == NULL || size < 18 || data[0] != 0x1F || data[1] != 0x8B) return false;
    if (!write_file(h->statePath, data, size)) return false;
    h->result = 0;
    host_send(h, CMD_LOAD);
    remove(h->statePath);
    return h->result != 0;
}

void n64_free(void* p) { free(p); }

uint32_t n64_frame_counter(const N64Handle* h) { return h->frames; }

uint32_t n64_peek_rdram(const N64Handle* h, uint32_t address)
{
    (void)h;
    if (g_gfx.RDRAM == NULL) return 0;
    uint32_t w;
    memcpy(&w, g_gfx.RDRAM + (address & 0x7FFFFC), 4);   // stored in host order = the BE word's value
    return w;
}
