// Our C API over the vendored melonDS core (GPL-3.0-or-later, ThirdParty/melonds). Part of Foldback.
//
// One NDS (never a DSi) per handle, built with melonDS's FreeBIOS and its generated firmware, and
// direct-booted into the cartridge. This file also provides the `melonDS::Platform` functions the
// core calls back into: no file access (every open fails, so no BIOS/firmware file can ever be
// read), no network or local multiplayer (packets go nowhere), no microphone or camera.
#include "MelonDSGlue.h"

#include <algorithm>
#include <chrono>
#include <condition_variable>
#include <cstdlib>
#include <cstring>
#include <ctime>
#include <memory>
#include <mutex>
#include <thread>
#include <vector>

#include "NDS.h"
#include "NDSCart.h"
#include "GPU.h"
#include "Platform.h"
#include "Savestate.h"
#include "SPI_Firmware.h"
#include "FreeBIOS.h"
#include "Args.h"

using namespace melonDS;

struct MelonDSHandle {
    std::unique_ptr<NDS> nds;
    std::vector<uint32_t> frame = std::vector<uint32_t>(256 * 384, 0xFF000000);
    std::vector<int16_t> raw = std::vector<int16_t>(2 * 8192);
    std::vector<float> audio;
    std::vector<float> handedOut;  // what the last drain returned; valid until the next call
    bool threaded3D = false;
    bool saveUsed = false;  // a save was loaded, or the game has written its save memory
};

static void setClock(NDS& nds) {
    time_t now = time(nullptr);
    struct tm t;
    localtime_r(&now, &t);
    nds.RTC.SetDateTime(t.tm_year + 1900, t.tm_mon + 1, t.tm_mday, t.tm_hour, t.tm_min, t.tm_sec);
}

static void bootCartridge(MelonDSHandle* h) {
    h->nds->Reset();
    // FreeBIOS cannot run the firmware's boot menu, so melonDS always needs a direct boot here.
    h->nds->SetupDirectBoot("game.nds");
    setClock(*h->nds);
    h->nds->Start();
}

static void applyRenderSettings(MelonDSHandle* h) {
    RendererSettings settings {};
    settings.ScaleFactor = 1;
    settings.Threaded = h->threaded3D;
    h->nds->GetRenderer().SetRenderSettings(settings);
}

