// Our wrapper around the vendored mGBA core (GBA only). Not part of mGBA; it only calls
// mGBA's public mCore interface and leaves every mGBA file unmodified.
#include "MGBAGlue.h"

#include <mgba/core/core.h>
#include <mgba/core/log.h>
#include <mgba/core/serialize.h>
#include <mgba/gba/core.h>
#include <mgba/internal/gba/gba.h>
#include <mgba-util/audio-buffer.h>
#include <mgba-util/audio-resampler.h>
#include <mgba-util/vfs.h>

#include <pthread.h>

#define AUDIO_OUT_CAPACITY 8192

struct MGBAHandle {
    struct mCore* core;
    mColor native[MGBA_WIDTH * MGBA_HEIGHT];   // mGBA's 32-bit output (0xXXBBGGRR)
    uint32_t bgra[MGBA_WIDTH * MGBA_HEIGHT];   // converted for the app
    struct mAudioResampler resampler;
    struct mAudioBuffer resampled;              // stereo at audioRate
    double audioRate;
    int16_t stereo[AUDIO_OUT_CAPACITY * 2];
    float mono[AUDIO_OUT_CAPACITY];
};

// mGBA logs to stdout when no logger is installed. Install a silent one, once per process.
static void _silentLog(struct mLogger* logger, int category, enum mLogLevel level, const char* format, va_list args) {
    (void) logger; (void) category; (void) level; (void) format; (void) args;
}
static struct mLogger _silentLogger = { .log = _silentLog, .filter = NULL };
static pthread_once_t _loggerOnce = PTHREAD_ONCE_INIT;
static void _installLogger(void) { mLogSetDefaultLogger(&_silentLogger); }

bool mgba_is_rom(const uint8_t* rom, size_t size) {
    struct VFile* vf = VFileFromConstMemory(rom, size);
    if (!vf) {
        return false;
    }
    bool ok = GBAIsROM(vf);
    vf->close(vf);
    return ok;
}

MGBAHandle* mgba_create(const uint8_t* rom, size_t romSize, const uint8_t* save, size_t saveSize,
                        double audioRate) {
    pthread_once(&_loggerOnce, _installLogger);
    if (!mgba_is_rom(rom, romSize)) {
        return NULL;
    }
    MGBAHandle* h = calloc(1, sizeof(*h));
    if (!h) {
        return NULL;
    }
    struct mCore* core = GBACoreCreate();
    if (!core) {
        free(h);
        return NULL;
    }
    mCoreInitConfig(core, NULL);
    if (!core->init(core)) {
        mCoreConfigDeinit(&core->config);
        free(core);
        free(h);
        return NULL;
    }
    h->core = core;

    // Built-in HLE BIOS only (no BIOS file), boot straight into the cartridge.
    struct mCoreOptions opts = {
        .useBios = false,
        .skipBios = true,
        .volume = 0x100,
    };
    mCoreConfigLoadDefaults(&core->config, &opts);
    mCoreLoadForeignConfig(core, &core->config);
    core->opts.useBios = false;
    core->opts.skipBios = true;

    core->setVideoBuffer(core, h->native, MGBA_WIDTH);

    // Both VFiles copy their contents, so the caller's buffers can go away.
    struct VFile* romVf = VFileMemChunk(rom, romSize);
    if (!romVf || !core->loadROM(core, romVf)) {
        if (romVf) {
            romVf->close(romVf);
        }
        mgba_destroy(h);
        return NULL;
    }
    struct VFile* saveVf = VFileMemChunk(save && saveSize ? save : NULL, save ? saveSize : 0);
    if (saveVf) {
        core->loadSave(core, saveVf);
    }

    h->audioRate = audioRate;
    mAudioBufferInit(&h->resampled, AUDIO_OUT_CAPACITY, 2);
    mAudioResamplerInit(&h->resampler, mINTERPOLATOR_SINC);
    mAudioResamplerSetDestination(&h->resampler, &h->resampled, audioRate);

    core->reset(core);
    return h;
}

void mgba_destroy(MGBAHandle* h) {
    if (!h) {
        return;
    }
    if (h->core) {
        h->core->unloadROM(h->core);
        mCoreConfigDeinit(&h->core->config);
        h->core->deinit(h->core);
    }
    if (h->resampled.data.data) {
        mAudioResamplerDeinit(&h->resampler);
        mAudioBufferDeinit(&h->resampled);
    }
    free(h);
}

