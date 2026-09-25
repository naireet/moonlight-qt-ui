#pragma once

#include "decoder.h"
#include "overlaymanager.h"
#include "pyrowaveloader.h"
#include "streaming/bandwidth.h"

#include <libplacebo/log.h>
#include <libplacebo/renderer.h>
#include <libplacebo/vulkan.h>

#include <atomic>
#include <condition_variable>
#include <mutex>
#include <thread>
#include <vector>

/**
 * @brief PyroWave (intra-only Vulkan wavelet codec) decoder and presenter.
 *
 * A single VkDevice is created by libplacebo (pl_vulkan_create, with the same
 * patched libplacebo the HEVC path uses) and wrapped by PyroWave through
 * pyrowave_create_device(), so PyroWave never creates a device of its own.
 * Decoding writes into libplacebo plane textures held for external use and
 * libplacebo renders them straight to the window's swapchain: no copies, no
 * dmabuf/DRM-modifier interop.
 *
 * Threads:
 *  - the common-c decoder thread calls submitDecodeUnit(), which parses the
 *    host's framing, pushes the packets and records a GPU decode into a free slot;
 *  - a render thread waits for the swapchain, then latches the newest decoded
 *    slot (older undisplayed frames are dropped) and presents it.
 */
class PyroWaveVideoDecoder : public IVideoDecoder, public Overlay::IOverlayRenderer
{
public:
    explicit PyroWaveVideoDecoder(bool testOnly);
    ~PyroWaveVideoDecoder() override;

    bool initialize(PDECODER_PARAMETERS params) override;
    bool isHardwareAccelerated() override;
    bool isAlwaysFullScreen() override;
    bool isHdrSupported() override;
    int getDecoderCapabilities() override;
    int getDecoderColorspace() override;
    int getDecoderColorRange() override;
    QSize getDecoderMaxResolution() override;
    int submitDecodeUnit(PDECODE_UNIT du) override;
    void renderFrameOnMainThread() override;
    void setHdrMode(bool enabled) override;
    bool notifyWindowChanged(PWINDOW_STATE_CHANGE_INFO info) override;

    void notifyOverlayUpdated(Overlay::OverlayType type) override;

private:
    // One set of Y/Cb/Cr plane textures. Its state moves
    // Free -> Decoding -> Decoded -> Presenting -> Free; a Decoded slot that is
    // replaced by a newer frame before being presented goes straight back to Free.
    enum class SlotState { Free, Decoding, Decoded, Presenting };

    struct FrameSlot {
        pl_tex planes[3] = {};
        VkImage images[3] = {};
        SlotState state = SlotState::Free;

        // The last GPU operation on these planes, which the next decode must wait for:
        // either libplacebo's hold (render timeline) or the previous decode (decode timeline).
        pl_vulkan_sem lastAccess = {};

        // Decode-complete point, waited on by libplacebo before sampling
        uint64_t decodeValue = 0;

        uint64_t decodeSubmitUs = 0;
        int frameNumber = 0;
    };

    static constexpr int k_SlotCount = 3;

    // What the host was asked to send, which is also how frames are rendered
    struct StreamColorimetry {
        bool hdr;
        pl_color_space color;
        pl_color_repr repr;
    };

    // Incomplete-frame counters. A frame is "partial" when moonlight-common-c salvaged
    // only a prefix of it (DECODE_UNIT::isPartial); packets are PyroWave packets.
    struct PyroWaveStats {
        uint32_t partialShown;
        uint32_t partialRejected;
        uint64_t partialPacketsPushed;
        uint64_t partialPacketsDeclared;
    };

    bool createVulkanDevice(PDECODER_PARAMETERS params);
    bool createPyroWaveDecoder();
    bool createSlots();
    pl_fmt findPlaneFormat(bool renderable);
    bool createSwapchain();
    bool holdPlane(pl_tex plane);
    StreamColorimetry currentColorimetry();
    void checkSequenceHeader(const uint8_t* data, size_t size);

    void renderThreadProc();
    void renderLatestFrame();
    bool buildOverlays(const pl_frame& target, pl_overlay_part* parts,
                       std::vector<pl_overlay>& overlays, std::vector<pl_tex>& texturesToDestroy);
    void logOutputColorspace(const pl_frame& source, const pl_frame& target);

    bool createOverlay(pl_overlay* overlay, SDL_Surface* surface);
    static void overlayUploadComplete(void* opaque);

    void updateStatsWindow();
    void addVideoStats(VIDEO_STATS& src, VIDEO_STATS& dst);
    void stringifyVideoStats(VIDEO_STATS& stats, const PyroWaveStats& pyroStats, char* output, int length);
    void stringifyVideoStatsLite(VIDEO_STATS& stats, char* output, int length);
    int formatHdrStatus(char* output, int length);

    static void pyroQueueLock(void* userdata);
    static void pyroQueueUnlock(void* userdata);

