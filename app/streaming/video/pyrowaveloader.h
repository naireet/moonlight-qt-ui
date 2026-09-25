#pragma once

#include <vulkan/vulkan.h>
#include <pyrowave.h>

// Entry points of the PyroWave C API that the client uses.
#define PYROWAVE_FUNCTIONS(X) \
    X(pyrowave_get_api_version) \
    X(pyrowave_create_device) \
    X(pyrowave_device_destroy) \
    X(pyrowave_device_set_queue_type) \
    X(pyrowave_device_report_performance_stats) \
    X(pyrowave_decoder_device_prefers_fragment_path) \
    X(pyrowave_decoder_create) \
    X(pyrowave_decoder_destroy) \
    X(pyrowave_decoder_clear) \
    X(pyrowave_decoder_push_packet) \
    X(pyrowave_decoder_decode_is_ready_with_sideband) \
    X(pyrowave_decoder_decode_gpu_buffer)

/**
 * @brief Runtime binding to libpyrowave-shared.
 *
 * The library is only loaded when a PyroWave stream is actually requested, so a
 * missing, broken or incompatible library can never affect startup or the other
 * codecs. Members are named after the C functions they point to.
 */
class PyroWaveLibrary
{
public:
    /**
     * @brief Loads the library on first use.
     * @return The bound library, or nullptr (after logging why) if it is missing,
     *         lacks an entry point or was built for a different API version.
     *         The result is cached; the library is never unloaded.
     */
    static const PyroWaveLibrary* get();

#define PYROWAVE_DECLARE_FUNCTION(name) decltype(&::name) name = nullptr;
    PYROWAVE_FUNCTIONS(PYROWAVE_DECLARE_FUNCTION)
#undef PYROWAVE_DECLARE_FUNCTION

private:
    PyroWaveLibrary() = default;
    bool load();

    void* m_Handle = nullptr;
};
