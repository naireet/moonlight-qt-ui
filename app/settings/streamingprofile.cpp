#include "streamingprofile.h"

#include "utils.h"

namespace {
constexpr auto SER_PROFILE_ID = "id";
constexpr auto SER_PROFILE_NAME = "name";
constexpr auto SER_WIDTH = "width";
constexpr auto SER_HEIGHT = "height";
constexpr auto SER_FPS = "fps";
constexpr auto SER_BITRATE = "bitrate";
constexpr auto SER_UNLOCK_BITRATE = "unlockbitrate";
constexpr auto SER_AUTOADJUSTBITRATE = "autoadjustbitrate";
constexpr auto SER_VSYNC = "vsync";
constexpr auto SER_HOSTAUDIO = "hostaudio";
constexpr auto SER_MULTICONT = "multicontroller";
constexpr auto SER_QUITAPPAFTER = "quitAppAfter";
constexpr auto SER_FRAMEPACING = "framepacing";
constexpr auto SER_AUDIOCFG = "audiocfg";
constexpr auto SER_VIDEOCFG = "videocfg";
constexpr auto SER_HDR = "hdr";
constexpr auto SER_YUV444 = "yuv444";
constexpr auto SER_VIDEODEC = "videodec";
constexpr auto SER_WINDOWMODE = "windowmode";

static StreamingPreferences::WindowMode getDefaultWindowMode()
{
#ifdef Q_OS_DARWIN
    return StreamingPreferences::WindowMode::WM_FULLSCREEN_DESKTOP;
#else
    if (WMUtils::isRunningWayland() && !WMUtils::isGpuSlow()) {
        return StreamingPreferences::WindowMode::WM_FULLSCREEN_DESKTOP;
    }

    return StreamingPreferences::WindowMode::WM_FULLSCREEN;
#endif
}
}

StreamingProfile::StreamingProfile()
    : width(1280)
    , height(720)
    , fps(60)
    , bitrateKbps(StreamingPreferences::getDefaultBitrate(width, height, fps, false))
    , unlockBitrate(false)
    , autoAdjustBitrate(true)
    , enableVsync(true)
    , playAudioOnHost(false)
    , multiController(true)
    , quitAppAfter(false)
    , framePacing(false)
    , audioConfig(StreamingPreferences::AudioConfig::AC_STEREO)
    , videoCodecConfig(StreamingPreferences::VideoCodecConfig::VCC_AUTO)
    , enableHdr(false)
    , enableYUV444(false)
    , videoDecoderSelection(StreamingPreferences::VideoDecoderSelection::VDS_AUTO)
    , windowMode(getDefaultWindowMode())
{
}

StreamingProfile::StreamingProfile(QSettings& settings)
    : StreamingProfile()
{
    id = settings.value(SER_PROFILE_ID).toString();
    name = settings.value(SER_PROFILE_NAME).toString();
    width = settings.value(SER_WIDTH, width).toInt();
    height = settings.value(SER_HEIGHT, height).toInt();
    fps = settings.value(SER_FPS, fps).toInt();
    unlockBitrate = settings.value(SER_UNLOCK_BITRATE, unlockBitrate).toBool();
    autoAdjustBitrate = settings.value(SER_AUTOADJUSTBITRATE, autoAdjustBitrate).toBool();
    enableVsync = settings.value(SER_VSYNC, enableVsync).toBool();
    playAudioOnHost = settings.value(SER_HOSTAUDIO, playAudioOnHost).toBool();
    multiController = settings.value(SER_MULTICONT, multiController).toBool();
    quitAppAfter = settings.value(SER_QUITAPPAFTER, quitAppAfter).toBool();
    framePacing = settings.value(SER_FRAMEPACING, framePacing).toBool();
    audioConfig = static_cast<StreamingPreferences::AudioConfig>(
                settings.value(SER_AUDIOCFG, static_cast<int>(audioConfig)).toInt());
    videoCodecConfig = static_cast<StreamingPreferences::VideoCodecConfig>(
                settings.value(SER_VIDEOCFG, static_cast<int>(videoCodecConfig)).toInt());
    enableHdr = settings.value(SER_HDR, enableHdr).toBool();
    enableYUV444 = settings.value(SER_YUV444, enableYUV444).toBool();
    bitrateKbps = settings.value(SER_BITRATE,
                                 StreamingPreferences::getDefaultBitrate(width, height, fps, enableYUV444)).toInt();
    videoDecoderSelection = static_cast<StreamingPreferences::VideoDecoderSelection>(
                settings.value(SER_VIDEODEC, static_cast<int>(videoDecoderSelection)).toInt());
    windowMode = static_cast<StreamingPreferences::WindowMode>(
                settings.value(SER_WINDOWMODE, static_cast<int>(windowMode)).toInt());

    if (videoCodecConfig == StreamingPreferences::VideoCodecConfig::VCC_FORCE_HEVC_HDR_DEPRECATED) {
        videoCodecConfig = StreamingPreferences::VideoCodecConfig::VCC_AUTO;
        enableHdr = true;
    }
}

