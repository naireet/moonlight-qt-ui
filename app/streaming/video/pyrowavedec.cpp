#include "pyrowavedec.h"

#include "streaming/session.h"
#include "streaming/streamutils.h"

#include <SDL_vulkan.h>

#include <QByteArray>
#include <QtGlobal>

#include <algorithm>
#include <cstring>

#ifdef HAVE_DRM_MASTER_HOOKS
extern "C" {
void lockDrmMaster();
void unlockDrmMaster();
}
#endif

namespace {

// Same guard as PlVkRenderer: don't let Qt take DRM master from us while Vulkan
// may need it (KMSDRM environments only; a no-op otherwise).
class DrmMasterLocker {
public:
    DrmMasterLocker() {
#ifdef HAVE_DRM_MASTER_HOOKS
        lockDrmMaster();
#endif
    }
    ~DrmMasterLocker() {
#ifdef HAVE_DRM_MASTER_HOOKS
        unlockDrmMaster();
#endif
    }
    DrmMasterLocker(const DrmMasterLocker&) = delete;
    DrmMasterLocker& operator=(const DrmMasterLocker&) = delete;
};

void plLogCallback(void*, enum pl_log_level level, const char* msg)
{
    switch (level) {
    case PL_LOG_FATAL:
        SDL_LogCritical(SDL_LOG_CATEGORY_APPLICATION, "libplacebo: %s", msg);
        break;
    case PL_LOG_ERR:
        SDL_LogError(SDL_LOG_CATEGORY_APPLICATION, "libplacebo: %s", msg);
        break;
    case PL_LOG_WARN:
        if (strncmp(msg, "Masking `", 9) == 0) {
            return;
        }
        SDL_LogWarn(SDL_LOG_CATEGORY_APPLICATION, "libplacebo: %s", msg);
        break;
    case PL_LOG_INFO:
        SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION, "libplacebo: %s", msg);
        break;
    default:
        SDL_LogDebug(SDL_LOG_CATEGORY_APPLICATION, "libplacebo: %s", msg);
        break;
    }
}

template<typename T>
const T* findFeatureStruct(const VkPhysicalDeviceFeatures2* features, VkStructureType sType)
{
    for (auto s = static_cast<const VkBaseInStructure*>(features->pNext); s != nullptr; s = s->pNext) {
        if (s->sType == sType) {
            return reinterpret_cast<const T*>(s);
        }
    }
    return nullptr;
}

uint32_t readLe32(const uint8_t* p)
{
    return (uint32_t)p[0] | ((uint32_t)p[1] << 8) | ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24);
}

// PyroWave sequence header colorimetry bits (BitstreamSequenceHeader in
// pyrowave_common.hpp, second 32-bit word, bitfields allocated LSB first):
//   24-25 code, 26 chroma_resolution (1 = 4:4:4), 27 color_primaries (1 = BT.2020),
//   28 transfer_function (1 = PQ), 29 ycbcr_transform (1 = BT.2020),
//   30 ycbcr_range (1 = limited), 31 chroma_siting (1 = left)
constexpr uint32_t k_SeqChroma444 = 1u << 26;
constexpr uint32_t k_SeqPrimaries2020 = 1u << 27;
constexpr uint32_t k_SeqTransferPq = 1u << 28;
constexpr uint32_t k_SeqMatrix2020 = 1u << 29;
constexpr uint32_t k_SeqRangeLimited = 1u << 30;
constexpr uint32_t k_SeqSitingLeft = 1u << 31;
constexpr uint32_t k_SeqColorimetryMask = k_SeqPrimaries2020 | k_SeqTransferPq | k_SeqMatrix2020 |
                                          k_SeqRangeLimited | k_SeqSitingLeft;

// First packets of more than this are treated as corrupt rather than parsed
constexpr uint32_t k_MaxPacketSize = 16 * 1024 * 1024;

const char* primariesName(enum pl_color_primaries p)
{
    switch (p) {
    case PL_COLOR_PRIM_BT_709: return "BT.709";
    case PL_COLOR_PRIM_BT_2020: return "BT.2020";
    case PL_COLOR_PRIM_DISPLAY_P3: return "Display P3";
    default: return "other";
    }
}

const char* transferName(enum pl_color_transfer t)
{
    switch (t) {
    case PL_COLOR_TRC_BT_1886: return "BT.1886";
    case PL_COLOR_TRC_SRGB: return "sRGB";
    case PL_COLOR_TRC_PQ: return "PQ";
    case PL_COLOR_TRC_HLG: return "HLG";
    case PL_COLOR_TRC_LINEAR: return "linear";
    default: return "other";
    }
}

}

PyroWaveVideoDecoder::PyroWaveVideoDecoder(bool testOnly)
    : m_TestOnly(testOnly),
      m_BwTracker(10, 250)
{
    bool ok;
    pl_log_params logParams = pl_log_default_params;
    logParams.log_cb = plLogCallback;
    logParams.log_level = (pl_log_level)qEnvironmentVariableIntValue("PLVK_LOG_LEVEL", &ok);
    if (!ok) {
#ifdef QT_DEBUG
        logParams.log_level = PL_LOG_DEBUG;
#else
        logParams.log_level = PL_LOG_WARN;
#endif
    }
    m_Log = pl_log_create(PL_API_VER, &logParams);
}

PyroWaveVideoDecoder::~PyroWaveVideoDecoder()
{
    if (!m_TestOnly && Session::get() != nullptr) {
        Session::get()->getOverlayManager().setOverlayRenderer(nullptr);
    }

    if (m_RenderThread.joinable()) {
        {
            std::lock_guard<std::mutex> lock(m_SlotLock);
            m_Stopping = true;
        }
        m_FrameAvailable.notify_all();
        m_RenderThread.join();
    }

    if (m_GlobalVideoStats.renderedFrames != 0) {
        char stats[1024];
        stringifyVideoStats(m_GlobalVideoStats, m_GlobalPyroStats, stats, sizeof(stats));
        SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION, "\nGlobal video stats\n------------------\n%s", stats);
    }

    // PyroWave objects wrap the libplacebo device, so they go first. Destroying the
    // decoder waits for its GPU work to finish.
    if (m_PyroDecoder != nullptr) {
        m_Lib->pyrowave_decoder_destroy(m_PyroDecoder);
    }
    if (m_PyroDevice != nullptr) {
        m_Lib->pyrowave_device_destroy(m_PyroDevice);
    }

    if (m_Vulkan != nullptr) {
        pl_gpu_finish(m_Vulkan->gpu);

        for (auto& slot : m_Slots) {
            for (auto& plane : slot.planes) {
                pl_tex_destroy(m_Vulkan->gpu, &plane);
            }
        }
        for (auto& o : m_Overlays) {
            pl_tex_destroy(m_Vulkan->gpu, &o.overlay.tex);
            pl_tex_destroy(m_Vulkan->gpu, &o.stagingOverlay.tex);
        }

        // Only safe after pl_gpu_finish(), since the textures may still reference them
        pl_vulkan_sem_destroy(m_Vulkan->gpu, &m_DecodeTimeline);
        pl_vulkan_sem_destroy(m_Vulkan->gpu, &m_RenderTimeline);
    }

    {
        DrmMasterLocker locker;

        pl_renderer_destroy(&m_Renderer);
        pl_swapchain_destroy(&m_Swapchain);
        pl_vulkan_destroy(&m_Vulkan);

        // Created by SDL, so there's no libplacebo API to destroy it
        if (fn_vkDestroySurfaceKHR != nullptr && m_VkSurface != VK_NULL_HANDLE) {
            fn_vkDestroySurfaceKHR(m_PlVkInstance->instance, m_VkSurface, nullptr);
        }

        pl_vk_inst_destroy(&m_PlVkInstance);
    }

    // m_Log must always be the last object destroyed
    pl_log_destroy(&m_Log);
}

