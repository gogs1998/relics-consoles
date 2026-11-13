// The N64 renderer's pipeline cache file format (Relics: Games, GPLv3). See N64PipelineCache.h.
//
// Layout (little-endian):
//   0 "RLPC"  4 format (1)  8 vendorID  12 deviceID  16 driverVersion  20 uuid[16]  36 reserved (0)
//   40 payload size (u64)  48 FNV-1a 64 of the payload (u64)  56 payload
// Payload = Granite's blob: pipelineCacheUUID[16], its own 64-bit hash, then the Vulkan pipeline cache data, which
// starts with VkPipelineCacheHeaderVersionOne (length >= 32, version 1, vendorID, deviceID, pipelineCacheUUID).
#include "N64PipelineCache.h"

#include <string.h>

enum {
    FORMAT = 1,
    GRANITE_PREFIX = 16 + 8,     // UUID + hash
    VK_HEADER_MIN = 32,          // sizeof(VkPipelineCacheHeaderVersionOne)
    VK_HEADER_VERSION_ONE = 1,
};

static void put32(uint8_t* p, uint32_t v) { memcpy(p, &v, 4); }
static void put64(uint8_t* p, uint64_t v) { memcpy(p, &v, 8); }
static uint32_t get32(const uint8_t* p) { uint32_t v; memcpy(&v, p, 4); return v; }
static uint64_t get64(const uint8_t* p) { uint64_t v; memcpy(&v, p, 8); return v; }

static uint64_t fnv1a64(const uint8_t* p, size_t n)
{
    uint64_t h = 0xcbf29ce484222325ull;
    for (size_t i = 0; i < n; i++) {
        h ^= p[i];
        h *= 0x100000001b3ull;
    }
    return h;
}

void n64pc_make_header(uint8_t header[N64_PIPELINE_CACHE_HEADER_SIZE], const N64PipelineCacheID* id,
                       const uint8_t* payload, size_t payloadSize)
{
    memset(header, 0, N64_PIPELINE_CACHE_HEADER_SIZE);
    memcpy(header, "RLPC", 4);
    put32(header + 4, FORMAT);
    put32(header + 8, id->vendorID);
    put32(header + 12, id->deviceID);
    put32(header + 16, id->driverVersion);
    memcpy(header + 20, id->uuid, 16);
    put64(header + 40, (uint64_t)payloadSize);
    put64(header + 48, payload ? fnv1a64(payload, payloadSize) : 0);
}

bool n64pc_validate(const uint8_t* file, size_t fileSize, const N64PipelineCacheID* id, size_t* payloadOffset,
                    size_t* payloadSize)
{
    if (file == NULL || id == NULL || fileSize < N64_PIPELINE_CACHE_HEADER_SIZE) return false;
    if (memcmp(file, "RLPC", 4) != 0 || get32(file + 4) != FORMAT) return false;
    if (get32(file + 8) != id->vendorID || get32(file + 12) != id->deviceID
        || get32(file + 16) != id->driverVersion || memcmp(file + 20, id->uuid, 16) != 0 || get32(file + 36) != 0)
        return false;
    const uint64_t size = get64(file + 40);
    if (size > N64_PIPELINE_CACHE_MAX_PAYLOAD || size != (uint64_t)(fileSize - N64_PIPELINE_CACHE_HEADER_SIZE))
        return false;
    const uint8_t* payload = file + N64_PIPELINE_CACHE_HEADER_SIZE;
    if (size < GRANITE_PREFIX + VK_HEADER_MIN) return false;
    if (fnv1a64(payload, (size_t)size) != get64(file + 48)) return false;
    // Granite's prefix, then the Vulkan header inside the cache data.
    if (memcmp(payload, id->uuid, 16) != 0) return false;
    const uint8_t* vk = payload + GRANITE_PREFIX;
    const uint64_t vkSize = size - GRANITE_PREFIX;
    const uint32_t vkHeaderLength = get32(vk);
    if (vkHeaderLength < VK_HEADER_MIN || vkHeaderLength > vkSize) return false;
    if (get32(vk + 4) != VK_HEADER_VERSION_ONE) return false;
    if (get32(vk + 8) != id->vendorID || get32(vk + 12) != id->deviceID) return false;
    if (memcmp(vk + 16, id->uuid, 16) != 0) return false;
    if (payloadOffset) *payloadOffset = N64_PIPELINE_CACHE_HEADER_SIZE;
    if (payloadSize) *payloadSize = (size_t)size;
    return true;
}
