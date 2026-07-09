#pragma once

#include "settings/streamingprofile.h"

#include <QObject>
#include <QStringList>
#include <QTimer>
#include <QVector>

class QQmlEngine;

class StreamingProfileManager : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString activeProfileId READ activeProfileId NOTIFY activeProfileChanged)
    Q_PROPERTY(QString activeProfileName READ activeProfileName NOTIFY activeProfileChanged)

public:
    static StreamingProfileManager* get(QQmlEngine* qmlEngine = nullptr);

    Q_INVOKABLE QStringList profileNames() const;
    Q_INVOKABLE QStringList profileIds() const;
    Q_INVOKABLE QString activeProfileId() const;
    Q_INVOKABLE QString activeProfileName() const;
    Q_INVOKABLE void setActiveProfile(const QString& profileId);
    Q_INVOKABLE void createProfileFromCurrent(const QString& name);
    Q_INVOKABLE void duplicateProfile(const QString& sourceProfileId, const QString& newName);
    Q_INVOKABLE void renameProfile(const QString& profileId, const QString& newName);
    Q_INVOKABLE bool deleteProfile(const QString& profileId);
    Q_INVOKABLE void resetProfileToDefaults(const QString& profileId);

    // Applies the given profile's settings directly onto an arbitrary
    // StreamingPreferences instance (e.g. a temporary per-launch object),
    // WITHOUT calling save() or emitting any of the preference change
    // signals that setActiveProfile()/applyProfileToPreferences() do --
    // this must never disturb the actual globally-active profile or its
    // persisted state. Used to let a specific app launch with a pinned
    // profile's settings while leaving "Active Profile" in Settings
    // completely unchanged. Returns false if profileId doesn't match any
    // known profile (e.g. it was since deleted), leaving prefs untouched.
    bool applyProfileTo(const QString& profileId, StreamingPreferences* prefs) const;

signals:
    void activeProfileChanged();
    void profileListChanged();

private:
    explicit StreamingProfileManager(QQmlEngine* qmlEngine);

    void load();
    void save();
    void scheduleSave();
    void flushPendingSave();
    void ensureDefaultProfileBootstrap();
    void syncActiveProfileFromPreferences();
    int findProfileIndex(const QString& profileId) const;
    bool isProfileNameAvailable(const QString& name, const QString& excludedProfileId = QString()) const;

    QVector<StreamingProfile> m_Profiles;
    QString m_ActiveProfileId;
    QQmlEngine* m_QmlEngine;
    bool m_ApplyingProfile;
    QTimer m_SaveTimer;
};