bool PyroWaveVideoDecoder::initialize(PDECODER_PARAMETERS params)
{
    if (!(params->videoFormat & VIDEO_FORMAT_MASK_PYROWAVE)) {
        return false;
    }

    m_Window = params->window;
    m_VideoFormat = params->videoFormat;
    m_Width = params->width;
    m_Height = params->height;
    m_FrameRate = params->frameRate;
    m_EnableVsync = params->enableVsync;
    m_Yuv444 = !!(params->videoFormat & VIDEO_FORMAT_MASK_YUV444);
    m_TenBit = !!(params->videoFormat & VIDEO_FORMAT_MASK_10BIT);

    if (!m_Yuv444 && ((m_Width & 1) || (m_Height & 1))) {
        SDL_LogError(SDL_LOG_CATEGORY_APPLICATION,
                     "PyroWave: 4:2:0 requires an even resolution (%dx%d)",
                     m_Width, m_Height);
        return false;
    }

    m_Lib = PyroWaveLibrary::get();
    if (m_Lib == nullptr) {
        return false;
    }

    // Acceptance policy for frames that arrive incomplete (Wi-Fi loss). A frame is
    // decoded if its two coarsest wavelet bands are intact and more than this fraction
    // of its blocks arrived; otherwise the previous picture stays up for a frame.
    // Upstream's default is 0.9, which throws away most salvaged frames: a prefix
    // truncated at the first lost packet rarely carries 90% of the blocks. Missing
    // blocks decode as zero (softer detail), so 0.5 trades a little blur for fewer
    // repeated frames. Tunable for A/B tests without rebuilding.
    {
        QByteArray ratioEnv = qgetenv("PYROWAVE_MIN_BLOCK_RATIO");
        bool ok = false;
        float ratio = ratioEnv.isEmpty() ? 0.5f : ratioEnv.toFloat(&ok);
        if (!ratioEnv.isEmpty() && (!ok || ratio < 0.0f || ratio > 1.0f)) {
            SDL_LogWarn(SDL_LOG_CATEGORY_APPLICATION,
                        "PyroWave: ignoring invalid PYROWAVE_MIN_BLOCK_RATIO=%s (expected 0.0 to 1.0)",
                        ratioEnv.constData());
            ratio = 0.5f;
        }
        m_MinBlockRatio = ratio;
    }
    if (!m_TestOnly) {
        SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION,
                    "PyroWave: incomplete frames are shown with %d intact coarse bands and > %.2f of blocks",
                    m_PristineBands, m_MinBlockRatio);
    }

    if (!createVulkanDevice(params) || !createPyroWaveDecoder() || !createSlots()) {
        return false;
    }

    if (m_TestOnly) {
        return true;
    }

    if (!createSwapchain()) {
        return false;
    }

    m_Renderer = pl_renderer_create(m_Log, m_Vulkan->gpu);
    if (m_Renderer == nullptr) {
        SDL_LogError(SDL_LOG_CATEGORY_APPLICATION, "PyroWave: pl_renderer_create() failed");
        return false;
    }

    m_RenderThread = std::thread(&PyroWaveVideoDecoder::renderThreadProc, this);

    if (Session::get() != nullptr) {
        Session::get()->getOverlayManager().setOverlayRenderer(this);
    }

    SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION,
                "PyroWave decoder ready: %dx%d %s %s, %d slots",
                m_Width, m_Height, m_Yuv444 ? "4:4:4" : "4:2:0", m_TenBit ? "10-bit" : "8-bit",
                k_SlotCount);
    return true;
}

bool PyroWaveVideoDecoder::createVulkanDevice(PDECODER_PARAMETERS params)
{
    unsigned int instanceExtensionCount = 0;
    if (!SDL_Vulkan_GetInstanceExtensions(params->window, &instanceExtensionCount, nullptr)) {
        SDL_LogError(SDL_LOG_CATEGORY_APPLICATION,
                     "PyroWave: SDL_Vulkan_GetInstanceExtensions() failed: %s", SDL_GetError());
        return false;
    }
    std::vector<const char*> instanceExtensions(instanceExtensionCount);
    if (!SDL_Vulkan_GetInstanceExtensions(params->window, &instanceExtensionCount, instanceExtensions.data())) {
        SDL_LogError(SDL_LOG_CATEGORY_APPLICATION,
                     "PyroWave: SDL_Vulkan_GetInstanceExtensions() failed: %s", SDL_GetError());
        return false;
    }

    pl_vk_inst_params instParams = pl_vk_inst_default_params;
    instParams.debug_extra = !!qEnvironmentVariableIntValue("PLVK_DEBUG_EXTRA");
    instParams.debug = instParams.debug_extra || !!qEnvironmentVariableIntValue("PLVK_DEBUG");
    instParams.get_proc_addr = (PFN_vkGetInstanceProcAddr)SDL_Vulkan_GetVkGetInstanceProcAddr();
    instParams.extensions = instanceExtensions.data();
    instParams.num_extensions = (int)instanceExtensions.size();
    m_PlVkInstance = pl_vk_inst_create(m_Log, &instParams);
    if (m_PlVkInstance == nullptr) {
        SDL_LogError(SDL_LOG_CATEGORY_APPLICATION, "PyroWave: pl_vk_inst_create() failed");
        return false;
    }

    // Granite (PyroWave's Vulkan layer) requires a Vulkan 1.3 instance
    if (m_PlVkInstance->api_version < VK_API_VERSION_1_3) {
        SDL_LogError(SDL_LOG_CATEGORY_APPLICATION,
                     "PyroWave: Vulkan 1.3 instance required (have %u.%u)",
                     VK_API_VERSION_MAJOR(m_PlVkInstance->api_version),
                     VK_API_VERSION_MINOR(m_PlVkInstance->api_version));
        return false;
    }

    fn_vkDestroySurfaceKHR = (PFN_vkDestroySurfaceKHR)
        m_PlVkInstance->get_proc_addr(m_PlVkInstance->instance, "vkDestroySurfaceKHR");
    auto fn_vkGetPhysicalDeviceSurfacePresentModesKHR = (PFN_vkGetPhysicalDeviceSurfacePresentModesKHR)
        m_PlVkInstance->get_proc_addr(m_PlVkInstance->instance, "vkGetPhysicalDeviceSurfacePresentModesKHR");
    auto fn_vkGetDeviceProcAddr = (PFN_vkGetDeviceProcAddr)
        m_PlVkInstance->get_proc_addr(m_PlVkInstance->instance, "vkGetDeviceProcAddr");
    if (fn_vkDestroySurfaceKHR == nullptr || fn_vkGetPhysicalDeviceSurfacePresentModesKHR == nullptr ||
            fn_vkGetDeviceProcAddr == nullptr) {
        SDL_LogError(SDL_LOG_CATEGORY_APPLICATION, "PyroWave: missing Vulkan entry points");
        return false;
    }

    {
        DrmMasterLocker locker;
        if (!SDL_Vulkan_CreateSurface(params->window, m_PlVkInstance->instance, &m_VkSurface)) {
            SDL_LogError(SDL_LOG_CATEGORY_APPLICATION,
                         "PyroWave: SDL_Vulkan_CreateSurface() failed: %s", SDL_GetError());
            return false;
        }
    }

    // Features PyroWave's decoder shaders use, requested on top of libplacebo's own
    // required/recommended set. libplacebo only enables the ones the device supports,
    // so the result is checked below.
    VkPhysicalDeviceVulkan13Features features13 = {};
    features13.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_3_FEATURES;
    features13.subgroupSizeControl = VK_TRUE;
    features13.computeFullSubgroups = VK_TRUE;
    VkPhysicalDeviceVulkan12Features features12 = {};
    features12.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_2_FEATURES;
    features12.pNext = &features13;
    features12.timelineSemaphore = VK_TRUE;
    features12.shaderFloat16 = VK_TRUE;
    features12.storageBuffer8BitAccess = VK_TRUE;
    VkPhysicalDeviceVulkan11Features features11 = {};
    features11.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_1_FEATURES;
    features11.pNext = &features12;
    features11.storageBuffer16BitAccess = VK_TRUE;
    VkPhysicalDeviceFeatures2 features = {};
    features.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FEATURES_2;
    features.pNext = &features11;
    features.features.shaderInt16 = VK_TRUE;
    features.features.shaderStorageImageExtendedFormats = VK_TRUE;
    // PyroWave writes the planes through format-less storage images
    features.features.shaderStorageImageWriteWithoutFormat = VK_TRUE;

    // The device is created by libplacebo, so it goes through exactly the same
    // (patched) queue setup as the HEVC Vulkan renderer. That is what keeps this
    // path clear of the gamescope WSI layer crash (ValveSoftware/gamescope#2261).
    pl_vulkan_params vkParams = pl_vulkan_default_params;
    vkParams.instance = m_PlVkInstance->instance;
    vkParams.get_proc_addr = m_PlVkInstance->get_proc_addr;
    vkParams.surface = m_VkSurface;
    vkParams.features = &features;
    // PyroWave submits on the graphics queue it is given; keep libplacebo there too
    vkParams.async_compute = false;
    {
        DrmMasterLocker locker;
        m_Vulkan = pl_vulkan_create(m_Log, &vkParams);
    }
    if (m_Vulkan == nullptr) {
        SDL_LogError(SDL_LOG_CATEGORY_APPLICATION, "PyroWave: pl_vulkan_create() failed");
        return false;
    }

    VkPhysicalDeviceProperties props;
    auto fn_vkGetPhysicalDeviceProperties = (PFN_vkGetPhysicalDeviceProperties)
        m_PlVkInstance->get_proc_addr(m_PlVkInstance->instance, "vkGetPhysicalDeviceProperties");
    fn_vkGetPhysicalDeviceProperties(m_Vulkan->phys_device, &props);
    SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION,
                "PyroWave: Vulkan device %s (API %u.%u)",
                props.deviceName, VK_API_VERSION_MAJOR(m_Vulkan->api_version), VK_API_VERSION_MINOR(m_Vulkan->api_version));

    auto enabled13 = findFeatureStruct<VkPhysicalDeviceVulkan13Features>(
        m_Vulkan->features, VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_3_FEATURES);
    auto enabled12 = findFeatureStruct<VkPhysicalDeviceVulkan12Features>(
        m_Vulkan->features, VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_2_FEATURES);
    if (m_Vulkan->api_version < VK_API_VERSION_1_3 || enabled13 == nullptr || !enabled13->subgroupSizeControl ||
            enabled12 == nullptr || !enabled12->timelineSemaphore ||
            !m_Vulkan->features->features.shaderStorageImageWriteWithoutFormat) {
        SDL_LogError(SDL_LOG_CATEGORY_APPLICATION,
                     "PyroWave: device lacks Vulkan 1.3 subgroup size control, timeline semaphores "
                     "or format-less storage image writes");
        return false;
    }

    // Present mode selection, same policy as PlVkRenderer
    uint32_t presentModeCount = 0;
    fn_vkGetPhysicalDeviceSurfacePresentModesKHR(m_Vulkan->phys_device, m_VkSurface, &presentModeCount, nullptr);
    std::vector<VkPresentModeKHR> presentModes(presentModeCount);
    fn_vkGetPhysicalDeviceSurfacePresentModesKHR(m_Vulkan->phys_device, m_VkSurface, &presentModeCount, presentModes.data());
    auto supported = [&](VkPresentModeKHR mode) {
        return std::find(presentModes.begin(), presentModes.end(), mode) != presentModes.end();
    };
    if (m_EnableVsync) {
        m_PresentMode = VK_PRESENT_MODE_FIFO_KHR;
    }
    else if (supported(VK_PRESENT_MODE_IMMEDIATE_KHR)) {
        m_PresentMode = VK_PRESENT_MODE_IMMEDIATE_KHR;
    }
    else if (supported(VK_PRESENT_MODE_FIFO_RELAXED_KHR)) {
        m_PresentMode = VK_PRESENT_MODE_FIFO_RELAXED_KHR;
    }
    else if (supported(VK_PRESENT_MODE_MAILBOX_KHR)) {
        m_PresentMode = VK_PRESENT_MODE_MAILBOX_KHR;
    }
    else {
        m_PresentMode = VK_PRESENT_MODE_FIFO_KHR;
    }

    // Hand PyroWave the same instance and device. The create infos describe what
    // libplacebo actually enabled; the queue list is restricted to graphics queue 0
    // so Granite never looks up any other queue.
    m_PyroAppInfo = {};
    m_PyroAppInfo.sType = VK_STRUCTURE_TYPE_APPLICATION_INFO;
    m_PyroAppInfo.apiVersion = m_PlVkInstance->api_version;
    m_PyroInstanceInfo = {};
    m_PyroInstanceInfo.sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO;
    m_PyroInstanceInfo.pApplicationInfo = &m_PyroAppInfo;
    m_PyroInstanceInfo.enabledExtensionCount = (uint32_t)m_PlVkInstance->num_extensions;
    m_PyroInstanceInfo.ppEnabledExtensionNames = m_PlVkInstance->extensions;

    m_PyroQueueCreateInfo = {};
    m_PyroQueueCreateInfo.sType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO;
    m_PyroQueueCreateInfo.queueFamilyIndex = (uint32_t)m_Vulkan->queue_graphics.index;
    m_PyroQueueCreateInfo.queueCount = 1;
    m_PyroQueueCreateInfo.pQueuePriorities = &m_PyroQueuePriority;

    m_PyroDeviceInfo = {};
    m_PyroDeviceInfo.sType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO;
    m_PyroDeviceInfo.pNext = m_Vulkan->features;
    m_PyroDeviceInfo.queueCreateInfoCount = 1;
    m_PyroDeviceInfo.pQueueCreateInfos = &m_PyroQueueCreateInfo;
    m_PyroDeviceInfo.enabledExtensionCount = (uint32_t)m_Vulkan->num_extensions;
    m_PyroDeviceInfo.ppEnabledExtensionNames = m_Vulkan->extensions;

    // libplacebo creates its queues without flags, so vkGetDeviceQueue is valid here
    auto fn_vkGetDeviceQueue = (PFN_vkGetDeviceQueue)fn_vkGetDeviceProcAddr(m_Vulkan->device, "vkGetDeviceQueue");
    if (fn_vkGetDeviceQueue == nullptr) {
        SDL_LogError(SDL_LOG_CATEGORY_APPLICATION, "PyroWave: vkGetDeviceQueue is unavailable");
        return false;
    }
    m_PyroQueue.familyIndex = (uint32_t)m_Vulkan->queue_graphics.index;
    m_PyroQueue.index = 0;
    fn_vkGetDeviceQueue(m_Vulkan->device, m_PyroQueue.familyIndex, 0, &m_PyroQueue.queue);

    return true;
}

