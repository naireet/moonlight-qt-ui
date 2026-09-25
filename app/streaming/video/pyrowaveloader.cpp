#include "pyrowaveloader.h"

#include "SDL_compat.h"

#include <QByteArray>
#include <QtGlobal>

#include <dlfcn.h>

// The soname carries the API major version. Pre-1.0 the ABI is not stable, so
// the minor version must match the header we were built against as well.
static_assert(PYROWAVE_API_VERSION_MAJOR == 0, "Update the PyroWave soname below");
#define PYROWAVE_DEFAULT_LIBRARY "libpyrowave-shared.so.0"

const PyroWaveLibrary* PyroWaveLibrary::get()
{
    // Deliberately leaked: Granite keeps global state, so the library is never unloaded
    static const PyroWaveLibrary* s_Library = []() -> const PyroWaveLibrary* {
        auto library = new PyroWaveLibrary();
        if (!library->load()) {
            delete library;
            return nullptr;
        }
        return library;
    }();

    return s_Library;
}

bool PyroWaveLibrary::load()
{
    // PYROWAVE_LIBRARY allows testing a locally built library without repackaging
    QByteArray overridePath = qgetenv("PYROWAVE_LIBRARY");
    const char* libraryName = overridePath.isEmpty() ? PYROWAVE_DEFAULT_LIBRARY : overridePath.constData();

    m_Handle = dlopen(libraryName, RTLD_NOW | RTLD_LOCAL);
    if (m_Handle == nullptr) {
        SDL_LogWarn(SDL_LOG_CATEGORY_APPLICATION,
                    "PyroWave: unable to load %s: %s",
                    libraryName, dlerror());
        return false;
    }

#define PYROWAVE_BIND_FUNCTION(fn) \
    fn = reinterpret_cast<decltype(fn)>(dlsym(m_Handle, #fn)); \
    if (fn == nullptr) { \
        SDL_LogWarn(SDL_LOG_CATEGORY_APPLICATION, \
                    "PyroWave: %s is missing from %s", #fn, libraryName); \
        dlclose(m_Handle); \
        m_Handle = nullptr; \
        return false; \
    }
    PYROWAVE_FUNCTIONS(PYROWAVE_BIND_FUNCTION)
#undef PYROWAVE_BIND_FUNCTION

    uint32_t major = 0, minor = 0, patch = 0;
    pyrowave_get_api_version(&major, &minor, &patch);
    if (major != PYROWAVE_API_VERSION_MAJOR || minor != PYROWAVE_API_VERSION_MINOR) {
        SDL_LogWarn(SDL_LOG_CATEGORY_APPLICATION,
                    "PyroWave: %s has API version %u.%u.%u, but %d.%d.x is required",
                    libraryName, major, minor, patch,
                    PYROWAVE_API_VERSION_MAJOR, PYROWAVE_API_VERSION_MINOR);
        dlclose(m_Handle);
        m_Handle = nullptr;
        return false;
    }

    SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION,
                "PyroWave: loaded %s (API version %u.%u.%u)",
                libraryName, major, minor, patch);
    return true;
}
