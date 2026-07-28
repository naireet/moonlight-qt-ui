#pragma once

#include <QSettings>

class NvApp
{
public:
    NvApp() {}
    explicit NvApp(QSettings& settings);

    bool operator==(const NvApp& other) const
    {
        return id == other.id &&
                name == other.name &&
                hdrSupported == other.hdrSupported &&
                isAppCollectorGame == other.isAppCollectorGame &&
                hidden == other.hidden &&
                directLaunch == other.directLaunch &&
                favorite == other.favorite &&
                favoriteOrder == other.favoriteOrder &&
                preferredProfileId == other.preferredProfileId;
    }

    bool operator!=(const NvApp& other) const
    {
        return !operator==(other);
    }

    bool isInitialized()
    {
        // We use isNull() instead of isEmpty() here because we want
        // to detect cases where the name is unassigned, not empty.
        return id != 0 && !name.isNull();
    }

    void
    serialize(QSettings& settings) const;

    int id = 0;
    QString name;
    bool hdrSupported = false;
    bool isAppCollectorGame = false;
    bool hidden = false;
    bool directLaunch = false;
    bool favorite = false;
    int favoriteOrder = -1;

    // Empty string means "use whichever streaming profile is currently the
    // globally-active one" (the existing/default behavior). A non-empty
    // value pins this app to always launch with that specific
    // StreamingProfile's settings, regardless of the global active
    // profile -- see StreamingProfileManager::applyProfileTo() and
    // AppModel::createSessionForApp().
    QString preferredProfileId;
};

Q_DECLARE_METATYPE(NvApp)
