// N64 RDP spike: benchmark runner. Part of Relics: Games (GPLv3). See n64bench.h.
#include "n64bench.h"

#include <stdio.h>
#include <string.h>

#include "Mupen64Glue.h"
#include "n64_rdp_spike.h"

enum { LEVELS = 3, WARMUP = 40, MAX_FRAMES = 1200 };

typedef struct {
    int frames;
    double wallMs;
    N64SpikeStats s;
    uint32_t triangles, kernels, perKernel;
    double worstMs;   // slowest frame of the level, warm-up included (pipeline compiles show here)
} Bucket;

static void add(Bucket* b, const N64SpikeStats* s, double wall)
{
    b->frames++;
    b->wallMs += wall;
    b->s.rspMs += s->rspMs;
    b->s.hleMs += s->hleMs;
    b->s.rdpEnqueueMs += s->rdpEnqueueMs;
    b->s.rdpSyncMs += s->rdpSyncMs;
    b->s.viMs += s->viMs;
    b->s.gpuRenderMs += s->gpuRenderMs;
    b->s.triangles += s->triangles;
    b->s.rdpWords += s->rdpWords;
}

bool n64bench_run(const uint8_t* rom, size_t romSize, const char* workDir, const char* dataDir, bool synchronous,
                  N64BenchProgress progress, void* ctx, char* report, size_t cap)
{
    size_t o = 0;
#define OUT(...) do { if (o < cap) o += (size_t)snprintf(report + o, cap - o, __VA_ARGS__); } while (0)
    report[0] = 0;
    n64spike_set_synchronous(synchronous);
    N64Handle* h = n64_create(rom, romSize, NULL, 0, workDir, dataDir);
    if (h == NULL) { OUT("n64_create failed\n"); return false; }
    OUT("Device: %s\n", n64spike_device_info());
    if (strstr(n64spike_device_info(), " | Vulkan ") == NULL) {   // set only when paraLLEl-RDP is up
        n64_destroy(h);
        OUT("RDP did not start\n");
        return false;
    }
    OUT("Mode: %s RDP (%s)\n", synchronous ? "synchronous" : "asynchronous",
        synchronous ? "CPU waits for the GPU at every SyncFull" : "only the VI scan-out waits");
    Bucket b[LEVELS + 1];
    memset(b, 0, sizeof(b));
    N64SpikeStats junk;
    n64spike_take_stats(&junk);
    int lastLevel = -1, sinceSwitch = 0, seen = 0;
    for (int f = 0; f < MAX_FRAMES; f++) {
        const double t0 = n64spike_now_ms();
        n64_run_frame(h);
        const double wall = n64spike_now_ms() - t0;
        N64SpikeStats s;
        n64spike_take_stats(&s);
        const int level = (int)n64_peek_rdram(h, 0x304);
        if (level != lastLevel) {
            if (level == 1 && lastLevel == LEVELS) break;   // all three levels measured
            lastLevel = level;
            sinceSwitch = 0;
            if (level >= 1 && level <= LEVELS) seen |= 1 << level;
        }
        if (level >= 1 && level <= LEVELS && wall > b[level].worstMs) b[level].worstMs = wall;
        if (level >= 1 && level <= LEVELS && ++sinceSwitch > WARMUP) {
            add(&b[level], &s, wall);
            b[level].triangles = n64_peek_rdram(h, 0x308);
            b[level].kernels = n64_peek_rdram(h, 0x30C);
            b[level].perKernel = n64_peek_rdram(h, 0x310);
        }
        if (progress && f % 15 == 0) {
            char line[200];
            snprintf(line, sizeof(line), "frame %d, level %d: %.2f ms (%.0f fps)  rsp %.2f  rdp %.2f  gpu %.2f", f,
                     level, wall, wall > 0 ? 1000.0 / wall : 0, s.rspMs, s.rdpEnqueueMs + s.rdpSyncMs, s.gpuRenderMs);
            progress(line, n64_framebuffer(h), ctx);
        }
    }
    n64_destroy(h);

    OUT("\nPer emulated frame (ms), averages after %d warm-up frames per level. Full speed = 16.67 ms (60 VI/s).\n",
        WARMUP);
    OUT("%-5s %6s %6s %7s %7s | %6s %6s %6s %7s %7s %6s | %7s %7s\n", "level", "tris", "frames", "frame", "fps",
        "cpu", "rsp", "rspHLE", "rdpCPU", "rdpWait", "vi", "gpuRDP", "worst");
    for (int l = 1; l <= LEVELS; l++) {
        Bucket* x = &b[l];
        if (x->frames == 0) { OUT("%-5d (not reached)\n", l); continue; }
        const double n = x->frames;
        const double frame = x->wallMs / n;
        const double rsp = x->s.rspMs / n, hle = x->s.hleMs / n, rdpc = x->s.rdpEnqueueMs / n;
        const double rdpw = x->s.rdpSyncMs / n, vi = x->s.viMs / n;
        const double cpu = frame - rsp - hle - rdpc - rdpw - vi;
        OUT("%-5d %6u %6d %7.2f %7.1f | %6.2f %6.2f %6.2f %7.2f %7.2f %6.2f | %7.2f %7.2f\n", l, x->triangles,
            x->frames, frame, 1000.0 / frame, cpu, rsp, hle, rdpc, rdpw, vi, x->s.gpuRenderMs / n, x->worstMs);
    }
    OUT("\ncpu = mupen64plus cached interpreter (everything not listed); rsp = cxd4 interpreter on graphics tasks\n"
        "(our microcode at level 3: %u kernel iterations x %u RSP instructions + command streaming);\n"
        "rdpCPU = queueing RDP commands; rdpWait = waiting for the GPU at SyncFull; vi = VI pass + readback;\n"
        "gpuRDP = GPU time of the RDP render passes (Vulkan timestamps, overlaps the other columns);\n"
        "worst = slowest single frame of the level including warm-up (first-use shader pipeline builds).\n",
        b[LEVELS].kernels, b[LEVELS].perKernel);
    return seen != 0;
#undef OUT
}
