// Foldback's minimal stand-in for the SDL2 header that mupen64plus-core includes. Not SDL.
//
// The core only uses a handful of SDL calls in the files we compile: recursive mutexes (savestates,
// cheats), a millisecond clock and sleep (speed limiter, Bio Pak), and SDL_WasInit/SDL_Quit/
// SDL_PumpEvents in the front-end paths. Everything here is implemented with POSIX threads and
// clocks; there is no window, event, joystick, audio or video code at all. Part of Foldback (GPLv3).
#ifndef FOLDBACK_SDL_SHIM_H
#define FOLDBACK_SDL_SHIM_H

#include <pthread.h>
#include <stdint.h>
#include <stdlib.h>
#include <time.h>
#include <unistd.h>

#define SDL_INIT_TIMER 0x00000001u
#define SDL_INIT_AUDIO 0x00000010u
#define SDL_INIT_VIDEO 0x00000020u
#define SDL_INIT_JOYSTICK 0x00000200u

typedef struct SDL_mutex { pthread_mutex_t m; } SDL_mutex;

static inline SDL_mutex* SDL_CreateMutex(void)
{
    SDL_mutex* mx = (SDL_mutex*)malloc(sizeof(SDL_mutex));
    if (mx == NULL) return NULL;
    pthread_mutexattr_t attr;
    pthread_mutexattr_init(&attr);
    pthread_mutexattr_settype(&attr, PTHREAD_MUTEX_RECURSIVE);  // SDL mutexes are recursive
    pthread_mutex_init(&mx->m, &attr);
    pthread_mutexattr_destroy(&attr);
    return mx;
}

static inline int SDL_LockMutex(SDL_mutex* mx) { return mx ? pthread_mutex_lock(&mx->m) : -1; }
static inline int SDL_UnlockMutex(SDL_mutex* mx) { return mx ? pthread_mutex_unlock(&mx->m) : -1; }
static inline void SDL_DestroyMutex(SDL_mutex* mx)
{
    if (mx == NULL) return;
    pthread_mutex_destroy(&mx->m);
    free(mx);
}

static inline uint32_t SDL_GetTicks(void)
{
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (uint32_t)((uint64_t)ts.tv_sec * 1000u + (uint64_t)ts.tv_nsec / 1000000u);
}

static inline void SDL_Delay(uint32_t ms) { usleep((useconds_t)ms * 1000u); }

static inline uint32_t SDL_WasInit(uint32_t flags) { (void)flags; return 0; }
static inline int SDL_InitSubSystem(uint32_t flags) { (void)flags; return -1; }
static inline void SDL_QuitSubSystem(uint32_t flags) { (void)flags; }
static inline void SDL_Quit(void) {}
static inline void SDL_PumpEvents(void) {}
static inline const char* SDL_GetError(void) { return "SDL is not available"; }

#endif
