#include "streamingprofilemanager.h"

#include <QCoreApplication>
#include <QMetaObject>
#include <QReadWriteLock>
#include <QSettings>
#include <QUuid>

namespace {
constexpr auto SER_PROFILE_GROUP = "profiles";
constexpr auto SER_PROFILE_LIST = "list";
constexpr auto SER_ACTIVE_PROFILE_ID = "activeProfileId";

StreamingProfileManager* s_GlobalProfileManager;
Q_GLOBAL_STATIC(QReadWriteLock, s_GlobalProfileManagerLock)

static QString createProfileId()
{
    return QUuid::createUuid().toString(QUuid::WithoutBraces);
}

static void emitPreferenceSignal(StreamingPreferences* prefs, const char* signalName)
{
    QMetaObject::invokeMethod(prefs, signalName, Qt::DirectConnection);
}

static void applyProfileToPreferences(StreamingPreferences* prefs, const StreamingProfile& profile)
{
    StreamingProfile previousValues;
    previousValues.captureFrom(prefs);

    profile.applyTo(prefs);
    prefs->save();

    if (previousValues.width != profile.width ||
            previousValues.height != profile.height ||
            previousValues.fps != profile.fps) {
        emitPreferenceSignal(prefs, "displayModeChanged");
    }
    if (previousValues.bitrateKbps != profile.bitrateKbps) {
        emitPreferenceSignal(prefs, "bitrateChanged");
    }
    if (previousValues.unlockBitrate != profile.unlockBitrate) {
        emitPreferenceSignal(prefs, "unlockBitrateChanged");
    }
    if (previousValues.autoAdjustBitrate != profile.autoAdjustBitrate) {
        emitPreferenceSignal(prefs, "autoAdjustBitrateChanged");
    }
    if (previousValues.enableVsync != profile.enableVsync) {
        emitPreferenceSignal(prefs, "enableVsyncChanged");
    }
    if (previousValues.playAudioOnHost != profile.playAudioOnHost) {
        emitPreferenceSignal(prefs, "playAudioOnHostChanged");
    }
    if (previousValues.multiController != profile.multiController) {
        emitPreferenceSignal(prefs, "multiControllerChanged");
    }
    if (previousValues.quitAppAfter != profile.quitAppAfter) {
        emitPreferenceSignal(prefs, "quitAppAfterChanged");
    }
    if (previousValues.framePacing != profile.framePacing) {
        emitPreferenceSignal(prefs, "framePacingChanged");
    }
    if (previousValues.audioConfig != profile.audioConfig) {
        emitPreferenceSignal(prefs, "audioConfigChanged");
    }
    if (previousValues.videoCodecConfig != profile.videoCodecConfig) {
        emitPreferenceSignal(prefs, "videoCodecConfigChanged");
    }
    if (previousValues.enableHdr != profile.enableHdr) {
        emitPreferenceSignal(prefs, "enableHdrChanged");
    }
    if (previousValues.enableYUV444 != profile.enableYUV444) {
        emitPreferenceSignal(prefs, "enableYUV444Changed");
    }
    if (previousValues.videoDecoderSelection != profile.videoDecoderSelection) {
        emitPreferenceSignal(prefs, "videoDecoderSelectionChanged");
    }
    if (previousValues.windowMode != profile.windowMode) {
        emitPreferenceSignal(prefs, "windowModeChanged");
    }
}
}