void PyroWaveVideoDecoder::pyroQueueLock(void* userdata)
{
    auto me = static_cast<PyroWaveVideoDecoder*>(userdata);
    me->m_Vulkan->lock_queue(me->m_Vulkan, me->m_PyroQueue.familyIndex, 0);
}

void PyroWaveVideoDecoder::pyroQueueUnlock(void* userdata)
{
    auto me = static_cast<PyroWaveVideoDecoder*>(userdata);
    me->m_Vulkan->unlock_queue(me->m_Vulkan, me->m_PyroQueue.familyIndex, 0);
}

bool PyroWaveVideoDecoder::createPyroWaveDecoder()
{
    pyrowave_device_create_info deviceInfo = {};
    deviceInfo.GetInstanceProcAddr = m_PlVkInstance->get_proc_addr;
    deviceInfo.instance = m_PlVkInstance->instance;
    deviceInfo.physical_device = m_Vulkan->phys_device;
    deviceInfo.device = m_Vulkan->device;
    deviceInfo.instance_create_info = &m_PyroInstanceInfo;
    deviceInfo.device_create_info = &m_PyroDeviceInfo;
    deviceInfo.queue_info = &m_PyroQueue;
    deviceInfo.queue_info_count = 1;
    deviceInfo.queue_lock_callback = pyroQueueLock;
    deviceInfo.queue_unlock_callback = pyroQueueUnlock;
    deviceInfo.userdata = this;

    pyrowave_result res = m_Lib->pyrowave_create_device(&deviceInfo, &m_PyroDevice);
    if (res != PYROWAVE_SUCCESS) {
        m_PyroDevice = nullptr;
        SDL_LogError(SDL_LOG_CATEGORY_APPLICATION,
                     "PyroWave: pyrowave_create_device() failed: %d", (int)res);
        return false;
    }

    // Decode where the result is consumed
    m_Lib->pyrowave_device_set_queue_type(m_PyroDevice, VK_QUEUE_GRAPHICS_BIT);

    pyrowave_decoder_create_info decoderInfo = {};
    decoderInfo.device = m_PyroDevice;
    decoderInfo.width = m_Width;
    decoderInfo.height = m_Height;
    decoderInfo.chroma = m_Yuv444 ? PYROWAVE_CHROMA_SUBSAMPLING_444 : PYROWAVE_CHROMA_SUBSAMPLING_420;
    // The fragment path renders into the planes, so it also needs renderable planes
    decoderInfo.fragment_path = m_Lib->pyrowave_decoder_device_prefers_fragment_path(m_PyroDevice) &&
                                findPlaneFormat(true) != nullptr;
    m_FragmentPath = decoderInfo.fragment_path;
    res = m_Lib->pyrowave_decoder_create(&decoderInfo, &m_PyroDecoder);
    if (res != PYROWAVE_SUCCESS) {
        m_PyroDecoder = nullptr;
        SDL_LogError(SDL_LOG_CATEGORY_APPLICATION,
                     "PyroWave: pyrowave_decoder_create(%dx%d) failed: %d", m_Width, m_Height, (int)res);
        return false;
    }

    SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION,
                "PyroWave: decoding with the %s path", decoderInfo.fragment_path ? "fragment" : "compute");
    return true;
}

pl_fmt PyroWaveVideoDecoder::findPlaneFormat(bool renderable)
{
    // 10-bit streams use R16 planes: the host writes normalized UNORM values into
    // 16-bit containers (not 10-bit samples shifted into them), so the full 16 bits
    // are the colour depth. 8-bit streams use R8 planes.
    const int depth = m_TenBit ? 16 : 8;
    int caps = PL_FMT_CAP_SAMPLEABLE | PL_FMT_CAP_STORABLE | PL_FMT_CAP_LINEAR;
    if (renderable) {
        caps |= PL_FMT_CAP_RENDERABLE;
    }
    return pl_find_fmt(m_Vulkan->gpu, PL_FMT_UNORM, 1, depth, depth, (pl_fmt_caps)caps);
}