    const bool m_TestOnly;
    const PyroWaveLibrary* m_Lib = nullptr;

    // Stream parameters
    SDL_Window* m_Window = nullptr;
    int m_VideoFormat = 0;
    int m_Width = 0;
    int m_Height = 0;
    int m_FrameRate = 0;
    bool m_Yuv444 = false;
    bool m_TenBit = false;
    bool m_EnableVsync = false;
    std::atomic<bool> m_HostHdrMode { false };

    // libplacebo, owning the one Vulkan device
    pl_log m_Log = nullptr;
    pl_vk_inst m_PlVkInstance = nullptr;
    VkSurfaceKHR m_VkSurface = VK_NULL_HANDLE;
    pl_vulkan m_Vulkan = nullptr;
    pl_swapchain m_Swapchain = nullptr;
    pl_renderer m_Renderer = nullptr;
    VkPresentModeKHR m_PresentMode = VK_PRESENT_MODE_FIFO_KHR;
    PFN_vkDestroySurfaceKHR fn_vkDestroySurfaceKHR = nullptr;

    // PyroWave's view of the same device. Granite keeps pointers into these
    // create infos for the lifetime of the pyrowave_device.
    VkApplicationInfo m_PyroAppInfo = {};
    VkInstanceCreateInfo m_PyroInstanceInfo = {};
    float m_PyroQueuePriority = 1.0f;
    VkDeviceQueueCreateInfo m_PyroQueueCreateInfo = {};
    VkDeviceCreateInfo m_PyroDeviceInfo = {};
    pyrowave_device_create_queue_info m_PyroQueue = {};
    pyrowave_device m_PyroDevice = nullptr;
    pyrowave_decoder m_PyroDecoder = nullptr;
    bool m_FragmentPath = false;

    // Frame slots and the two timelines that order access to them. Each timeline has
    // exactly one signalling thread, so its values are always submitted in order.
    std::mutex m_SlotLock;
    std::condition_variable m_FrameAvailable;
    FrameSlot m_Slots[k_SlotCount];
    int m_LatestDecodedSlot = -1;
    VkSemaphore m_DecodeTimeline = VK_NULL_HANDLE;  // signalled by PyroWave (decoder thread)
    uint64_t m_DecodeTimelineValue = 0;
    VkSemaphore m_RenderTimeline = VK_NULL_HANDLE;  // signalled by libplacebo holds (render thread)
    uint64_t m_RenderTimelineValue = 0;

    std::thread m_RenderThread;
    bool m_Stopping = false;  // protected by m_SlotLock

    // Render thread state
    pl_color_space m_LastSwapchainHint = {};
    pl_color_space m_LastOutputColorspace = {};

    // Decoder thread state
    std::vector<uint8_t> m_FrameBuffer;
    uint32_t m_LastSequenceColorimetry = UINT32_MAX;
    int m_LastPushedFrameNumber = 0;
    bool m_LoggedPushFailure = false;

    // Acceptance policy for incomplete frames (see initialize())
    int m_PristineBands = 2;
    float m_MinBlockRatio = 0.5f;

    // PyroWave-specific counters, windowed like VIDEO_STATS (decoder thread only)
    PyroWaveStats m_ActivePyroStats = {};
    PyroWaveStats m_LastPyroStats = {};
    PyroWaveStats m_GlobalPyroStats = {};
    static void addPyroWaveStats(const PyroWaveStats& src, PyroWaveStats& dst);
    int formatPyroWaveStatus(const PyroWaveStats& stats, char* output, int length);

    // Overlays, following PlVkRenderer's staging model
    SDL_SpinLock m_OverlayLock = 0;
    struct {
        bool hasOverlay;
        pl_overlay overlay;
        bool hasStagingOverlay;
        pl_overlay stagingOverlay;
    } m_Overlays[Overlay::OverlayMax] = {};

    // Statistics. Decode-side fields are owned by the decoder thread; render-side
    // counters are accumulated by the render thread and folded in once per window.
    VIDEO_STATS m_ActiveWndVideoStats = {};
    VIDEO_STATS m_LastWndVideoStats = {};
    VIDEO_STATS m_GlobalVideoStats = {};
    BandwidthTracker m_BwTracker;
    int m_LastFrameNumber = 0;
    std::atomic<uint32_t> m_RenderedFrames { 0 };
    std::atomic<uint32_t> m_DroppedFrames { 0 };
    std::atomic<uint64_t> m_RenderTimeUs { 0 };
    std::atomic<uint64_t> m_QueueDelayUs { 0 };

    // Snapshot of the output state for the overlay, written by the render thread
    std::mutex m_HdrStatusLock;
    pl_color_space m_HdrStatusSource = {};
    pl_color_space m_HdrStatusTarget = {};
    bool m_HdrStatusValid = false;
};