StreamingProfileManager::StreamingProfileManager(QQmlEngine* qmlEngine)
    : m_QmlEngine(qmlEngine)
    , m_ApplyingProfile(false)
{
    // Coalesce rapid, high-frequency preference changes (e.g. dragging the
    // bitrate slider) into a single trailing save instead of hitting
    // QSettings/registry on every tick, which was blocking the GUI thread
    // and causing visible slider drag lag.
    m_SaveTimer.setSingleShot(true);
    m_SaveTimer.setInterval(350);
    connect(&m_SaveTimer, &QTimer::timeout, this, &StreamingProfileManager::save);
    connect(qApp, &QCoreApplication::aboutToQuit, this, &StreamingProfileManager::flushPendingSave);

    StreamingPreferences* prefs = StreamingPreferences::get(qmlEngine);

    connect(prefs, &StreamingPreferences::displayModeChanged, this, [this]() { syncActiveProfileFromPreferences(); });
    connect(prefs, &StreamingPreferences::bitrateChanged, this, [this]() { syncActiveProfileFromPreferences(); });
    connect(prefs, &StreamingPreferences::unlockBitrateChanged, this, [this]() { syncActiveProfileFromPreferences(); });
    connect(prefs, &StreamingPreferences::autoAdjustBitrateChanged, this, [this]() { syncActiveProfileFromPreferences(); });
    connect(prefs, &StreamingPreferences::enableVsyncChanged, this, [this]() { syncActiveProfileFromPreferences(); });
    connect(prefs, &StreamingPreferences::playAudioOnHostChanged, this, [this]() { syncActiveProfileFromPreferences(); });
    connect(prefs, &StreamingPreferences::multiControllerChanged, this, [this]() { syncActiveProfileFromPreferences(); });
    connect(prefs, &StreamingPreferences::quitAppAfterChanged, this, [this]() { syncActiveProfileFromPreferences(); });
    connect(prefs, &StreamingPreferences::framePacingChanged, this, [this]() { syncActiveProfileFromPreferences(); });
    connect(prefs, &StreamingPreferences::audioConfigChanged, this, [this]() { syncActiveProfileFromPreferences(); });
    connect(prefs, &StreamingPreferences::videoCodecConfigChanged, this, [this]() { syncActiveProfileFromPreferences(); });
    connect(prefs, &StreamingPreferences::enableHdrChanged, this, [this]() { syncActiveProfileFromPreferences(); });
    connect(prefs, &StreamingPreferences::enableYUV444Changed, this, [this]() { syncActiveProfileFromPreferences(); });
    connect(prefs, &StreamingPreferences::videoDecoderSelectionChanged, this, [this]() { syncActiveProfileFromPreferences(); });
    connect(prefs, &StreamingPreferences::windowModeChanged, this, [this]() { syncActiveProfileFromPreferences(); });

    load();
    ensureDefaultProfileBootstrap();
}

StreamingProfileManager* StreamingProfileManager::get(QQmlEngine* qmlEngine)
{
    {
        QReadLocker readGuard(s_GlobalProfileManagerLock);

        if (s_GlobalProfileManager && (s_GlobalProfileManager->m_QmlEngine || !qmlEngine)) {
            Q_ASSERT(!qmlEngine || s_GlobalProfileManager->m_QmlEngine == qmlEngine);
            return s_GlobalProfileManager;
        }
    }

    {
        QWriteLocker writeGuard(s_GlobalProfileManagerLock);

        if (s_GlobalProfileManager) {
            if (!s_GlobalProfileManager->m_QmlEngine) {
                s_GlobalProfileManager->m_QmlEngine = qmlEngine;
            }
            else {
                Q_ASSERT(!qmlEngine || s_GlobalProfileManager->m_QmlEngine == qmlEngine);
            }
        }
        else {
            s_GlobalProfileManager = new StreamingProfileManager(qmlEngine);
        }

        return s_GlobalProfileManager;
    }
}

QStringList StreamingProfileManager::profileNames() const
{
    QStringList names;
    names.reserve(m_Profiles.count());
    for (const StreamingProfile& profile : m_Profiles) {
        names.append(profile.name);
    }

    return names;
}

QStringList StreamingProfileManager::profileIds() const
{
    QStringList ids;
    ids.reserve(m_Profiles.count());
    for (const StreamingProfile& profile : m_Profiles) {
        ids.append(profile.id);
    }

    return ids;
}