extern "C" {

bool melonds_is_rom(const uint8_t* rom, size_t size) {
    if (!rom || size < 0x1000) return false;
    uint32_t arm9Off, arm9Size, arm7Off, arm7Size;
    memcpy(&arm9Off, rom + 0x20, 4);
    memcpy(&arm9Size, rom + 0x2C, 4);
    memcpy(&arm7Off, rom + 0x30, 4);
    memcpy(&arm7Size, rom + 0x3C, 4);
    if (arm9Off < 0x200 || arm7Off < 0x200) return false;
    if (uint64_t(arm9Off) + arm9Size > size || uint64_t(arm7Off) + arm7Size > size) return false;
    if (arm9Size == 0 || arm7Size == 0) return false;
    return true;
}

MelonDSHandle* melonds_create(const uint8_t* rom, size_t romSize, const uint8_t* save, size_t saveSize,
                              double audioRate, bool threaded3D) {
    if (!melonds_is_rom(rom, romSize) || romSize > 512u * 1024 * 1024) return nullptr;
    // DSi-only titles (unit code 3) can't run on an NDS.
    if ((rom[0x12] & 0x03) == 0x03) return nullptr;

    auto h = std::make_unique<MelonDSHandle>();
    h->threaded3D = threaded3D;

    NDSArgs args {};  // FreeBIOS ARM9/ARM7 images and a generated firmware are the defaults
    args.JIT = std::nullopt;
    args.OutputSampleRate = audioRate;
    args.Interpolation = AudioInterpolation::None;
    h->nds = std::make_unique<NDS>(std::move(args), h.get());

    NDSCart::NDSCartArgs cartArgs {};
    if (save && saveSize > 0) {
        cartArgs.SRAM = std::make_unique<u8[]>(saveSize);
        memcpy(cartArgs.SRAM.get(), save, saveSize);
        cartArgs.SRAMLength = u32(saveSize);
        h->saveUsed = true;
    }
    auto cart = NDSCart::ParseROM(rom, u32(romSize), h.get(), std::move(cartArgs));
    if (!cart) return nullptr;
    h->nds->SetNDSCart(std::move(cart));
    applyRenderSettings(h.get());
    bootCartridge(h.get());
    h->audio.reserve(8192);
    return h.release();
}

void melonds_destroy(MelonDSHandle* h) {
    if (!h) return;
    h->nds->Stop();
    delete h;
}

void melonds_reset(MelonDSHandle* h) {
    bootCartridge(h);
    melonds_discard_audio(h);
}

void melonds_run_frame(MelonDSHandle* h, uint32_t keys, bool touching, uint16_t x, uint16_t y) {
    NDS& nds = *h->nds;
    nds.SetKeyMask(~keys & 0xFFF);  // melonDS keys are active-low
    if (touching)
        nds.TouchScreen(std::min<uint16_t>(x, 255), std::min<uint16_t>(y, 191));
    else
        nds.ReleaseScreen();
    nds.RunFrame();

    void* top = nullptr;
    void* bottom = nullptr;
    if (nds.GPU.GetFramebuffers(&top, &bottom) && top && bottom) {
        memcpy(h->frame.data(), top, 256 * 192 * 4);
        memcpy(h->frame.data() + 256 * 192, bottom, 256 * 192 * 4);
    }

    // Stereo s16 at the output rate -> mono float.
    for (;;) {
        int n = nds.SPU.ReadOutput(h->raw.data(), int(h->raw.size() / 2));
        if (n <= 0) break;
        if (h->audio.size() + size_t(n) > 48000) break;  // never grow without bound if nobody drains
        for (int i = 0; i < n; i++)
            h->audio.push_back((float(h->raw[2 * i]) + float(h->raw[2 * i + 1])) * (0.5f / 32768.0f));
        if (n < int(h->raw.size() / 2)) break;
    }
}

const uint32_t* melonds_framebuffer(const MelonDSHandle* h) { return h->frame.data(); }

size_t melonds_drain_audio(MelonDSHandle* h, const float** out) {
    h->handedOut.swap(h->audio);
    h->audio.clear();
    *out = h->handedOut.data();
    return h->handedOut.size();
}

void melonds_discard_audio(MelonDSHandle* h) {
    int16_t scratch[2 * 1024];
    while (h->nds->SPU.ReadOutput(scratch, 1024) == 1024) {}
    h->audio.clear();
}

size_t melonds_savedata(MelonDSHandle* h, uint8_t** out) {
    *out = nullptr;
    const u8* mem = h->nds->GetNDSSave();
    u32 len = h->nds->GetNDSSaveLength();
    if (!mem || len == 0 || !h->saveUsed) return 0;
    auto* copy = static_cast<uint8_t*>(malloc(len));
    if (!copy) return 0;
    memcpy(copy, mem, len);
    *out = copy;
    return len;
}

size_t melonds_save_state(MelonDSHandle* h, uint8_t** out) {
    *out = nullptr;
    Savestate state;
    if (state.Error) return 0;
    h->nds->DoSavestate(&state);
    if (state.Error) return 0;
    size_t len = state.Length();
    auto* copy = static_cast<uint8_t*>(malloc(len));
    if (!copy) return 0;
    memcpy(copy, state.Buffer(), len);
    *out = copy;
    return len;
}

bool melonds_load_state(MelonDSHandle* h, const uint8_t* data, size_t size) {
    if (!data || size < 16 || size > 0xFFFFFFFFu) return false;
    // Back up first: a state that fails half-way would leave the machine inconsistent.
    Savestate backup;
    if (backup.Error) return false;
    h->nds->DoSavestate(&backup);
    if (backup.Error) return false;

    std::vector<u8> copy(data, data + size);  // Savestate wants a mutable buffer
    Savestate state(copy.data(), u32(size), false);
    if (!state.Error && h->nds->DoSavestate(&state) && !state.Error) {
        melonds_discard_audio(h);
        return true;
    }
    backup.Rewind(false);
    h->nds->DoSavestate(&backup);
    return false;
}

void melonds_free(void* p) { free(p); }

uint32_t melonds_frame_counter(const MelonDSHandle* h) { return h->nds->NumFrames; }

uint32_t melonds_peek_main_ram(const MelonDSHandle* h, uint32_t address) {
    uint32_t v;
    memcpy(&v, h->nds->MainRAM + (address & h->nds->MainRAMMask & ~3u), 4);
    return v;
}

}  // extern "C"

// MARK: - melonDS platform hooks