bool PyroWaveVideoDecoder::createSlots()
{
    const int depth = m_TenBit ? 16 : 8;
    const VkFormat expectedFormat = m_TenBit ? VK_FORMAT_R16_UNORM : VK_FORMAT_R8_UNORM;
    const VkImageUsageFlags requiredUsage = m_FragmentPath ? VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT : VK_IMAGE_USAGE_STORAGE_BIT;
    pl_fmt fmt = findPlaneFormat(m_FragmentPath);
    if (fmt == nullptr) {
        SDL_LogError(SDL_LOG_CATEGORY_APPLICATION,
                     "PyroWave: no storable, filterable %d-bit single-channel format", depth);
        return false;
    }

    pl_vulkan_sem_params semParams = {};
    semParams.type = VK_SEMAPHORE_TYPE_TIMELINE;
    semParams.initial_value = 0;
    semParams.debug_tag = PL_DEBUG_TAG;
    m_DecodeTimeline = pl_vulkan_sem_create(m_Vulkan->gpu, &semParams);
    m_RenderTimeline = pl_vulkan_sem_create(m_Vulkan->gpu, &semParams);
    if (m_DecodeTimeline == VK_NULL_HANDLE || m_RenderTimeline == VK_NULL_HANDLE) {
        SDL_LogError(SDL_LOG_CATEGORY_APPLICATION, "PyroWave: unable to create timeline semaphores");
        return false;
    }

    const int chromaWidth = m_Yuv444 ? m_Width : m_Width / 2;
    const int chromaHeight = m_Yuv444 ? m_Height : m_Height / 2;

    for (auto& slot : m_Slots) {
        for (int i = 0; i < 3; i++) {
            pl_tex_params texParams = {};
            texParams.w = i == 0 ? m_Width : chromaWidth;
            texParams.h = i == 0 ? m_Height : chromaHeight;
            texParams.format = fmt;
            texParams.sampleable = true;
            texParams.storable = true;
            texParams.renderable = m_FragmentPath;
            texParams.debug_tag = PL_DEBUG_TAG;
            slot.planes[i] = pl_tex_create(m_Vulkan->gpu, &texParams);
            if (slot.planes[i] == nullptr) {
                SDL_LogError(SDL_LOG_CATEGORY_APPLICATION, "PyroWave: pl_tex_create() failed");
                return false;
            }

            VkFormat format;
            VkImageUsageFlags usage;
            slot.images[i] = pl_vulkan_unwrap(m_Vulkan->gpu, slot.planes[i], &format, &usage);
            if (slot.images[i] == VK_NULL_HANDLE || format != expectedFormat || !(usage & requiredUsage)) {
                SDL_LogError(SDL_LOG_CATEGORY_APPLICATION,
                             "PyroWave: plane texture is not a %s %s image",
                             m_FragmentPath ? "renderable" : "storage",
                             m_TenBit ? "R16_UNORM" : "R8_UNORM");
                return false;
            }

            // Hand the plane to PyroWave. The hold makes libplacebo move it to GENERAL,
            // which is the layout PyroWave's compute path writes in.
            if (!holdPlane(slot.planes[i])) {
                return false;
            }
        }

        slot.lastAccess = { m_RenderTimeline, m_RenderTimelineValue };
    }

    // Holds are only flushed with other work; make sure the initial ones are submitted
    pl_gpu_flush(m_Vulkan->gpu);
    return true;
}

bool PyroWaveVideoDecoder::holdPlane(pl_tex plane)
{
    // Only called from one thread at a time (initialization, then the render thread),
    // so render timeline values are always signalled in increasing order.
    m_RenderTimelineValue++;

    pl_vulkan_hold_params holdParams = {};
    holdParams.tex = plane;
    holdParams.layout = VK_IMAGE_LAYOUT_GENERAL;
    holdParams.qf = VK_QUEUE_FAMILY_IGNORED;
    holdParams.semaphore = { m_RenderTimeline, m_RenderTimelineValue };
    if (!pl_vulkan_hold_ex(m_Vulkan->gpu, &holdParams)) {
        SDL_LogError(SDL_LOG_CATEGORY_APPLICATION, "PyroWave: pl_vulkan_hold_ex() failed");
        return false;
    }
    return true;
}

bool PyroWaveVideoDecoder::createSwapchain()
{
    pl_vulkan_swapchain_params swapchainParams = {};
    swapchainParams.surface = m_VkSurface;
    swapchainParams.present_mode = m_PresentMode;
    // Double-buffered for the lowest display latency, as PlVkRenderer starts with
    swapchainParams.swapchain_depth = 1;
#if PL_API_VER >= 338
    swapchainParams.disable_10bit_sdr = true; // Some drivers don't dither 10-bit SDR output correctly
#endif

    DrmMasterLocker locker;
    m_Swapchain = pl_vulkan_create_swapchain(m_Vulkan, &swapchainParams);
    if (m_Swapchain == nullptr) {
        SDL_LogError(SDL_LOG_CATEGORY_APPLICATION, "PyroWave: pl_vulkan_create_swapchain() failed");
        return false;
    }
    return true;
}

PyroWaveVideoDecoder::StreamColorimetry PyroWaveVideoDecoder::currentColorimetry()
{
    // This is what getDecoderColorspace()/getDecoderColorRange() asked the host for:
    // full range, BT.709 for SDR and BT.2020 NCL/PQ once the host display is in HDR
    // mode (Sunshine derivatives switch to BT.2020 for HDR regardless of the request).
    // SDR uses BT.1886 like an HEVC stream's BT.709 transfer does through
    // PlVkRenderer, so PyroWave vs HEVC A/B tests compare like with like.
    StreamColorimetry c = {};
    c.hdr = m_TenBit && m_HostHdrMode.load();

    c.color.primaries = c.hdr ? PL_COLOR_PRIM_BT_2020 : PL_COLOR_PRIM_BT_709;
    c.color.transfer = c.hdr ? PL_COLOR_TRC_PQ : PL_COLOR_TRC_BT_1886;

    c.repr.sys = c.hdr ? PL_COLOR_SYSTEM_BT_2020_NC : PL_COLOR_SYSTEM_BT_709;
    c.repr.levels = PL_COLOR_LEVELS_FULL;
    c.repr.alpha = PL_ALPHA_NONE;
    c.repr.bits.sample_depth = m_TenBit ? 16 : 8;
    c.repr.bits.color_depth = m_TenBit ? 16 : 8;
    c.repr.bits.bit_shift = 0;

    if (c.hdr) {
        // Same mapping as PlVkRenderer gets from FFmpeg for other codecs: the host's
        // mastering metadata (re-read every frame, so mid-stream updates apply), and
        // PL_COLOR_HDR_BLACK for an unspecified minimum since we trust the host values.
        // Nothing here assumes anything about the local panel.
        SS_HDR_METADATA hdrMetadata;
        if (LiGetHdrMetadata(&hdrMetadata)) {
            if (hdrMetadata.displayPrimaries[0].x != 0) {
                c.color.hdr.prim.red = { hdrMetadata.displayPrimaries[0].x / 50000.0f, hdrMetadata.displayPrimaries[0].y / 50000.0f };
                c.color.hdr.prim.green = { hdrMetadata.displayPrimaries[1].x / 50000.0f, hdrMetadata.displayPrimaries[1].y / 50000.0f };
                c.color.hdr.prim.blue = { hdrMetadata.displayPrimaries[2].x / 50000.0f, hdrMetadata.displayPrimaries[2].y / 50000.0f };
                c.color.hdr.prim.white = { hdrMetadata.whitePoint.x / 50000.0f, hdrMetadata.whitePoint.y / 50000.0f };
            }
            if (hdrMetadata.maxDisplayLuminance != 0) {
                c.color.hdr.max_luma = hdrMetadata.maxDisplayLuminance;
                c.color.hdr.min_luma = hdrMetadata.minDisplayLuminance / 10000.0f;
            }
            c.color.hdr.max_cll = hdrMetadata.maxContentLightLevel;
            c.color.hdr.max_fall = hdrMetadata.maxFrameAverageLightLevel;

            if (c.color.hdr.min_luma == 0) {
                c.color.hdr.min_luma = PL_COLOR_HDR_BLACK;
            }
        }
    }

    return c;
}

void PyroWaveVideoDecoder::checkSequenceHeader(const uint8_t* data, size_t size)
{
    if (size < 8) {
        return;
    }

    uint32_t word0 = readLe32(data);
    uint32_t word1 = readLe32(data + 4);

    // Only the start-of-frame sequence header (extended = 1, code = 0) carries these fields
    if (!(word0 & 0x80000000u) || ((word1 >> 24) & 0x3) != 0) {
        return;
    }

    const int width = (int)(word0 & 0x3FFF) + 1;
    const int height = (int)((word0 >> 14) & 0x3FFF) + 1;
    const bool chroma444 = !!(word1 & k_SeqChroma444);
    if (width != m_Width || height != m_Height || chroma444 != m_Yuv444) {
        if (m_LastSequenceColorimetry != (word1 | 1u)) {
            SDL_LogError(SDL_LOG_CATEGORY_APPLICATION,
                         "PyroWave: host is sending %dx%d %s, but %dx%d %s was negotiated",
                         width, height, chroma444 ? "4:4:4" : "4:2:0",
                         m_Width, m_Height, m_Yuv444 ? "4:4:4" : "4:2:0");
            m_LastSequenceColorimetry = word1 | 1u;
        }
        return;
    }

    const bool hdr = m_TenBit && m_HostHdrMode.load();
    const uint32_t expected = hdr ? (k_SeqPrimaries2020 | k_SeqTransferPq | k_SeqMatrix2020) : 0;
    const uint32_t actual = word1 & k_SeqColorimetryMask;

    // Warn once per distinct (signalled, expected) combination
    const uint32_t key = actual | (hdr ? 1u : 0u);
    if (actual != expected && key != m_LastSequenceColorimetry) {
        SDL_LogWarn(SDL_LOG_CATEGORY_APPLICATION,
                    "PyroWave: bitstream colorimetry (%s primaries, %s transfer, %s matrix, %s range, %s chroma) "
                    "differs from the negotiated %s/%s/%s, full range, centre chroma%s",
                    (actual & k_SeqPrimaries2020) ? "BT.2020" : "BT.709",
                    (actual & k_SeqTransferPq) ? "PQ" : "BT.709",
                    (actual & k_SeqMatrix2020) ? "BT.2020" : "BT.709",
                    (actual & k_SeqRangeLimited) ? "limited" : "full",
                    (actual & k_SeqSitingLeft) ? "left" : "centre",
                    hdr ? "BT.2020" : "BT.709", hdr ? "PQ" : "BT.709", hdr ? "BT.2020" : "BT.709",
                    actual == 0 ? " (the host may not be signalling colorimetry at all)" : "");
    }
    m_LastSequenceColorimetry = key;
}