QString StreamingProfileManager::activeProfileId() const
{
    return m_ActiveProfileId;
}

QString StreamingProfileManager::activeProfileName() const
{
    int profileIndex = findProfileIndex(m_ActiveProfileId);
    if (profileIndex < 0) {
        return QString();
    }

    return m_Profiles.at(profileIndex).name;
}

void StreamingProfileManager::setActiveProfile(const QString& profileId)
{
    int profileIndex = findProfileIndex(profileId);
    if (profileIndex < 0) {
        return;
    }

    m_ActiveProfileId = profileId;

    m_ApplyingProfile = true;
    applyProfileToPreferences(StreamingPreferences::get(), m_Profiles.at(profileIndex));
    m_ApplyingProfile = false;

    save();

    emit activeProfileChanged();
}

void StreamingProfileManager::createProfileFromCurrent(const QString& name)
{
    const QString trimmedName = name.trimmed();
    if (trimmedName.isEmpty() || !isProfileNameAvailable(trimmedName)) {
        return;
    }

    StreamingProfile profile;
    profile.captureFrom(StreamingPreferences::get());
    profile.id = createProfileId();
    profile.name = trimmedName;

    const bool wasEmpty = m_Profiles.isEmpty();
    m_Profiles.append(profile);

    if (wasEmpty) {
        m_ActiveProfileId = profile.id;
        emit activeProfileChanged();
    }

    save();
    emit profileListChanged();
}

void StreamingProfileManager::duplicateProfile(const QString& sourceProfileId, const QString& newName)
{
    const QString trimmedName = newName.trimmed();
    const int sourceIndex = findProfileIndex(sourceProfileId);
    if (sourceIndex < 0 || trimmedName.isEmpty() || !isProfileNameAvailable(trimmedName)) {
        return;
    }

    StreamingProfile duplicate = m_Profiles.at(sourceIndex);
    duplicate.id = createProfileId();
    duplicate.name = trimmedName;
    m_Profiles.append(duplicate);

    save();
    emit profileListChanged();
}

void StreamingProfileManager::renameProfile(const QString& profileId, const QString& newName)
{
    const QString trimmedName = newName.trimmed();
    const int profileIndex = findProfileIndex(profileId);
    if (profileIndex < 0 || trimmedName.isEmpty() || !isProfileNameAvailable(trimmedName, profileId)) {
        return;
    }

    m_Profiles[profileIndex].name = trimmedName;
    save();

    emit profileListChanged();
    if (profileId == m_ActiveProfileId) {
        emit activeProfileChanged();
    }
}

bool StreamingProfileManager::deleteProfile(const QString& profileId)
{
    const int profileIndex = findProfileIndex(profileId);
    if (profileIndex < 0 || m_Profiles.count() <= 1) {
        return false;
    }

    const bool deletingActiveProfile = profileId == m_ActiveProfileId;
    m_Profiles.removeAt(profileIndex);

    if (deletingActiveProfile) {
        m_ActiveProfileId = m_Profiles.constFirst().id;

        m_ApplyingProfile = true;
        applyProfileToPreferences(StreamingPreferences::get(), m_Profiles.constFirst());
        m_ApplyingProfile = false;
    }

    save();

    emit profileListChanged();
    if (deletingActiveProfile) {
        emit activeProfileChanged();
    }

    return true;
}

void StreamingProfileManager::resetProfileToDefaults(const QString& profileId)
{
    const int profileIndex = findProfileIndex(profileId);
    if (profileIndex < 0) {
        return;
    }

    StreamingProfile resetProfile;
    resetProfile.id = m_Profiles.at(profileIndex).id;
    resetProfile.name = m_Profiles.at(profileIndex).name;
    m_Profiles[profileIndex] = resetProfile;

    if (profileId == m_ActiveProfileId) {
        m_ApplyingProfile = true;
        applyProfileToPreferences(StreamingPreferences::get(), m_Profiles.at(profileIndex));
        m_ApplyingProfile = false;
    }

    save();
    emit profileListChanged();
    if (profileId == m_ActiveProfileId) {
        emit activeProfileChanged();
    }
}