namespace melonDS::Platform {

void SignalStop(StopReason, void*) {}

std::string GetLocalFilePath(const std::string& filename) { return filename; }

// No file access at all: nothing (BIOS, firmware, NAND, SD images) can ever be read or written.
FileHandle* OpenFile(const std::string&, FileMode) { return nullptr; }
FileHandle* OpenLocalFile(const std::string&, FileMode) { return nullptr; }
bool FileExists(const std::string&) { return false; }
bool LocalFileExists(const std::string&) { return false; }
bool CheckFileWritable(const std::string&) { return false; }
bool CheckLocalFileWritable(const std::string&) { return false; }
bool CloseFile(FileHandle*) { return false; }
bool IsEndOfFile(FileHandle*) { return true; }
bool FileReadLine(char*, int, FileHandle*) { return false; }
u64 FilePosition(FileHandle*) { return 0; }
bool FileSeek(FileHandle*, s64, FileSeekOrigin) { return false; }
void FileRewind(FileHandle*) {}
u64 FileRead(void*, u64, u64, FileHandle*) { return 0; }
bool FileFlush(FileHandle*) { return false; }
u64 FileWrite(const void*, u64, u64, FileHandle*) { return 0; }
u64 FileWriteFormatted(FileHandle*, const char*, ...) { return 0; }
u64 FileLength(FileHandle*) { return 0; }

void Log(LogLevel, const char*, ...) {}

struct Thread {
    std::thread t;
};
Thread* Thread_Create(std::function<void()> func) { return new Thread{std::thread(std::move(func))}; }
void Thread_Free(Thread* thread) {
    if (!thread) return;
    if (thread->t.joinable()) thread->t.detach();
    delete thread;
}
void Thread_Wait(Thread* thread) {
    if (thread && thread->t.joinable()) thread->t.join();
}

struct Semaphore {
    std::mutex m;
    std::condition_variable cv;
    int count = 0;
};
Semaphore* Semaphore_Create() { return new Semaphore(); }
void Semaphore_Free(Semaphore* s) { delete s; }
void Semaphore_Reset(Semaphore* s) {
    std::lock_guard<std::mutex> lock(s->m);
    s->count = 0;
}
void Semaphore_Wait(Semaphore* s) {
    std::unique_lock<std::mutex> lock(s->m);
    s->cv.wait(lock, [s] { return s->count > 0; });
    s->count--;
}
bool Semaphore_TryWait(Semaphore* s, int timeout_ms) {
    std::unique_lock<std::mutex> lock(s->m);
    if (timeout_ms == 0) {
        if (s->count == 0) return false;
    } else if (!s->cv.wait_for(lock, std::chrono::milliseconds(timeout_ms), [s] { return s->count > 0; })) {
        return false;
    }
    s->count--;
    return true;
}
void Semaphore_Post(Semaphore* s, int count) {
    {
        std::lock_guard<std::mutex> lock(s->m);
        s->count += count;
    }
    if (count == 1) s->cv.notify_one(); else s->cv.notify_all();
}

struct Mutex {
    std::mutex m;
};
Mutex* Mutex_Create() { return new Mutex(); }
void Mutex_Free(Mutex* m) { delete m; }
void Mutex_Lock(Mutex* m) { m->m.lock(); }
void Mutex_Unlock(Mutex* m) { m->m.unlock(); }
bool Mutex_TryLock(Mutex* m) { return m->m.try_lock(); }

void Sleep(u64 usecs) { std::this_thread::sleep_for(std::chrono::microseconds(usecs)); }
u64 GetMSCount() {
    using namespace std::chrono;
    return u64(duration_cast<milliseconds>(steady_clock::now().time_since_epoch()).count());
}
u64 GetUSCount() {
    using namespace std::chrono;
    return u64(duration_cast<microseconds>(steady_clock::now().time_since_epoch()).count());
}

// The app reads saves back through melonds_savedata; this only notes that there is one now.
void WriteNDSSave(const u8*, u32, u32, u32, void* userdata) {
    if (userdata) static_cast<MelonDSHandle*>(userdata)->saveUsed = true;
}
void WriteGBASave(const u8*, u32, u32, u32, void*) {}
void WriteFirmware(const Firmware&, u32, u32, void*) {}
void WriteDateTime(int, int, int, int, int, int, void*) {}

// No local multiplayer and no network: every send is dropped, nothing is ever received.
void MP_Begin(void*) {}
void MP_End(void*) {}
int MP_SendPacket(u8*, int, u64, void*) { return 0; }
int MP_RecvPacket(u8*, u64*, void*) { return 0; }
int MP_SendCmd(u8*, int, u64, void*) { return 0; }
int MP_SendReply(u8*, int, u64, u16, void*) { return 0; }
int MP_SendAck(u8*, int, u64, void*) { return 0; }
int MP_RecvHostPacket(u8*, u64*, void*) { return 0; }
u16 MP_RecvReplies(u8*, u64, u16, void*) { return 0; }
int Net_SendPacket(u8*, int, void*) { return 0; }
int Net_RecvPacket(u8*, void*) { return 0; }

void Camera_Start(int, void*) {}
void Camera_Stop(int, void*) {}
void Camera_CaptureFrame(int, u32*, int, int, bool, void*) {}

void Mic_Start(void*) {}
void Mic_Stop(void*) {}
int Mic_ReadInput(s16*, int, void*) { return 0; }

AACDecoder* AAC_Init() { return nullptr; }
void AAC_DeInit(AACDecoder*) {}
bool AAC_Configure(AACDecoder*, int, int) { return false; }
bool AAC_DecodeFrame(AACDecoder*, const void*, int, void*, int) { return false; }

bool Addon_KeyDown(KeyType, void*) { return false; }
void Addon_RumbleStart(u32, void*) {}
void Addon_RumbleStop(void*) {}
float Addon_MotionQuery(MotionQueryType, void*) { return 0; }

DynamicLibrary* DynamicLibrary_Load(const char*) { return nullptr; }
void DynamicLibrary_Unload(DynamicLibrary*) {}
void* DynamicLibrary_LoadFunction(DynamicLibrary*, const char*) { return nullptr; }

}  // namespace melonDS::Platform
