// paraLLEl-RDP (MIT, vendored unmodified in Sources/MUPEN64/parallel-rdp) behind our mupen64plus glue, on MoltenVK.
// Part of Relics: Consoles (GPLv3). Measured in docs/n64-rdp-spike.md. The command-stream handling follows the protocol every
// paraLLEl-RDP integration uses (DPC_CURRENT..DPC_END from RDRAM or, with the XBUS bit, from DMEM; commands may
// straddle two ProcessRDPList calls; SyncFull raises the DP interrupt), written here from the RDP documentation.
#include "volk_rename.h"   // before any Vulkan header: volk's globals must not clash with MoltenVK
#include "rdp_device.hpp"
#include "context.hpp"
#include "device.hpp"

#include <TargetConditionals.h>
#include <dlfcn.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>
#include <mach/mach_time.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <memory>
#include <mutex>
#include <string>
#include <vector>

extern "C" {
#include "api/m64p_plugin.h"
#include "n64_rdp.h"
#include "Mupen64Glue.h"
#include "N64PipelineCache.h"
}

#if TARGET_OS_IPHONE && !TARGET_OS_SIMULATOR
// MoltenVK is linked statically on iOS devices; its ICD entry point avoids volk's vkGetInstanceProcAddr global.
extern "C" PFN_vkVoidFunction vk_icdGetInstanceProcAddr(VkInstance instance, const char* name);
#endif

