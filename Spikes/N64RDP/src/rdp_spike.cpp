// N64 RDP spike: paraLLEl-RDP (MIT) behind our mupen64plus glue. Part of Relics: Games (GPLv3).
// Throwaway feasibility code (docs/n64-rdp-spike.md). The command-stream handling follows the protocol every
// paraLLEl-RDP integration uses (DPC_CURRENT..DPC_END from RDRAM or, with the XBUS bit, from DMEM; commands may
// straddle two ProcessRDPList calls; SyncFull raises the DP interrupt), written here from the RDP documentation.
#include "rdp_device.hpp"
#include "context.hpp"
#include "device.hpp"

#include <TargetConditionals.h>
#include <dlfcn.h>
#include <mach/mach_time.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <memory>
#include <string>
#include <vector>

extern "C" {
#include "api/m64p_plugin.h"
#include "n64_rdp_spike.h"
}

#if TARGET_OS_IPHONE
// MoltenVK is linked statically on iOS; its ICD entry point avoids volk's vkGetInstanceProcAddr global.
extern "C" PFN_vkVoidFunction vk_icdGetInstanceProcAddr(VkInstance instance, const char* name);
#endif

namespace {

GFX_INFO gfx;
std::unique_ptr<Vulkan::Context> ctx;
std::unique_ptr<Vulkan::Device> dev;
std::unique_ptr<RDP::CommandProcessor> proc;
bool synchronous = true;
std::string info;

uint32_t cmdData[0x00040000 >> 2];
int cmdCur = 0, cmdPtr = 0;

N64SpikeStats stats;
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

}  // namespace

extern "C" double n64spike_now_ms(void)
{
    static mach_timebase_info_data_t tb;
    if (tb.denom == 0) mach_timebase_info(&tb);
    return (double)mach_absolute_time() * tb.numer / tb.denom / 1e6;
}

extern "C" double n64spike_rdp_nested_ms(void) { return nestedRdpMs; }

extern "C" void n64spike_add_rsp_ms(double ms, bool hle)
{
    if (hle) stats.hleMs += ms;
    else stats.rspMs += ms;
}

extern "C" bool n64spike_gfx_init(const void* gfxInfo)
{
    gfx = *(const GFX_INFO*)gfxInfo;
    setenv("PARALLEL_RDP_BENCH", "1", 0);   // GPU timestamps per render pass
#if TARGET_OS_IPHONE
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
    ctx.reset(new Vulkan::Context);
    if (!ctx->init_instance_and_device(nullptr, 0, nullptr, 0)) {
        info = "Vulkan instance/device creation failed";
        ctx.reset();
        return false;
    }
    dev.reset(new Vulkan::Device);
    dev->set_context(*ctx);

    const size_t rdramSize = gfx.RDRAM_SIZE ? *gfx.RDRAM_SIZE : 0x800000;
    size_t align = dev->get_device_features().host_memory_properties.minImportedHostPointerAlignment;
    if (align == 0) align = 0x10000;
    const uintptr_t base = (uintptr_t)gfx.RDRAM;
    const uintptr_t aligned = base & ~(uintptr_t)(align - 1);
    proc.reset(new RDP::CommandProcessor(*dev, (void*)aligned, base - aligned, rdramSize, rdramSize / 2, 0));
    if (!proc->device_is_supported()) {
        info = "paraLLEl-RDP: device not supported";
        proc.reset(); dev.reset(); ctx.reset();
        return false;
    }
    const auto& f = dev->get_device_features();
    char buf[512];
    snprintf(buf, sizeof(buf), "%s | Vulkan %u.%u | host-memory import %s (align %zu) | subgroup %u | int8/16 %s",
             dev->get_gpu_properties().deviceName, VK_VERSION_MAJOR(dev->get_gpu_properties().apiVersion),
             VK_VERSION_MINOR(dev->get_gpu_properties().apiVersion),
             f.supports_external_memory_host ? "yes" : "no (copy path)", align, f.vk11_props.subgroupSize,
             (f.enabled_features.shaderInt16 && f.vk12_features.shaderInt8) ? "yes" : "no");
    info = buf;
    cmdCur = cmdPtr = 0;
    return true;
}

extern "C" void n64spike_gfx_shutdown(void)
{
    if (proc) proc->idle();
    proc.reset();
    dev.reset();
    ctx.reset();
}

extern "C" void n64spike_process_rdp_list(void)
{
    if (!proc) return;
    const double t0 = n64spike_now_ms();
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
            if (op >= 8) proc->enqueue_command((unsigned)len * 2, &cmdData[2 * cmdCur]);
            if (op >= 0x08 && op <= 0x0F) stats.triangles++;
            stats.rdpWords += (uint64_t)len;
            if (op == 0x29) {   // SyncFull
                stats.syncFulls++;
                if (synchronous) {
                    const double s0 = n64spike_now_ms();
                    proc->wait_for_timeline(proc->signal_timeline());
                    syncMs += n64spike_now_ms() - s0;
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
    const double dt = n64spike_now_ms() - t0;
    nestedRdpMs += dt;
    stats.rdpSyncMs += syncMs;
    stats.rdpEnqueueMs += dt - syncMs;
}

extern "C" bool n64spike_scan_out(uint32_t* fb, int width, int height)
{
    if (!proc) return false;
    const double t0 = n64spike_now_ms();
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
    if (w == 0 || h == 0) {
        for (int i = 0; i < width * height; i++) fb[i] = 0xFF000000u;
    } else {
        for (int y = 0; y < height; y++) {
            const RDP::RGBA* row = &colors[(size_t)(y * (int)h / height) * w];
            for (int x = 0; x < width; x++) {
                const RDP::RGBA& p = row[x * (int)w / width];
                fb[y * width + x] = 0xFF000000u | (uint32_t)p.r << 16 | (uint32_t)p.g << 8 | p.b;
            }
        }
    }
    proc->begin_frame_context();
    stats.frames++;
    stats.viMs += n64spike_now_ms() - t0;
    return true;
}

extern "C" void n64spike_set_synchronous(bool on) { synchronous = on; }

extern "C" void n64spike_take_stats(N64SpikeStats* out)
{
    collect_gpu_time();
    *out = stats;
    stats = N64SpikeStats();
}

extern "C" const char* n64spike_device_info(void) { return info.c_str(); }