int PyroWaveVideoDecoder::submitDecodeUnit(PDECODE_UNIT du)
{
    // Stats bookkeeping, mirroring FFmpegVideoDecoder
    if (m_LastFrameNumber == 0) {
        m_ActiveWndVideoStats.measurementStartUs = LiGetMicroseconds();
        m_LastFrameNumber = du->frameNumber;
    }
    else {
        m_ActiveWndVideoStats.networkDroppedFrames += du->frameNumber - (m_LastFrameNumber + 1);
        m_ActiveWndVideoStats.totalFrames += du->frameNumber - (m_LastFrameNumber + 1);
        m_LastFrameNumber = du->frameNumber;
    }

    m_BwTracker.AddBytes(du->fullLength);

    if (LiGetMicroseconds() > m_ActiveWndVideoStats.measurementStartUs + 1000000) {
        updateStatsWindow();
    }

    if (du->frameHostProcessingLatency != 0) {
        if (m_ActiveWndVideoStats.minHostProcessingLatency != 0) {
            m_ActiveWndVideoStats.minHostProcessingLatency = qMin(m_ActiveWndVideoStats.minHostProcessingLatency, du->frameHostProcessingLatency);
        }
        else {
            m_ActiveWndVideoStats.minHostProcessingLatency = du->frameHostProcessingLatency;
        }
        m_ActiveWndVideoStats.framesWithHostProcessingLatency += 1;
    }
    m_ActiveWndVideoStats.maxHostProcessingLatency = qMax(m_ActiveWndVideoStats.maxHostProcessingLatency, du->frameHostProcessingLatency);
    m_ActiveWndVideoStats.totalHostProcessingLatency += du->frameHostProcessingLatency;
    m_ActiveWndVideoStats.receivedFrames++;
    m_ActiveWndVideoStats.totalFrames++;

    const uint64_t decodeStartUs = LiGetMicroseconds();

    // The host frames each video frame as [u32 count] { [u32 size] [size bytes] } * count,
    // little-endian, one PyroWave packet per entry. Gather it into one buffer first.
    m_FrameBuffer.resize((size_t)du->fullLength);
    size_t offset = 0;
    for (PLENTRY entry = du->bufferList; entry != nullptr; entry = entry->next) {
        if (entry->length < 0 || offset + (size_t)entry->length > m_FrameBuffer.size()) {
            return DR_OK;
        }
        memcpy(m_FrameBuffer.data() + offset, entry->data, (size_t)entry->length);
        offset += (size_t)entry->length;
    }

    const uint8_t* data = m_FrameBuffer.data();
    const size_t length = offset;
    if (length < 4) {
        return DR_OK;
    }

    // PyroWave's frame sequence counter is only 3 bits, and the decoder ignores packets
    // whose sequence looks older than the last one. After a burst of 3+ lost frames a
    // new frame can look "older", and several good frames would be discarded until the
    // counter comes round again. Frames reach us complete and in order, so that check
    // buys nothing here: forget the old sequence whenever a frame was skipped.
    if (m_LastPushedFrameNumber != 0 && du->frameNumber != m_LastPushedFrameNumber + 1) {
        m_Lib->pyrowave_decoder_clear(m_PyroDecoder);
    }
    m_LastPushedFrameNumber = du->frameNumber;

    // A partial frame (see DECODE_UNIT::isPartial) ends at an arbitrary byte, so the
    // declared count can exceed what is present; stop at the first incomplete packet.
    const uint32_t declaredPackets = readLe32(data);
    uint32_t pushedPackets = 0;
    size_t pos = 4;
    for (uint32_t i = 0; i < declaredPackets && pos + 4 <= length; i++) {
        const uint32_t packetSize = readLe32(data + pos);
        pos += 4;
        if (packetSize == 0 || packetSize > k_MaxPacketSize || packetSize > length - pos) {
            break;
        }

        if (i == 0) {
            checkSequenceHeader(data + pos, packetSize);
        }

        pyrowave_result res = m_Lib->pyrowave_decoder_push_packet(m_PyroDecoder, data + pos, packetSize);
        if (res != PYROWAVE_SUCCESS && !m_LoggedPushFailure) {
            SDL_LogWarn(SDL_LOG_CATEGORY_APPLICATION,
                        "PyroWave: rejected a packet in frame %d (%d); further rejections are not logged",
                        du->frameNumber, (int)res);
            m_LoggedPushFailure = true;
        }
        else if (res == PYROWAVE_SUCCESS) {
            pushedPackets++;
        }
        pos += packetSize;
    }

    const bool ready = m_Lib->pyrowave_decoder_decode_is_ready_with_sideband(m_PyroDecoder, true,
                                                                             m_PristineBands, m_MinBlockRatio,
                                                                             nullptr, 0);
    if (du->isPartial) {
        m_ActivePyroStats.partialPacketsPushed += pushedPackets;
        m_ActivePyroStats.partialPacketsDeclared += declaredPackets;
        if (ready) {
            m_ActivePyroStats.partialShown++;
        }
        else {
            m_ActivePyroStats.partialRejected++;
        }
    }
    if (!ready) {
        return DR_OK;
    }

    // Choose where to decode: a free slot, else the newest undisplayed frame, which this
    // one replaces. With 3 slots one of the two always exists: at most one slot is being
    // presented and at most one is waiting to be.
    int slotIndex = -1;
    pl_vulkan_sem acquireAfter = {};
    {
        std::lock_guard<std::mutex> lock(m_SlotLock);
        for (int i = 0; i < k_SlotCount; i++) {
            if (m_Slots[i].state == SlotState::Free) {
                slotIndex = i;
                break;
            }
        }
        if (slotIndex < 0 && m_LatestDecodedSlot >= 0) {
            slotIndex = m_LatestDecodedSlot;
            m_LatestDecodedSlot = -1;
            m_DroppedFrames++;
        }
        if (slotIndex < 0) {
            SDL_assert(false);
            return DR_OK;
        }
        m_Slots[slotIndex].state = SlotState::Decoding;
        acquireAfter = m_Slots[slotIndex].lastAccess;
    }

    FrameSlot& slot = m_Slots[slotIndex];
    const VkFormat planeFormat = m_TenBit ? VK_FORMAT_R16_UNORM : VK_FORMAT_R8_UNORM;
    pyrowave_gpu_buffers buffers = {};
    for (int i = 0; i < 3; i++) {
        pyrowave_image_view& view = buffers.planes[i];
        view.image = slot.images[i];
        view.width = (uint32_t)slot.planes[i]->params.w;
        view.height = (uint32_t)slot.planes[i]->params.h;
        view.image_format = planeFormat;
        view.view_format = planeFormat;
        view.aspect = VK_IMAGE_ASPECT_COLOR_BIT;
        view.swizzle = VK_COMPONENT_SWIZZLE_IDENTITY;
        view.layout = VK_IMAGE_LAYOUT_GENERAL;
    }

    const uint64_t decodeValue = m_DecodeTimelineValue + 1;
    pyrowave_gpu_sync_operation acquire = {};
    acquire.sync.semaphore = acquireAfter.sem;
    acquire.sync.value = acquireAfter.value;
    pyrowave_gpu_sync_operation release = {};
    release.sync.semaphore = m_DecodeTimeline;
    release.sync.value = decodeValue;

    pyrowave_result res = m_Lib->pyrowave_decoder_decode_gpu_buffer(m_PyroDecoder, &acquire, &release, &buffers);

    std::unique_lock<std::mutex> lock(m_SlotLock);
    if (res != PYROWAVE_SUCCESS) {
        // Nothing was submitted, so the slot's last access is unchanged
        slot.state = SlotState::Free;
        lock.unlock();
        SDL_LogError(SDL_LOG_CATEGORY_APPLICATION,
                     "PyroWave: decode of frame %d failed: %d", du->frameNumber, (int)res);
        return DR_OK;
    }

    m_DecodeTimelineValue = decodeValue;
    slot.decodeValue = decodeValue;
    slot.lastAccess = { m_DecodeTimeline, decodeValue };
    slot.frameNumber = du->frameNumber;
    slot.decodeSubmitUs = LiGetMicroseconds();
    slot.state = SlotState::Decoded;

    // Latest wins: an older frame still waiting to be presented is dropped
    if (m_LatestDecodedSlot >= 0 && m_LatestDecodedSlot != slotIndex) {
        m_Slots[m_LatestDecodedSlot].state = SlotState::Free;
        m_DroppedFrames++;
    }
    m_LatestDecodedSlot = slotIndex;
    lock.unlock();
    m_FrameAvailable.notify_one();

    m_ActiveWndVideoStats.decodedFrames++;
    m_ActiveWndVideoStats.totalDecodeTimeUs += LiGetMicroseconds() - decodeStartUs;
    m_ActiveWndVideoStats.totalReassemblyTimeUs += du->enqueueTimeUs - du->receiveTimeUs;
    return DR_OK;
}

void PyroWaveVideoDecoder::renderThreadProc()
{
    std::unique_lock<std::mutex> lock(m_SlotLock);
    for (;;) {
        m_FrameAvailable.wait(lock, [this] { return m_Stopping || m_LatestDecodedSlot >= 0; });
        if (m_Stopping) {
            break;
        }

        lock.unlock();
        renderLatestFrame();
        lock.lock();
    }
}