void mgba_reset(MGBAHandle* h) {
    h->core->reset(h->core);
    mgba_discard_audio(h);
}

static void _convertFrame(MGBAHandle* h) {
    const mColor* src = h->native;
    uint32_t* dst = h->bgra;
    for (size_t i = 0; i < MGBA_WIDTH * MGBA_HEIGHT; ++i) {
        uint32_t c = src[i];
        dst[i] = 0xFF000000u | ((c & 0xFFu) << 16) | (c & 0xFF00u) | ((c >> 16) & 0xFFu);
    }
}

static void _resample(MGBAHandle* h) {
    struct mCore* core = h->core;
    struct mAudioBuffer* source = core->getAudioBuffer(core);
    mAudioResamplerSetSource(&h->resampler, source, core->audioSampleRate(core), true);
    mAudioResamplerProcess(&h->resampler);
    if (mAudioBufferFull(&h->resampled)) {
        // Nobody has drained for ~10 frames: drop the stale output rather than let mGBA's
        // buffer back up (which would add latency once draining resumes).
        mAudioBufferClear(&h->resampled);
        mAudioResamplerProcess(&h->resampler);
    }
}

void mgba_run_frame(MGBAHandle* h, uint32_t keys) {
    struct mCore* core = h->core;
    core->setKeys(core, keys & 0x3FF);
    core->runFrame(core);
    _convertFrame(h);
    _resample(h);
}

const uint32_t* mgba_framebuffer(const MGBAHandle* h) {
    return h->bgra;
}

size_t mgba_drain_audio(MGBAHandle* h, const float** out) {
    size_t n = mAudioBufferRead(&h->resampled, h->stereo, AUDIO_OUT_CAPACITY);
    for (size_t i = 0; i < n; ++i) {
        h->mono[i] = ((float) h->stereo[i * 2] + (float) h->stereo[i * 2 + 1]) * (0.5f / 32768.f);
    }
    *out = h->mono;
    return n;
}

void mgba_discard_audio(MGBAHandle* h) {
    mAudioBufferClear(&h->resampled);
}

size_t mgba_savedata(MGBAHandle* h, uint8_t** out) {
    void* sram = NULL;
    size_t size = h->core->savedataClone(h->core, &sram);
    if (!size) {
        free(sram);
        *out = NULL;
        return 0;
    }
    *out = sram;
    return size;
}

size_t mgba_save_state(MGBAHandle* h, uint8_t** out) {
    *out = NULL;
    struct VFile* vf = VFileMemChunk(NULL, 0);
    if (!vf) {
        return 0;
    }
    if (!mCoreSaveStateNamed(h->core, vf, SAVESTATE_RTC)) {
        vf->close(vf);
        return 0;
    }
    ssize_t size = vf->size(vf);
    uint8_t* buffer = size > 0 ? malloc((size_t) size) : NULL;
    if (buffer) {
        vf->seek(vf, 0, SEEK_SET);
        if (vf->read(vf, buffer, (size_t) size) != size) {
            free(buffer);
            buffer = NULL;
        }
    }
    vf->close(vf);
    if (!buffer) {
        return 0;
    }
    *out = buffer;
    return (size_t) size;
}

bool mgba_load_state(MGBAHandle* h, const uint8_t* data, size_t size) {
    if ((ssize_t) size < (ssize_t) h->core->stateSize(h->core)) {
        return false;
    }
    struct VFile* vf = VFileFromConstMemory(data, size);
    if (!vf) {
        return false;
    }
    bool ok = mCoreLoadStateNamed(h->core, vf, SAVESTATE_RTC);
    vf->close(vf);
    if (ok) {
        _convertFrame(h);
        mgba_discard_audio(h);
    }
    return ok;
}

void mgba_free(void* p) {
    free(p);
}

uint8_t mgba_peek(MGBAHandle* h, uint32_t address) {
    return (uint8_t) h->core->rawRead8(h->core, address, -1);
}

uint32_t mgba_frame_counter(const MGBAHandle* h) {
    return h->core->frameCounter(h->core);
}

uint32_t mgba_native_audio_rate(const MGBAHandle* h) {
    return h->core->audioSampleRate(h->core);
}
