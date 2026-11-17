#pragma once

#include <QMutex>
#include <QObject>
#include <QString>

#include <functional>

class QFileSystemWatcher;
class QTimer;

// Lets the Deckstream plugin control a running stream. Lives in the same data
// directory as the rest of the plugin contract (see backend/gamemode.h):
// - stream-state.json: exists while a stream is running, written by us
// - stream-stats.json: the performance overlay's stats, rewritten every 2 s
//   while a stream is running (even with the overlay hidden)
// - control/<uuid>.json: one command per file, written by the plugin and
//   deleted by us once read. *.tmp files are ignored.
//
// All file I/O happens on a dedicated thread, because the session's main
// thread is busy running the SDL event loop. Commands are handed back to the
// session through a dispatcher callback, which posts an SDL event.
class StreamControl : public QObject
{
    Q_OBJECT

public:
    enum Command {
        CommandNone,
        CommandDisconnect,
        CommandQuit,
        CommandToggleStats,
        CommandSteamOverlay
    };

    struct StreamInfo {
        QString hostUuid;
        QString hostName;
        QString appUuid;
        QString appName;
    };

    // Snapshot of the performance overlay's stats. Negative or empty values
    // are unavailable and are left out of stream-stats.json.
    struct Stats {
        qint64 ts = 0;
        int width = -1;
        int height = -1;
        QString codec;
        double fpsIncoming = -1;
        double fpsRendered = -1;
        double bitrateMbps = -1;
        double networkLatencyMs = -1;
        double networkLatencyVarianceMs = -1;
        double hostLatencyMs = -1;
        double decodeMs = -1;
        double queueMs = -1;
        double renderMs = -1;
        double framesDroppedNetworkPct = -1;
        double framesDroppedJitterPct = -1;
    };

    // Called on the control thread for each accepted command
    using Dispatcher = std::function<void(Command)>;

    // Commands older than this are ignored
    static constexpr qint64 k_MaxCommandAgeSecs = 10;

    // How often stream-stats.json is rewritten
    static constexpr int k_StatsIntervalMs = 2000;

    explicit StreamControl(const QString& dataDir, QObject* parent = nullptr);

    // Process-wide instance running on its own thread, created on first use
    static StreamControl* get();

    // Deletes stream-state.json if the process that wrote it is no longer a
    // running Moonlight (e.g. it crashed). Call once at startup.
    static void removeStaleState(const QString& dataDir);

    // Returns CommandNone if the file is malformed, unknown or too old
    static Command parseCommand(const QByteArray& json, qint64 nowSecs);

    static QByteArray statsToJson(const Stats& stats);

    // These are thread-safe. Between sessionStarted() and sessionEnded(),
    // stream-state.json and stream-stats.json exist and commands are passed
    // to the dispatcher.
    void sessionStarted(const StreamInfo& info, bool statsVisible, Dispatcher dispatcher);
    void setStatsVisible(bool visible);
    // Only stores the snapshot, so it's cheap enough for the decoder thread
    void updateStats(const Stats& stats);
    void sessionEnded();

    QString statePath() const;
    QString statsPath() const;
    QString controlDir() const;

public slots:
    // Starts watching control/. Must run on this object's thread.
    void start();

    // Consumes every pending command file
    void scan();

private slots:
    void writeState();
    void startStatsTimer();
    void writeStats();

private:
    const QString m_DataDir;
    QFileSystemWatcher* m_Watcher;
    QTimer* m_StatsTimer;

    // Guards everything below. Held while writing stream-state.json and
    // stream-stats.json so that sessionEnded() can't race with a write that
    // would recreate them.
    QMutex m_Lock;
    bool m_Active;
    StreamInfo m_Info;
    QString m_Started;
    bool m_StatsVisible;
    Dispatcher m_Dispatcher;
    Stats m_Stats;
    bool m_HasStats;
};