void PyroWaveVideoDecoder::renderLatestFrame()
{
    if (pl_gpu_is_failed(m_Vulkan->gpu)) {
        SDL_LogError(SDL_LOG_CATEGORY_APPLICATION, "PyroWave: GPU is in failed state. Recreating renderer.");
        SDL_Event event;
        event.type = SDL_RENDER_DEVICE_RESET;
        SDL_PushEvent(&event);

        // Avoid spinning on the same failure until the session recreates us
        std::lock_guard<std::mutex> lock(m_SlotLock);
        if (m_LatestDecodedSlot >= 0) {
            m_Slots[m_LatestDecodedSlot].state = SlotState::Free;
            m_LatestDecodedSlot = -1;
        }
        return;
    }

    // Wait for queued presents first, so the frame latched below is the newest one
    // that can actually be shown next (same approach as PlVkRenderer::waitToRender()).
    pl_swapchain_swap_buffers(m_Swapchain);

    int drawableWidth, drawableHeight;
    SDL_Vulkan_GetDrawableSize(m_Window, &drawableWidth, &drawableHeight);
    pl_swapchain_frame swapchainFrame;
    bool haveSwapchainFrame = pl_swapchain_resize(m_Swapchain, &drawableWidth, &drawableHeight) &&
                              pl_swapchain_start_frame(m_Swapchain, &swapchainFrame);

    int slotIndex;
    uint64_t latchUs = LiGetMicroseconds();
    {
        std::lock_guard<std::mutex> lock(m_SlotLock);
        slotIndex = m_LatestDecodedSlot;
        m_LatestDecodedSlot = -1;
        if (slotIndex < 0) {
            // Can't happen with a single render thread, but stay balanced if it does
            if (haveSwapchainFrame) {
                pl_swapchain_submit_frame(m_Swapchain);
            }
            return;
        }
        if (!haveSwapchainFrame) {
            // Occluded or minimized: the frame is dropped, its planes stay with PyroWave
            m_Slots[slotIndex].state = SlotState::Free;
            m_DroppedFrames++;
            return;
        }
        m_Slots[slotIndex].state = SlotState::Presenting;
    }

    FrameSlot& slot = m_Slots[slotIndex];
    const uint64_t renderStartUs = LiGetMicroseconds();
    m_QueueDelayUs += latchUs - slot.decodeSubmitUs;

    // Give the planes back to libplacebo once the decode has completed on the GPU
    for (auto plane : slot.planes) {
        pl_vulkan_release_params releaseParams = {};
        releaseParams.tex = plane;
        releaseParams.layout = VK_IMAGE_LAYOUT_GENERAL;
        releaseParams.qf = VK_QUEUE_FAMILY_IGNORED;
        releaseParams.semaphore = { m_DecodeTimeline, slot.decodeValue };
        pl_vulkan_release_ex(m_Vulkan->gpu, &releaseParams);
    }

    const StreamColorimetry colorimetry = currentColorimetry();

    pl_frame source = {};
    source.num_planes = 3;
    for (int i = 0; i < 3; i++) {
        source.planes[i].texture = slot.planes[i];
        source.planes[i].components = 1;
        source.planes[i].component_mapping[0] = i == 0 ? PL_CHANNEL_Y : (i == 1 ? PL_CHANNEL_CB : PL_CHANNEL_CR);
    }
    source.repr = colorimetry.repr;
    source.color = colorimetry.color;
    source.crop = { 0, 0, (float)m_Width, (float)m_Height };
    if (!m_Yuv444) {
        // PyroWave's reference converter and the Vibepollo host both build 4:2:0 chroma
        // as a 2x2 box average: centre siting. (A no-op offset, stated for clarity.)
        pl_frame_set_chroma_location(&source, PL_CHROMA_CENTER);
    }

    // The swapchain follows the stream: an HDR10 swapchain (with the host's metadata
    // via VK_EXT_hdr_metadata) whenever the surface offers one, re-hinted whenever the
    // colour space or metadata changes mid-stream.
    if (!pl_color_space_equal(&colorimetry.color, &m_LastSwapchainHint)) {
        m_LastSwapchainHint = colorimetry.color;
        pl_swapchain_colorspace_hint(m_Swapchain, &colorimetry.color);
    }

    pl_frame target;
    pl_frame_from_swapchain(&target, &swapchainFrame);

    SDL_Rect src = { 0, 0, m_Width, m_Height };
    SDL_Rect dst;
    dst.x = (int)target.crop.x0;
    dst.y = (int)target.crop.y0;
    dst.w = (int)(target.crop.x1 - target.crop.x0);
    dst.h = (int)(target.crop.y1 - target.crop.y0);
    StreamUtils::scaleSourceToDestinationSurface(&src, &dst);
    target.crop = { (float)dst.x, (float)dst.y, (float)(dst.x + dst.w), (float)(dst.y + dst.h) };

    pl_overlay_part overlayParts[Overlay::OverlayMax] = {};
    std::vector<pl_overlay> overlays;
    std::vector<pl_tex> texturesToDestroy;
    overlays.reserve(Overlay::OverlayMax);
    texturesToDestroy.reserve(Overlay::OverlayMax);
    buildOverlays(target, overlayParts, overlays, texturesToDestroy);
    target.num_overlays = (int)overlays.size();
    target.overlays = overlays.data();

    logOutputColorspace(source, target);

    // pl_render_fast_params, exactly as PlVkRenderer uses: no peak detection, no
    // debanding, no dithering, default static colour mapping. libplacebo only tone maps
    // when the target can't represent the source (e.g. an SDR swapchain); with an HDR10
    // swapchain the target carries the source metadata and the display does the mapping.
    if (!pl_render_image(m_Renderer, &source, &target, &pl_render_fast_params)) {
        SDL_LogError(SDL_LOG_CATEGORY_APPLICATION, "PyroWave: pl_render_image() failed");
        // NB: fall through, the swapchain frame must be submitted regardless
    }

    // Hand the planes back to PyroWave. The next decode into this slot waits for this.
    for (auto plane : slot.planes) {
        holdPlane(plane);
    }

    const bool submitted = pl_swapchain_submit_frame(m_Swapchain);

    {
        std::lock_guard<std::mutex> lock(m_SlotLock);
        slot.lastAccess = { m_RenderTimeline, m_RenderTimelineValue };
        slot.state = SlotState::Free;
    }

    for (pl_tex& texture : texturesToDestroy) {
        pl_tex_destroy(m_Vulkan->gpu, &texture);
    }

    if (!submitted) {
        SDL_LogError(SDL_LOG_CATEGORY_APPLICATION, "PyroWave: pl_swapchain_submit_frame() failed");
        SDL_Event event;
        event.type = SDL_RENDER_DEVICE_RESET;
        SDL_PushEvent(&event);
        return;
    }

    m_RenderedFrames++;
    m_RenderTimeUs += LiGetMicroseconds() - renderStartUs;
}

void PyroWaveVideoDecoder::logOutputColorspace(const pl_frame& source, const pl_frame& target)
{
    {
        std::lock_guard<std::mutex> lock(m_HdrStatusLock);
        m_HdrStatusSource = source.color;
        m_HdrStatusTarget = target.color;
        m_HdrStatusValid = true;
    }

    if (pl_color_space_equal(&target.color, &m_LastOutputColorspace)) {
        return;
    }
    m_LastOutputColorspace = target.color;

    const bool hdrSource = source.color.transfer == PL_COLOR_TRC_PQ;
    const bool hdrTarget = target.color.transfer == PL_COLOR_TRC_PQ;
    const char* mapping;
    if (!hdrSource) {
        mapping = "SDR, no tone mapping";
    }
    else if (!hdrTarget) {
        mapping = "libplacebo tone maps PQ to the SDR swapchain (single mapping)";
    }
    else if (target.color.hdr.max_luma > 0 && source.color.hdr.max_luma > target.color.hdr.max_luma) {
        mapping = "libplacebo tone maps to the swapchain peak";
    }
    else {
        mapping = "HDR10 passthrough, no libplacebo tone mapping";
    }

    SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION,
                "PyroWave output: source %s/%s (max %.0f nits, min %.4f, MaxCLL %.0f, MaxFALL %.0f) -> "
                "swapchain %s/%s (max %.0f nits): %s",
                primariesName(source.color.primaries), transferName(source.color.transfer),
                source.color.hdr.max_luma, source.color.hdr.min_luma, source.color.hdr.max_cll, source.color.hdr.max_fall,
                primariesName(target.color.primaries), transferName(target.color.transfer),
                target.color.hdr.max_luma, mapping);
}

