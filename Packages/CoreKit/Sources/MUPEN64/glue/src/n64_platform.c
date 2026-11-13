// Foldback's stand-ins for the mupen64plus-core files we do not compile (GPLv3, part of Foldback).
//
// - osal (files_*.c): every path the core asks for is our private work directory, or the data
//   directory holding the ROM database. State files are written with gzip level 1 (fast).
// - api/vidext.c: the video extension opens SDL windows and GL/Vulkan contexts. Our video plugin
//   never asks for one, so these entry points only report "not available".
// - main/eventloop.c, main/sdl_key_converter.c: SDL keyboard/joystick hotkeys. None here.
// - main/screenshot.c: needs libpng. Screenshots are taken by the app, not the core.
#include <stdio.h>
#include <string.h>
#include <sys/stat.h>
#include <zlib.h>

#include "api/m64p_types.h"
#include "api/vidext.h"
#include "main/eventloop.h"
#include "main/screenshot.h"
#include "osal/files.h"

extern char g_n64_work_dir[1024];
extern char g_n64_data_dir[1024];

// MARK: osal

int osal_mkdirp(const char* dirpath, int mode)
{
    char path[PATH_MAX];
    snprintf(path, sizeof(path), "%s", dirpath);
    for (char* p = path + 1; *p; p++) {
        if (*p == '/') {
            *p = 0;
            mkdir(path, (mode_t)mode);
            *p = '/';
        }
    }
    mkdir(path, (mode_t)mode);
    struct stat st;
    return (stat(path, &st) == 0 && S_ISDIR(st.st_mode)) ? 0 : 1;
}

const char* osal_get_shared_filepath(const char* filename, const char* firstsearch, const char* secondsearch)
{
    static char path[PATH_MAX];
    const char* dirs[3] = { firstsearch, secondsearch, g_n64_data_dir };
    for (int i = 0; i < 3; i++) {
        if (dirs[i] == NULL || dirs[i][0] == 0) continue;
        size_t len = strlen(dirs[i]);
        snprintf(path, sizeof(path), "%s%s%s", dirs[i], dirs[i][len - 1] == '/' ? "" : "/", filename);
        struct stat st;
        if (stat(path, &st) == 0 && S_ISREG(st.st_mode)) return path;
    }
    return NULL;
}

const char* osal_get_user_configpath(void) { return g_n64_work_dir; }
const char* osal_get_user_datapath(void) { return g_n64_work_dir; }
const char* osal_get_user_cachepath(void) { return g_n64_work_dir; }

FILE* osal_file_open(const char* filename, const char* mode) { return fopen(filename, mode); }

gzFile osal_gzopen(const char* filename, const char* mode)
{
    if (strcmp(mode, "wb") == 0) return gzopen(filename, "wb1");
    return gzopen(filename, mode);
}

// MARK: video extension (no windows, no GL)

m64p_error OverrideVideoFunctions(m64p_video_extension_functions* functions)
{
    (void)functions;
    return M64ERR_UNSUPPORTED;
}
int VidExt_InFullscreenMode(void) { return 0; }
int VidExt_VideoRunning(void) { return 0; }
m64p_error VidExt_GL_SwapBuffers(void) { return M64ERR_UNSUPPORTED; }

// MARK: event loop and screenshots

int event_set_core_defaults(void) { return 1; }
void event_initialize(void) {}
void event_sdl_keydown(int keysym, int keymod) { (void)keysym; (void)keymod; }
void event_sdl_keyup(int keysym, int keymod) { (void)keysym; (void)keymod; }
int event_gameshark_active(void) { return 0; }
void event_set_gameshark(int active) { (void)active; }

void ScreenshotRomOpen(void) {}
void TakeScreenshot(int iFrameNumber) { (void)iFrameNumber; }
