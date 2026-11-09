#pragma once

#include "session.h"
#include "backend/nvcomputer.h"

#include <QTimer>
#include <QUrl>

// Drives the "Connection lost - reconnecting" screen after a stream drops
// unexpectedly: polls the host's serverinfo every couple of seconds (sending
// Wake-on-LAN once if it's unreachable) until it is back with the same app
// still running, then hands out a fresh Session to resume it.
class StreamReconnector : public QObject
{
    Q_OBJECT

public:
    // If preferences is null, the global preferences are used, unless
    // perAppProfile is set, in which case the app's pinned profile is
    // re-applied to a standalone copy for each new session (mirroring
    // AppModel::createSessionForApp()).
    StreamReconnector(NvComputer* computer, const NvApp& app,
                      StreamingPreferences* preferences, bool perAppProfile);

    Q_INVOKABLE QString hostName() const;

    // Cached box art for the app as a URL, or empty if not cached
    Q_INVOKABLE QUrl boxArtUrl() const;

    Q_INVOKABLE void start();

    Q_INVOKABLE void stop();

    // Best-effort quit of the app on the host. Emits quitFinished().
    Q_INVOKABLE void quitHostApp();

    Q_INVOKABLE Session* createSession();

signals:
    // The host is reachable and still running our app
    void hostReady();

    // The host is reachable but our app is no longer running on it
    void appNotRunning();

    // Empty error string on success
    void quitFinished(QString error);

private:
    void poll();

    // gameId < 0 means the host could not be reached
    void handlePollResult(int gameId);

    NvComputer* m_Computer;
    NvApp m_App;
    StreamingPreferences* m_Preferences;
    bool m_PerAppProfile;
    QTimer m_PollTimer;
    bool m_PollInFlight;
    bool m_WolSent;
};
