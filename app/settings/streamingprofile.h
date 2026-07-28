#pragma once

#include "settings/streamingpreferences.h"

#include <QSettings>
#include <QString>

class StreamingProfile
{
public:
    StreamingProfile();
    explicit StreamingProfile(QSettings& settings);

    bool operator==(const StreamingProfile& other) const;
    bool operator!=(const StreamingProfile& other) const;

    void serialize(QSettings& settings) const;
    void applyTo(StreamingPreferences* prefs) const;
    void captureFrom(const StreamingPreferences* prefs);

    QString id;
    QString name;
    int width;
    int height;
    int fps;
    int bitrateKbps;
    bool unlockBitrate;
    bool autoAdjustBitrate;
    bool enableVsync;
    bool playAudioOnHost;
    bool multiController;
    bool quitAppAfter;
    bool framePacing;
    StreamingPreferences::AudioConfig audioConfig;
    StreamingPreferences::VideoCodecConfig videoCodecConfig;
    bool enableHdr;
    bool enableYUV444;
    StreamingPreferences::VideoDecoderSelection videoDecoderSelection;
    StreamingPreferences::WindowMode windowMode;
};
