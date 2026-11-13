// The N64 renderer's persistent Vulkan pipeline cache file (Relics: Games, GPLv3).
//
// paraLLEl-RDP builds its compute pipelines on first use (SPIR-V -> MSL -> Metal through MoltenVK). The VkPipelineCache
// is saved to Application Support and reloaded at the next start, so those builds happen once per device rather than
// once per session. The file is ours: a fixed header that names the GPU and the driver's pipeline-cache UUID, the
// payload's length and a checksum, then Granite's blob (UUID, hash, the Vulkan cache data with its own header).
// Anything that doesn't match exactly is ignored (and the file deleted): a cache is never trusted blindly.
#ifndef N64_PIPELINE_CACHE_H
#define N64_PIPELINE_CACHE_H
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif

typedef struct N64PipelineCacheID {
    uint32_t vendorID;
    uint32_t deviceID;
    uint32_t driverVersion;
    uint8_t uuid[16];   // VkPhysicalDeviceProperties.pipelineCacheUUID
} N64PipelineCacheID;

enum {
    N64_PIPELINE_CACHE_HEADER_SIZE = 56,
    /// Larger files are refused (a real cache is a few MB at most).
    N64_PIPELINE_CACHE_MAX_PAYLOAD = 16 * 1024 * 1024,
};

/// Fills the 56-byte file header for `payload` (Granite's pipeline-cache blob).
void n64pc_make_header(uint8_t header[N64_PIPELINE_CACHE_HEADER_SIZE], const N64PipelineCacheID* id,
                       const uint8_t* payload, size_t payloadSize);

/// Checks a whole cache file against this device: our header (magic, format, GPU, driver version, UUID, length,
/// checksum) and, inside the payload, Granite's UUID and the Vulkan cache header (length, version, vendor, device,
/// UUID). On success returns true and the payload's offset and size inside `file`.
bool n64pc_validate(const uint8_t* file, size_t fileSize, const N64PipelineCacheID* id, size_t* payloadOffset,
                    size_t* payloadSize);

#ifdef __cplusplus
}
#endif
#endif
