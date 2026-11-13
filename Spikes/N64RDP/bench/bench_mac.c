// N64 RDP spike: Mac command-line bench. Part of Relics: Games (GPLv3).
// Usage: n64rdp_bench <rom.z64> [--async] [--ppm out.ppm]
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "N64BenchGlue.h"

static const char* g_ppm;
static int g_shots;

static void progress(const char* line, const uint32_t* fb, void* ctx)
{
    (void)ctx;
    fprintf(stderr, "%s\n", line);
    if (g_ppm && fb && ++g_shots % 16 == 0) {   // overwrite: the last one wins
        FILE* f = fopen(g_ppm, "wb");
        if (!f) return;
        fprintf(f, "P6 320 240 255\n");
        for (int i = 0; i < 320 * 240; i++) {
            unsigned char p[3] = { (unsigned char)(fb[i] >> 16), (unsigned char)(fb[i] >> 8), (unsigned char)fb[i] };
            fwrite(p, 1, 3, f);
        }
        fclose(f);
    }
}

int main(int argc, char** argv)
{
    if (argc < 2) { fprintf(stderr, "usage: %s rom.z64 [--async] [--ppm out.ppm]\n", argv[0]); return 2; }
    bool sync = true;
    for (int i = 2; i < argc; i++) {
        if (!strcmp(argv[i], "--async")) sync = false;
        else if (!strcmp(argv[i], "--ppm") && i + 1 < argc) g_ppm = argv[++i];
    }
    char exe[1024];
    snprintf(exe, sizeof(exe), "%s", argv[0]);
    char* root = getenv("N64RDP_ROOT");   // repo root; default: the current directory
    char path[2048];
    snprintf(path, sizeof(path), "%s/ThirdParty-src/moltenvk/macos/libMoltenVK.dylib", root ? root : ".");
    setenv("GRANITE_VULKAN_LIBRARY", path, 0);
    FILE* f = fopen(argv[1], "rb");
    if (!f) { perror(argv[1]); return 1; }
    fseek(f, 0, SEEK_END);
    long n = ftell(f);
    fseek(f, 0, SEEK_SET);
    unsigned char* rom = malloc((size_t)n);
    fread(rom, 1, (size_t)n, f);
    fclose(f);
    char data[2048], work[] = "/private/tmp/n64rdp-bench-XXXXXX";
    snprintf(data, sizeof(data), "%s/Packages/CoreKit/Sources/N64Core/Resources", root ? root : ".");
    if (!mkdtemp(work)) { perror("mkdtemp"); return 1; }
    static char report[16384];
    bool ok = n64bench_run(rom, (size_t)n, work, data, sync, progress, NULL, report, sizeof(report));
    printf("%s", report);
    char cmd[2100];
    snprintf(cmd, sizeof(cmd), "rm -rf '%s'", work);
    system(cmd);
    return ok ? 0 : 1;
}