namespace {

GFX_INFO gfx;
std::unique_ptr<Vulkan::Context> ctx;
std::unique_ptr<Vulkan::Device> dev;
std::unique_ptr<RDP::CommandProcessor> proc;
bool synchronous = true;
std::string info;
int status = N64_RENDERER_VI_UNAVAILABLE;

// Persistent VkPipelineCache (N64PipelineCache.h). The lock only guards against a save from the host racing a save
// from the core thread's shutdown, which the glue's park handshake already rules out.
std::mutex cacheLock;
std::string cachePath;
size_t cacheSavedSize = 0;
const char* cacheNote = "";

uint32_t cmdData[0x00040000 >> 2];
int cmdCur = 0, cmdPtr = 0;

N64RdpStats stats;
double nestedRdpMs = 0;
std::vector<RDP::RGBA> colors;

// Length of each RDP command in 64-bit words (0x08-0x0F are the triangles, 0x24/0x25 texture rectangles).
const unsigned kCmdLen[64] = {
    1, 1, 1, 1, 1, 1, 1, 1, 4, 6, 12, 14, 12, 14, 20, 22,
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    1, 1, 1, 1, 2, 2, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
};

enum { DP_STATUS_XBUS = 1, MI_INTR_DP = 0x20 };

void collect_gpu_time()
{
    if (!dev) return;
    dev->timestamp_log([](const std::string& tag, const Vulkan::TimestampIntervalReport& r) {
        if (tag == "render-pass")   // whole RDP render passes; the other GPU tags are nested inside
            stats.gpuRenderMs += r.time_per_frame_context * 1000.0 * stats.frames;
    });
    dev->timestamp_log_reset();
}

N64PipelineCacheID cache_id()
{
    N64PipelineCacheID id;
    const VkPhysicalDeviceProperties& p = dev->get_gpu_properties();
    id.vendorID = p.vendorID;
    id.deviceID = p.deviceID;
    id.driverVersion = p.driverVersion;
    memcpy(id.uuid, p.pipelineCacheUUID, 16);
    return id;
}

/// Before the CommandProcessor exists (its pipelines are created through this cache). Any problem: a fresh cache.
bool cacheTrial = false;   // a loaded cache whose first frame hasn't been shown yet (the ".loading" sentinel exists)

std::string sentinel_path() { return cachePath + ".loading"; }

void load_pipeline_cache()
{
    std::lock_guard<std::mutex> guard(cacheLock);
    cacheSavedSize = 0;
    cacheTrial = false;
    bool loaded = false;
    if (!cachePath.empty()) {
        // A cache that passed every check but then crashed or hung the driver last time leaves the sentinel behind:
        // never feed it to Vulkan again.
        if (access(sentinel_path().c_str(), F_OK) == 0) {
            unlink(cachePath.c_str());
            unlink(sentinel_path().c_str());
        }
        const int fd = open(cachePath.c_str(), O_RDONLY | O_CLOEXEC);
        if (fd >= 0) try {
            struct stat st;
            if (fstat(fd, &st) == 0 && S_ISREG(st.st_mode) && st.st_size >= N64_PIPELINE_CACHE_HEADER_SIZE
                && st.st_size <= (off_t)N64_PIPELINE_CACHE_HEADER_SIZE + N64_PIPELINE_CACHE_MAX_PAYLOAD) {
                std::vector<uint8_t> file((size_t)st.st_size);   // may throw: caught below, cache discarded
                size_t got = 0;
                while (got < file.size()) {
                    const ssize_t n = read(fd, file.data() + got, file.size() - got);
                    if (n <= 0) break;
                    got += (size_t)n;
                }
                const N64PipelineCacheID id = cache_id();
                size_t off = 0, size = 0;
                if (got == file.size() && n64pc_validate(file.data(), file.size(), &id, &off, &size)) {
                    const int s = open(sentinel_path().c_str(), O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, 0600);
                    if (s >= 0) close(s);
                    cacheTrial = true;
                    if (dev->init_pipeline_cache(file.data() + off, size)) {
                        loaded = true;
                        cacheSavedSize = size;
                    }
                }
            }
            close(fd);
            if (!loaded) unlink(cachePath.c_str());   // stale, corrupt or from another GPU/driver
        } catch (...) {
            close(fd);
            unlink(cachePath.c_str());
            loaded = false;
        }
        if (!loaded && cacheTrial) {
            unlink(sentinel_path().c_str());
            cacheTrial = false;
        }
    }
    if (!loaded) dev->init_pipeline_cache(nullptr, 0);
    cacheNote = loaded ? " | pipeline cache loaded" : (cachePath.empty() ? "" : " | pipeline cache new");
}

void save_pipeline_cache_locked()
{
    if (!dev || cachePath.empty()) return;
    const size_t size = dev->get_pipeline_cache_size();
    if (size == 0 || size == cacheSavedSize || size > N64_PIPELINE_CACHE_MAX_PAYLOAD) return;
    std::vector<uint8_t> file(N64_PIPELINE_CACHE_HEADER_SIZE + size);
    // The cache may grow between the two calls (pipelines compile on worker threads); Granite then fails the read
    // (VK_INCOMPLETE) and the next save catches up.
    if (!dev->get_pipeline_cache_data(file.data() + N64_PIPELINE_CACHE_HEADER_SIZE, size)) return;
    const N64PipelineCacheID id = cache_id();
    n64pc_make_header(file.data(), &id, file.data() + N64_PIPELINE_CACHE_HEADER_SIZE, size);
    const std::string tmp = cachePath + ".tmp";
    const int fd = open(tmp.c_str(), O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, 0600);
    if (fd < 0) return;
    size_t put = 0;
    while (put < file.size()) {
        const ssize_t n = write(fd, file.data() + put, file.size() - put);
        if (n <= 0) break;
        put += (size_t)n;
    }
    const bool closed = close(fd) == 0;
    const bool ok = put == file.size() && closed;
    if (ok && rename(tmp.c_str(), cachePath.c_str()) == 0) cacheSavedSize = size;
    else unlink(tmp.c_str());
}

}  // namespace

extern "C" void n64rdp_set_pipeline_cache_path(const char* path)
{
    std::lock_guard<std::mutex> guard(cacheLock);
    cachePath = path ? path : "";
}

extern "C" void n64rdp_save_pipeline_cache(void)
{
    std::lock_guard<std::mutex> guard(cacheLock);
    save_pipeline_cache_locked();
}