bool PyroWaveVideoDecoder::buildOverlays(const pl_frame& target, pl_overlay_part* parts,
                                         std::vector<pl_overlay>& overlays, std::vector<pl_tex>& texturesToDestroy)
{
    // Same staging/ownership protocol as PlVkRenderer::renderFrame()
    SDL_AtomicLock(&m_OverlayLock);
    for (int i = 0; i < Overlay::OverlayMax; i++) {
        if (m_Overlays[i].hasStagingOverlay) {
            if (m_Overlays[i].hasOverlay) {
                texturesToDestroy.push_back(m_Overlays[i].overlay.tex);
            }
            m_Overlays[i].overlay = m_Overlays[i].stagingOverlay;
            m_Overlays[i].hasStagingOverlay = false;
            SDL_zero(m_Overlays[i].stagingOverlay);
            m_Overlays[i].hasOverlay = true;
        }

        if (m_Overlays[i].hasOverlay && !Session::get()->getOverlayManager().isOverlayEnabled((Overlay::OverlayType)i)) {
            texturesToDestroy.push_back(m_Overlays[i].overlay.tex);
            SDL_zero(m_Overlays[i].overlay);
            m_Overlays[i].hasOverlay = false;
        }

        if (m_Overlays[i].hasOverlay) {
            parts[i].src = { 0, 0, (float)m_Overlays[i].overlay.tex->params.w, (float)m_Overlays[i].overlay.tex->params.h };
            parts[i].dst.x0 = 0;
            if (i == Overlay::OverlayStatusUpdate) {
                // Bottom left
                parts[i].dst.y0 = SDL_max(0, target.crop.y1 - parts[i].src.y1);
            }
            else {
                // Top left
                parts[i].dst.y0 = 0;
            }
            parts[i].dst.x1 = parts[i].dst.x0 + parts[i].src.x1;
            parts[i].dst.y1 = parts[i].dst.y0 + parts[i].src.y1;

            m_Overlays[i].overlay.parts = &parts[i];
            m_Overlays[i].overlay.num_parts = 1;
            overlays.push_back(m_Overlays[i].overlay);
        }
    }
    SDL_AtomicUnlock(&m_OverlayLock);
    return !overlays.empty();
}

void PyroWaveVideoDecoder::overlayUploadComplete(void* opaque)
{
    SDL_FreeSurface((SDL_Surface*)opaque);
}

// Takes ownership of surface in all cases (same as PlVkRenderer::createOverlay())
bool PyroWaveVideoDecoder::createOverlay(pl_overlay* overlay, SDL_Surface* surface)
{
    SDL_assert(surface->format->format == SDL_PIXELFORMAT_ARGB8888);
    pl_fmt texFormat = pl_find_named_fmt(m_Vulkan->gpu, "bgra8");
    if (texFormat == nullptr) {
        SDL_LogError(SDL_LOG_CATEGORY_APPLICATION, "PyroWave: pl_find_named_fmt(bgra8) failed");
        SDL_FreeSurface(surface);
        return false;
    }

    pl_tex_params texParams = {};
    texParams.w = surface->w;
    texParams.h = surface->h;
    texParams.format = texFormat;
    texParams.sampleable = true;
    texParams.host_writable = true;
    texParams.blit_src = !!(texFormat->caps & PL_FMT_CAP_BLITTABLE);
    texParams.debug_tag = PL_DEBUG_TAG;
    if (!pl_tex_recreate(m_Vulkan->gpu, &overlay->tex, &texParams)) {
        pl_tex_destroy(m_Vulkan->gpu, &overlay->tex);
        SDL_zerop(overlay);
        SDL_FreeSurface(surface);
        SDL_LogError(SDL_LOG_CATEGORY_APPLICATION, "PyroWave: pl_tex_recreate() failed");
        return false;
    }

    SDL_assert(!SDL_MUSTLOCK(surface));
    pl_tex_transfer_params xferParams = {};
    xferParams.tex = overlay->tex;
    xferParams.row_pitch = (size_t)surface->pitch;
    xferParams.ptr = surface->pixels;
    xferParams.callback = overlayUploadComplete;
    xferParams.priv = surface;
    if (!pl_tex_upload(m_Vulkan->gpu, &xferParams)) {
        pl_tex_destroy(m_Vulkan->gpu, &overlay->tex);
        SDL_zerop(overlay);
        SDL_FreeSurface(surface);
        SDL_LogError(SDL_LOG_CATEGORY_APPLICATION, "PyroWave: pl_tex_upload() failed");
        return false;
    }

    overlay->mode = PL_OVERLAY_NORMAL;
    overlay->coords = PL_OVERLAY_COORDS_DST_FRAME;
    overlay->repr = pl_color_repr_rgb;
    overlay->color = pl_color_space_srgb;
    return true;
}

void PyroWaveVideoDecoder::notifyOverlayUpdated(Overlay::OverlayType type)
{
    SDL_Surface* newSurface = Session::get()->getOverlayManager().getUpdatedOverlaySurface(type);
    if (newSurface == nullptr && Session::get()->getOverlayManager().isOverlayEnabled(type)) {
        // Enabled with no new surface: keep the existing texture
        return;
    }

    SDL_AtomicLock(&m_OverlayLock);
    m_Overlays[type].hasStagingOverlay = false;
    SDL_AtomicUnlock(&m_OverlayLock);

    if (newSurface == nullptr) {
        pl_tex_destroy(m_Vulkan->gpu, &m_Overlays[type].stagingOverlay.tex);
        SDL_zero(m_Overlays[type].stagingOverlay);
        return;
    }

    if (!createOverlay(&m_Overlays[type].stagingOverlay, newSurface)) {
        return;
    }

    SDL_AtomicLock(&m_OverlayLock);
    m_Overlays[type].hasStagingOverlay = true;
    SDL_AtomicUnlock(&m_OverlayLock);
}

void PyroWaveVideoDecoder::updateStatsWindow()
{
    m_ActiveWndVideoStats.renderedFrames = m_RenderedFrames.exchange(0);
    m_ActiveWndVideoStats.pacerDroppedFrames = m_DroppedFrames.exchange(0);
    m_ActiveWndVideoStats.totalRenderTimeUs = m_RenderTimeUs.exchange(0);
    m_ActiveWndVideoStats.totalPacerTimeUs = m_QueueDelayUs.exchange(0);

    if (Session::get() != nullptr && Session::get()->getOverlayManager().isOverlayEnabled(Overlay::OverlayDebug)) {
        VIDEO_STATS lastTwoWndStats = {};
        addVideoStats(m_LastWndVideoStats, lastTwoWndStats);
        addVideoStats(m_ActiveWndVideoStats, lastTwoWndStats);
        PyroWaveStats lastTwoWndPyroStats = {};
        addPyroWaveStats(m_LastPyroStats, lastTwoWndPyroStats);
        addPyroWaveStats(m_ActivePyroStats, lastTwoWndPyroStats);

        char* text = Session::get()->getOverlayManager().getOverlayText(Overlay::OverlayDebug);
        int maxLength = Session::get()->getOverlayManager().getOverlayMaxTextLength();
        if (Session::get()->getPreferences()->statsOverlayLite) {
            stringifyVideoStatsLite(lastTwoWndStats, text, maxLength);
        }
        else {
            stringifyVideoStats(lastTwoWndStats, lastTwoWndPyroStats, text, maxLength);
        }
        Session::get()->getOverlayManager().setOverlayTextUpdated(Overlay::OverlayDebug);
    }

    addVideoStats(m_ActiveWndVideoStats, m_GlobalVideoStats);
    addPyroWaveStats(m_ActivePyroStats, m_GlobalPyroStats);

    SDL_memcpy(&m_LastWndVideoStats, &m_ActiveWndVideoStats, sizeof(m_ActiveWndVideoStats));
    SDL_zero(m_ActiveWndVideoStats);
    m_ActiveWndVideoStats.measurementStartUs = LiGetMicroseconds();
    m_LastPyroStats = m_ActivePyroStats;
    m_ActivePyroStats = {};
}

void PyroWaveVideoDecoder::addPyroWaveStats(const PyroWaveStats& src, PyroWaveStats& dst)
{
    dst.partialShown += src.partialShown;
    dst.partialRejected += src.partialRejected;
    dst.partialPacketsPushed += src.partialPacketsPushed;
    dst.partialPacketsDeclared += src.partialPacketsDeclared;
}

int PyroWaveVideoDecoder::formatPyroWaveStatus(const PyroWaveStats& stats, char* output, int length)
{
    const uint32_t partial = stats.partialShown + stats.partialRejected;
    if (partial == 0) {
        return snprintf(output, length, "Partial frames: none (acceptance > %.2f of blocks)\n", m_MinBlockRatio);
    }
    return snprintf(output, length,
                    "Partial frames: %u shown, %u held back (acceptance > %.2f of blocks), %.0f%% of their packets arrived\n",
                    stats.partialShown, stats.partialRejected, m_MinBlockRatio,
                    stats.partialPacketsDeclared ? 100.0 * stats.partialPacketsPushed / stats.partialPacketsDeclared : 0.0);
}

void PyroWaveVideoDecoder::addVideoStats(VIDEO_STATS& src, VIDEO_STATS& dst)
{
    dst.receivedFrames += src.receivedFrames;
    dst.decodedFrames += src.decodedFrames;
    dst.renderedFrames += src.renderedFrames;
    dst.totalFrames += src.totalFrames;
    dst.networkDroppedFrames += src.networkDroppedFrames;
    dst.pacerDroppedFrames += src.pacerDroppedFrames;
    dst.totalReassemblyTimeUs += src.totalReassemblyTimeUs;
    dst.totalDecodeTimeUs += src.totalDecodeTimeUs;
    dst.totalPacerTimeUs += src.totalPacerTimeUs;
    dst.totalRenderTimeUs += src.totalRenderTimeUs;

    if (dst.minHostProcessingLatency == 0) {
        dst.minHostProcessingLatency = src.minHostProcessingLatency;
    }
    else if (src.minHostProcessingLatency != 0) {
        dst.minHostProcessingLatency = qMin(dst.minHostProcessingLatency, src.minHostProcessingLatency);
    }
    dst.maxHostProcessingLatency = qMax(dst.maxHostProcessingLatency, src.maxHostProcessingLatency);
    dst.totalHostProcessingLatency += src.totalHostProcessingLatency;
    dst.framesWithHostProcessingLatency += src.framesWithHostProcessingLatency;

    if (!LiGetEstimatedRttInfo(&dst.lastRtt, &dst.lastRttVariance)) {
        dst.lastRtt = 0;
        dst.lastRttVariance = 0;
    }

    if (!dst.measurementStartUs) {
        dst.measurementStartUs = src.measurementStartUs;
    }

    double timeDiffSecs = (double)(LiGetMicroseconds() - dst.measurementStartUs) / 1000000.0;
    if (timeDiffSecs > 0) {
        dst.totalFps = (double)dst.totalFrames / timeDiffSecs;
        dst.receivedFps = (double)dst.receivedFrames / timeDiffSecs;
        dst.decodedFps = (double)dst.decodedFrames / timeDiffSecs;
        dst.renderedFps = (double)dst.renderedFrames / timeDiffSecs;
    }
}