void StreamingProfileManager::load()
{
    QSettings settings;

    settings.beginGroup(SER_PROFILE_GROUP);

    m_Profiles.clear();
    m_ActiveProfileId = settings.value(SER_ACTIVE_PROFILE_ID).toString();

    const int profileCount = settings.beginReadArray(SER_PROFILE_LIST);
    m_Profiles.reserve(profileCount);
    for (int i = 0; i < profileCount; i++) {
        settings.setArrayIndex(i);
        m_Profiles.append(StreamingProfile(settings));
    }
    settings.endArray();
    settings.endGroup();
}

void StreamingProfileManager::save()
{
    if (m_SaveTimer.isActive()) {
        m_SaveTimer.stop();
    }

    QSettings settings;

    settings.beginGroup(SER_PROFILE_GROUP);
    settings.setValue(SER_ACTIVE_PROFILE_ID, m_ActiveProfileId);
    settings.remove(SER_PROFILE_LIST);
    settings.beginWriteArray(SER_PROFILE_LIST);
    for (int i = 0; i < m_Profiles.count(); i++) {
        settings.setArrayIndex(i);
        m_Profiles.at(i).serialize(settings);
    }
    settings.endArray();
    settings.endGroup();
}

void StreamingProfileManager::scheduleSave()
{
    // Restarts the timer on every call, coalescing rapid successive changes
    // (e.g. dragging a slider) into a single trailing save.
    m_SaveTimer.start();
}

void StreamingProfileManager::flushPendingSave()
{
    if (m_SaveTimer.isActive()) {
        save();
    }
}

void StreamingProfileManager::ensureDefaultProfileBootstrap()
{
    if (m_Profiles.isEmpty()) {
        StreamingProfile defaultProfile;
        defaultProfile.captureFrom(StreamingPreferences::get());
        defaultProfile.id = createProfileId();
        defaultProfile.name = tr("Default");
        m_Profiles.append(defaultProfile);
        m_ActiveProfileId = defaultProfile.id;
        save();
        return;
    }

    if (findProfileIndex(m_ActiveProfileId) < 0) {
        m_ActiveProfileId = m_Profiles.constFirst().id;

        m_ApplyingProfile = true;
        applyProfileToPreferences(StreamingPreferences::get(), m_Profiles.constFirst());
        m_ApplyingProfile = false;

        save();
    }
}

void StreamingProfileManager::syncActiveProfileFromPreferences()
{
    if (m_ApplyingProfile) {
        return;
    }

    const int profileIndex = findProfileIndex(m_ActiveProfileId);
    if (profileIndex < 0) {
        return;
    }

    StreamingProfile updatedProfile = m_Profiles.at(profileIndex);
    updatedProfile.captureFrom(StreamingPreferences::get());

    if (updatedProfile != m_Profiles.at(profileIndex)) {
        m_Profiles[profileIndex] = updatedProfile;
        // Debounced save -- this handler fires on every high-frequency
        // preference change (e.g. every tick while dragging the bitrate
        // slider), so writing to QSettings/registry synchronously here
        // was blocking the GUI thread and causing visible slider lag.
        scheduleSave();
    }
}

int StreamingProfileManager::findProfileIndex(const QString& profileId) const
{
    for (int i = 0; i < m_Profiles.count(); i++) {
        if (m_Profiles.at(i).id == profileId) {
            return i;
        }
    }

    return -1;
}

bool StreamingProfileManager::isProfileNameAvailable(const QString& name, const QString& excludedProfileId) const
{
    for (const StreamingProfile& profile : m_Profiles) {
        if (profile.id != excludedProfileId &&
                profile.name.compare(name, Qt::CaseInsensitive) == 0) {
            return false;
        }
    }

    return true;
}