extern "C" int n64rdp_status(void) { return status; }

extern "C" double n64rdp_now_ms(void)
{
    static mach_timebase_info_data_t tb;
    if (tb.denom == 0) mach_timebase_info(&tb);
    return (double)mach_absolute_time() * tb.numer / tb.denom / 1e6;
}

extern "C" double n64rdp_rdp_nested_ms(void) { return nestedRdpMs; }

extern "C" void n64rdp_add_rsp_ms(double ms, bool hle)
{
    if (hle) stats.hleMs += ms;
    else stats.rspMs += ms;
}

namespace {
bool gfx_init_inner();
}

extern "C" bool n64rdp_gfx_init(const void* gfxInfo)
{
    gfx = *(const GFX_INFO*)gfxInfo;
    cmdCur = cmdPtr = 0;
    bool ok = false;
    try {
        ok = gfx_init_inner();
    } catch (...) {   // Granite/paraLLEl don't throw by design, but allocation can: fall back, never crash
        info = "the N64 renderer failed to start (exception)";
        ok = false;
    }
    if (!ok) {
        proc.reset();
        dev.reset();
        ctx.reset();
    }
    return ok;
}

namespace {
bool gfx_init_inner()
{
    // Where Vulkan can't exist (simulator, Mac tests without MoltenVK) the VI fallback is expected; on a device a
    // failure is reported to the player.
#if TARGET_OS_IPHONE && !TARGET_OS_SIMULATOR
    status = N64_RENDERER_VI_FAILED;
#else
    status = N64_RENDERER_VI_UNAVAILABLE;
#endif
#if TARGET_OS_SIMULATOR
    if (true) {   // opens the block the shared failure path below closes
        info = "no Vulkan in the simulator (MoltenVK ships no simulator slice)";
        return false;
    }
    {
#elif TARGET_OS_IPHONE
    if (!Vulkan::Context::init_loader((PFN_vkGetInstanceProcAddr)vk_icdGetInstanceProcAddr)) {
#else
    // Mac bench: GRANITE_VULKAN_LIBRARY = path of libMoltenVK.dylib. N64RDP_USE_ICD=1 goes through MoltenVK's ICD
    // entry point instead, exactly as the iOS build does, to check that path on the Mac.
    PFN_vkGetInstanceProcAddr icd = nullptr;
    if (getenv("N64RDP_USE_ICD")) {
        void* lib = dlopen(getenv("GRANITE_VULKAN_LIBRARY"), RTLD_LOCAL | RTLD_NOW);
        icd = lib ? (PFN_vkGetInstanceProcAddr)dlsym(lib, "vk_icdGetInstanceProcAddr") : nullptr;
        if (!icd) { info = "no vk_icdGetInstanceProcAddr"; return false; }
    }
    if (!Vulkan::Context::init_loader(icd)) {
#endif
        info = "no Vulkan loader";
        return false;
    }
#if !TARGET_OS_IPHONE
    status = N64_RENDERER_VI_FAILED;   // the Mac bench found MoltenVK: anything from here on is a real failure
#endif
    ctx.reset(new Vulkan::Context);
    if (!ctx->init_instance_and_device(nullptr, 0, nullptr, 0)) {
        info = "Vulkan instance/device creation failed";
        ctx.reset();
        return false;
    }
    dev.reset(new Vulkan::Device);
    dev->set_context(*ctx);
    load_pipeline_cache();

    const size_t rdramSize = gfx.RDRAM_SIZE ? *gfx.RDRAM_SIZE : 0x800000;
    size_t align = dev->get_device_features().host_memory_properties.minImportedHostPointerAlignment;
    if (align == 0) align = 0x10000;
    const uintptr_t base = (uintptr_t)gfx.RDRAM;
    const uintptr_t aligned = base & ~(uintptr_t)(align - 1);
    proc.reset(new RDP::CommandProcessor(*dev, (void*)aligned, base - aligned, rdramSize, rdramSize / 2, 0));
    if (!proc->device_is_supported()) {
        info = std::string("this GPU lacks features the N64 renderer needs (") + dev->get_gpu_properties().deviceName + ")";
        return false;
    }
    const auto& f = dev->get_device_features();
    char buf[512];
    snprintf(buf, sizeof(buf), "%s | Vulkan %u.%u | host-memory import %s (align %zu) | subgroup %u | int8/16 %s%s",
             dev->get_gpu_properties().deviceName, VK_VERSION_MAJOR(dev->get_gpu_properties().apiVersion),
             VK_VERSION_MINOR(dev->get_gpu_properties().apiVersion),
             f.supports_external_memory_host ? "yes" : "no (copy path)", align, f.vk11_props.subgroupSize,
             (f.enabled_features.shaderInt16 && f.vk12_features.shaderInt8) ? "yes" : "no", cacheNote);
    info = buf;
    status = N64_RENDERER_RDP;
    return true;
}
}  // namespace

extern "C" void n64rdp_gfx_shutdown(void)
{
    n64rdp_save_pipeline_cache();
    if (proc) proc->idle();
    proc.reset();
    dev.reset();
    ctx.reset();
    status = N64_RENDERER_VI_UNAVAILABLE;
}

extern "C" void n64rdp_process_rdp_list(void)
{
    // Without the renderer (simulator, or Vulkan failed) the command stream is still consumed and SyncFull still
    // raises the DP interrupt, so games keep running (only what the CPU draws shows) instead of waiting forever.
    const double t0 = n64rdp_now_ms();
    double syncMs = 0;
    const uint32_t current = *gfx.DPC_CURRENT_REG & 0x00FFFFF8;
    const uint32_t end = *gfx.DPC_END_REG & 0x00FFFFF8;
    int length = (int)end - (int)current;
    if (length > 0) {
        length = (unsigned)length >> 3;
        if ((cmdPtr + length) & ~(0x0003FFFF >> 3)) goto done;   // overflow: drop (never with sane streams)
        uint32_t offset = current;
        if (*gfx.DPC_STATUS_REG & DP_STATUS_XBUS) {
            do {
                offset &= 0xFF8;
                memcpy(&cmdData[2 * cmdPtr], gfx.DMEM + offset, 8);   // host-order words, as mupen64plus stores them
                offset += 8;
                cmdPtr++;
            } while (--length > 0);
        } else {
            do {
                offset &= 0x7FFFF8;
                memcpy(&cmdData[2 * cmdPtr], gfx.RDRAM + offset, 8);
                offset += 8;
                cmdPtr++;
            } while (--length > 0);
        }
        while (cmdCur < cmdPtr) {
            const uint32_t w0 = cmdData[2 * cmdCur];
            const unsigned op = (w0 >> 24) & 63;
            const int len = (int)kCmdLen[op];
            if (cmdPtr - cmdCur < len) goto partial;   // the rest of this command comes with the next call
            if (op >= 8 && proc) proc->enqueue_command((unsigned)len * 2, &cmdData[2 * cmdCur]);
            if (op >= 0x08 && op <= 0x0F) stats.triangles++;
            stats.rdpWords += (uint64_t)len;
            if (op == 0x29) {   // SyncFull
                stats.syncFulls++;
                if (synchronous && proc) {
                    const double s0 = n64rdp_now_ms();
                    proc->wait_for_timeline(proc->signal_timeline());
                    syncMs += n64rdp_now_ms() - s0;
                }
                *gfx.MI_INTR_REG |= MI_INTR_DP;
                gfx.CheckInterrupts();
            }
            cmdCur += len;
        }
        cmdPtr = 0;
        cmdCur = 0;
    }
done:
partial:
    *gfx.DPC_START_REG = *gfx.DPC_CURRENT_REG = *gfx.DPC_END_REG;
    const double dt = n64rdp_now_ms() - t0;
    nestedRdpMs += dt;
    stats.rdpSyncMs += syncMs;
    stats.rdpEnqueueMs += dt - syncMs;
}

extern "C" void n64rdp_state_loaded(void) { cmdCur = cmdPtr = 0; }

extern "C" bool n64rdp_scan_out(uint32_t* fb, int width, int height)
{
    if (!proc) return false;
    const double t0 = n64rdp_now_ms();
    using RDP::VIRegister;
    proc->set_vi_register(VIRegister::Control, *gfx.VI_STATUS_REG);
    proc->set_vi_register(VIRegister::Origin, *gfx.VI_ORIGIN_REG);
    proc->set_vi_register(VIRegister::Width, *gfx.VI_WIDTH_REG);
    proc->set_vi_register(VIRegister::Intr, *gfx.VI_INTR_REG);
    proc->set_vi_register(VIRegister::VCurrentLine, *gfx.VI_V_CURRENT_LINE_REG);
    proc->set_vi_register(VIRegister::Timing, *gfx.VI_TIMING_REG);
    proc->set_vi_register(VIRegister::VSync, *gfx.VI_V_SYNC_REG);
    proc->set_vi_register(VIRegister::HSync, *gfx.VI_H_SYNC_REG);
    proc->set_vi_register(VIRegister::Leap, *gfx.VI_LEAP_REG);
    proc->set_vi_register(VIRegister::HStart, *gfx.VI_H_START_REG);
    proc->set_vi_register(VIRegister::VStart, *gfx.VI_V_START_REG);
    proc->set_vi_register(VIRegister::VBurst, *gfx.VI_V_BURST_REG);
    proc->set_vi_register(VIRegister::XScale, *gfx.VI_X_SCALE_REG);
    proc->set_vi_register(VIRegister::YScale, *gfx.VI_Y_SCALE_REG);
    RDP::ScanoutOptions opts;
    opts.persist_frame_on_invalid_input = true;
    unsigned w = 0, h = 0;
    proc->scanout_sync(colors, w, h, opts);
    if (w == 0 || h == 0 || colors.size() < (size_t)w * h) {
        for (int i = 0; i < width * height; i++) fb[i] = 0xFF000000u;
    } else {
        // Nearest resample (identity for NTSC at 640 x 480); the VI output is 4:3 at any size.
        static std::vector<unsigned> xmap;
        xmap.resize((size_t)width);
        for (int x = 0; x < width; x++) xmap[(size_t)x] = (unsigned)((size_t)x * w / (unsigned)width);
        for (int y = 0; y < height; y++) {
            const RDP::RGBA* row = &colors[(size_t)((size_t)y * h / (unsigned)height) * w];
            uint32_t* out = &fb[(size_t)y * (size_t)width];
            for (int x = 0; x < width; x++) {
                const RDP::RGBA& p = row[xmap[(size_t)x]];
                out[x] = 0xFF000000u | (uint32_t)p.r << 16 | (uint32_t)p.g << 8 | p.b;
            }
        }
    }
    // Make the frame boundary truly idle: scanout_sync waits only for the VI readback, while RDP writebacks into
    // RDRAM (copy path, or a blank VI that skips the fence) may still be running. Everything is submitted here,
    // in the foreground frame, so save states never see in-flight GPU writes and the app never submits GPU work
    // while it sleeps.
    proc->wait_for_timeline(proc->signal_timeline());
    proc->begin_frame_context();
    if (cacheTrial) {   // the loaded cache survived pipeline creation and a frame: it's good
        std::lock_guard<std::mutex> guard(cacheLock);
        unlink(sentinel_path().c_str());
        cacheTrial = false;
    }
    stats.frames++;
    stats.viMs += n64rdp_now_ms() - t0;
    return true;
}

extern "C" void n64rdp_set_synchronous(bool on) { synchronous = on; }

extern "C" void n64rdp_take_stats(N64RdpStats* out)
{
    collect_gpu_time();
    *out = stats;
    stats = N64RdpStats();
}

extern "C" const char* n64rdp_device_info(void) { return info.c_str(); }