bool StreamingProfile::operator==(const StreamingProfile& other) const
{
    return id == other.id &&
            name == other.name &&
            width == other.width &&
            height == other.height &&
            fps == other.fps &&
            bitrateKbps == other.bitrateKbps &&
            unlockBitrate == other.unlockBitrate &&
            autoAdjustBitrate == other.autoAdjustBitrate &&
            enableVsync == other.enableVsync &&
            playAudioOnHost == other.playAudioOnHost &&
            multiController == other.multiController &&
            quitAppAfter == other.quitAppAfter &&
            framePacing == other.framePacing &&
            audioConfig == other.audioConfig &&
            videoCodecConfig == other.videoCodecConfig &&
            enableHdr == other.enableHdr &&
            enableYUV444 == other.enableYUV444 &&
            videoDecoderSelection == other.videoDecoderSelection &&
            windowMode == other.windowMode;
}

bool StreamingProfile::operator!=(const StreamingProfile& other) const
{
    return !operator==(other);
}

void StreamingProfile::serialize(QSettings& settings) const
{
    settings.setValue(SER_PROFILE_ID, id);
    settings.setValue(SER_PROFILE_NAME, name);
    settings.setValue(SER_WIDTH, width);
    settings.setValue(SER_HEIGHT, height);
    settings.setValue(SER_FPS, fps);
    settings.setValue(SER_BITRATE, bitrateKbps);
    settings.setValue(SER_UNLOCK_BITRATE, unlockBitrate);
    settings.setValue(SER_AUTOADJUSTBITRATE, autoAdjustBitrate);
    settings.setValue(SER_VSYNC, enableVsync);
    settings.setValue(SER_HOSTAUDIO, playAudioOnHost);
    settings.setValue(SER_MULTICONT, multiController);
    settings.setValue(SER_QUITAPPAFTER, quitAppAfter);
    settings.setValue(SER_FRAMEPACING, framePacing);
    settings.setValue(SER_AUDIOCFG, static_cast<int>(audioConfig));
    settings.setValue(SER_VIDEOCFG, static_cast<int>(videoCodecConfig));
    settings.setValue(SER_HDR, enableHdr);
    settings.setValue(SER_YUV444, enableYUV444);
    settings.setValue(SER_VIDEODEC, static_cast<int>(videoDecoderSelection));
    settings.setValue(SER_WINDOWMODE, static_cast<int>(windowMode));
}

void StreamingProfile::applyTo(StreamingPreferences* prefs) const
{
    prefs->width = width;
    prefs->height = height;
    prefs->fps = fps;
    prefs->bitrateKbps = bitrateKbps;
    prefs->unlockBitrate = unlockBitrate;
    prefs->autoAdjustBitrate = autoAdjustBitrate;
    prefs->enableVsync = enableVsync;
    prefs->playAudioOnHost = playAudioOnHost;
    prefs->multiController = multiController;
    prefs->quitAppAfter = quitAppAfter;
    prefs->framePacing = framePacing;
    prefs->audioConfig = audioConfig;
    prefs->videoCodecConfig = videoCodecConfig;
    prefs->enableHdr = enableHdr;
    prefs->enableYUV444 = enableYUV444;
    prefs->videoDecoderSelection = videoDecoderSelection;
    prefs->windowMode = windowMode;
}

void StreamingProfile::captureFrom(const StreamingPreferences* prefs)
{
    width = prefs->width;
    height = prefs->height;
    fps = prefs->fps;
    bitrateKbps = prefs->bitrateKbps;
    unlockBitrate = prefs->unlockBitrate;
    autoAdjustBitrate = prefs->autoAdjustBitrate;
    enableVsync = prefs->enableVsync;
    playAudioOnHost = prefs->playAudioOnHost;
    multiController = prefs->multiController;
    quitAppAfter = prefs->quitAppAfter;
    framePacing = prefs->framePacing;
    audioConfig = prefs->audioConfig;
    videoCodecConfig = prefs->videoCodecConfig;
    enableHdr = prefs->enableHdr;
    enableYUV444 = prefs->enableYUV444;
    videoDecoderSelection = prefs->videoDecoderSelection;
    windowMode = prefs->windowMode;
}