int PyroWaveVideoDecoder::formatHdrStatus(char* output, int length)
{
    pl_color_space sourceColor, targetColor;
    {
        std::lock_guard<std::mutex> lock(m_HdrStatusLock);
        if (!m_HdrStatusValid) {
            return snprintf(output, length, "HDR: waiting for the first frame\n");
        }
        sourceColor = m_HdrStatusSource;
        targetColor = m_HdrStatusTarget;
    }

    const char* chroma = m_Yuv444 ? "4:4:4" : "4:2:0";
    const char* depth = m_TenBit ? "10-bit" : "8-bit";

    if (sourceColor.transfer != PL_COLOR_TRC_PQ) {
        return snprintf(output, length, "HDR: off | PyroWave %s %s %s %s full | output %s/%s\n",
                        depth, chroma, transferName(sourceColor.transfer), primariesName(sourceColor.primaries),
                        primariesName(targetColor.primaries), transferName(targetColor.transfer));
    }

    // Only set from LiGetHdrMetadata(); without it libplacebo assumes generic HDR10 values
    const bool metadataReceived = sourceColor.hdr.prim.red.x != 0 || sourceColor.hdr.max_luma != 0 ||
                                  sourceColor.hdr.max_cll != 0 || sourceColor.hdr.max_fall != 0;
    char metadata[128];
    if (metadataReceived) {
        snprintf(metadata, sizeof(metadata), "metadata received: mastering %.4f-%.0f nits, MaxCLL %.0f, MaxFALL %.0f",
                 sourceColor.hdr.min_luma, sourceColor.hdr.max_luma, sourceColor.hdr.max_cll, sourceColor.hdr.max_fall);
    }
    else {
        snprintf(metadata, sizeof(metadata), "no metadata from host (HDR10 defaults)");
    }

    return snprintf(output, length,
                    "HDR: on | PyroWave %s %s PQ %s full | %s | output %s/%s%s\n",
                    depth, chroma, primariesName(sourceColor.primaries), metadata,
                    primariesName(targetColor.primaries), transferName(targetColor.transfer),
                    targetColor.transfer == PL_COLOR_TRC_PQ ? " (HDR10 passthrough)" : " (tone mapped to SDR)");
}

void PyroWaveVideoDecoder::stringifyVideoStats(VIDEO_STATS& stats, const PyroWaveStats& pyroStats, char* output, int length)
{
    int offset = 0;
    int ret;
    output[0] = 0;

    if (stats.receivedFps > 0) {
        ret = snprintf(&output[offset], length - offset,
                       "Video stream: %dx%d %.2f FPS (Codec: PyroWave %s %s%s)\n"
                       "Bitrate: %.1f Mbps, Peak (%us): %.1f\n"
                       "Incoming frame rate from network: %.2f FPS\n"
                       "Decoding frame rate: %.2f FPS\n"
                       "Rendering frame rate: %.2f FPS\n",
                       m_Width, m_Height, stats.totalFps,
                       m_TenBit ? "10-bit" : "8-bit",
                       m_Yuv444 ? "4:4:4" : "4:2:0",
                       (m_TenBit && m_HostHdrMode.load()) ? " HDR" : "",
                       m_BwTracker.GetAverageMbps(), m_BwTracker.GetWindowSeconds(), m_BwTracker.GetPeakMbps(),
                       stats.receivedFps, stats.decodedFps, stats.renderedFps);
        if (ret < 0 || ret >= length - offset) {
            return;
        }
        offset += ret;

        ret = formatHdrStatus(&output[offset], length - offset);
        if (ret < 0 || ret >= length - offset) {
            return;
        }
        offset += ret;

        ret = formatPyroWaveStatus(pyroStats, &output[offset], length - offset);
        if (ret < 0 || ret >= length - offset) {
            return;
        }
        offset += ret;
    }

    if (stats.framesWithHostProcessingLatency > 0) {
        ret = snprintf(&output[offset], length - offset,
                       "Host processing latency min/max/average: %.1f/%.1f/%.1f ms\n",
                       (float)stats.minHostProcessingLatency / 10,
                       (float)stats.maxHostProcessingLatency / 10,
                       (float)stats.totalHostProcessingLatency / 10 / stats.framesWithHostProcessingLatency);
        if (ret < 0 || ret >= length - offset) {
            return;
        }
        offset += ret;
    }

    if (stats.renderedFrames != 0 && stats.decodedFrames != 0 && stats.totalFrames != 0) {
        char rttString[32];
        if (stats.lastRtt != 0) {
            snprintf(rttString, sizeof(rttString), "%u ms (variance: %u ms)", stats.lastRtt, stats.lastRttVariance);
        }
        else {
            snprintf(rttString, sizeof(rttString), "N/A");
        }

        ret = snprintf(&output[offset], length - offset,
                       "Frames dropped by your network connection: %.2f%%\n"
                       "Frames replaced before display: %.2f%%\n"
                       "Average network latency: %s\n"
                       "Average reassembly/decode submit time: %.2f/%.2f ms\n"
                       "Average frame queue delay: %.2f ms\n"
                       "Average rendering time (including monitor V-sync latency): %.2f ms\n",
                       (float)stats.networkDroppedFrames / stats.totalFrames * 100,
                       (float)stats.pacerDroppedFrames / stats.decodedFrames * 100,
                       rttString,
                       (double)(stats.totalReassemblyTimeUs / 1000.0) / stats.decodedFrames,
                       (double)(stats.totalDecodeTimeUs / 1000.0) / stats.decodedFrames,
                       (double)(stats.totalPacerTimeUs / 1000.0) / stats.renderedFrames,
                       (double)(stats.totalRenderTimeUs / 1000.0) / stats.renderedFrames);
        if (ret < 0 || ret >= length - offset) {
            return;
        }
        offset += ret;
    }
}

void PyroWaveVideoDecoder::stringifyVideoStatsLite(VIDEO_STATS& stats, char* output, int length)
{
    // Same single-line format as FFmpegVideoDecoder::stringifyVideoStatsLite()
    double decodeMs = stats.decodedFrames != 0 ? (double)(stats.totalDecodeTimeUs / 1000.0) / stats.decodedFrames : 0.0;
    double lossPct = stats.totalFrames != 0 ? (float)stats.networkDroppedFrames / stats.totalFrames * 100 : 0.0;
    snprintf(output, length, "%.1f Mbps | Delay: %u/%.1f ms | Loss: %.1f%% | FPS: %.0f",
             m_BwTracker.GetAverageMbps(), stats.lastRtt, decodeMs, lossPct, stats.totalFps);
}

bool PyroWaveVideoDecoder::isHardwareAccelerated()
{
    return true;
}

bool PyroWaveVideoDecoder::isAlwaysFullScreen()
{
    return false;
}

bool PyroWaveVideoDecoder::isHdrSupported()
{
    // libplacebo presents HDR10 when the surface supports it and tone maps otherwise
    return true;
}

int PyroWaveVideoDecoder::getDecoderCapabilities()
{
    // Every frame is intra-coded: no reference frame invalidation, and decode stays
    // off the receive thread so a slow submission can't back up the socket.
    return 0;
}

int PyroWaveVideoDecoder::getDecoderColorspace()
{
    // Rendering goes through libplacebo, so request BT.709 like PlVkRenderer does.
    // (Sunshine derivatives switch to BT.2020 by themselves for HDR.)
    return COLORSPACE_REC_709;
}

int PyroWaveVideoDecoder::getDecoderColorRange()
{
    // Full range: no raised blacks, and a 16-bit plane is then unambiguous
    // (limited-range levels would depend on how the host scales 10-bit into 16).
    return COLOR_RANGE_FULL;
}

QSize PyroWaveVideoDecoder::getDecoderMaxResolution()
{
    return QSize(0, 0);
}

void PyroWaveVideoDecoder::renderFrameOnMainThread()
{
    // Frames are presented from the render thread
}

void PyroWaveVideoDecoder::setHdrMode(bool enabled)
{
    m_HostHdrMode = enabled;
    SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION, "PyroWave: host HDR mode %s", enabled ? "on" : "off");
}

bool PyroWaveVideoDecoder::notifyWindowChanged(PWINDOW_STATE_CHANGE_INFO info)
{
    // The swapchain is resized per frame, so size and display changes need no recreation
    return !(info->stateChangeFlags & ~(WINDOW_STATE_CHANGE_SIZE | WINDOW_STATE_CHANGE_DISPLAY));
}
