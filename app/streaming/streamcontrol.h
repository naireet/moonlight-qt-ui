#pragma once

#include <QMutex>
#include <QObject>
#include <QString>

#include <functional>

class QFileSystemWatcher;

// Lets the Deckstream plugin control a running stream. Lives in the same data
// directory as the rest of the plugin contract (see backend/gamemode.h):
// - stream-state.json: exists while a stream is running, written by us
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
        CommandToggleStats
    };

    struct StreamInfo {
        QString hostUuid;
        QString hostName;
        QString appUuid;
        QString appName;
    };

    // Called on the control thread for each accepted command
    using Dispatcher = std::function<void(Command)>;

    // Commands older than this are ignored
    static constexpr qint64 k_MaxCommandAgeSecs = 10;

    explicit StreamControl(const QString& dataDir, QObject* parent = nullptr);

    // Process-wide instance running on its own thread, created on first use
    static StreamControl* get();

    // Deletes stream-state.json if the process that wrote it is no longer a
    // running Moonlight (e.g. it crashed). Call once at startup.
    static void removeStaleState(const QString& dataDir);

    // Returns CommandNone if the file is malformed, unknown or too old
    static Command parseCommand(const QByteArray& json, qint64 nowSecs);

    // These are thread-safe. Between sessionStarted() and sessionEnded(),
    // stream-state.json exists and commands are passed to the dispatcher.
    void sessionStarted(const StreamInfo& info, bool statsVisible, Dispatcher dispatcher);
    void setStatsVisible(bool visible);
    void sessionEnded();

    QString statePath() const;
    QString controlDir() const;

public slots:
    // Starts watching control/. Must run on this object's thread.
    void start();

    // Consumes every pending command file
    void scan();

private slots:
    void writeState();

private:
    const QString m_DataDir;
    QFileSystemWatcher* m_Watcher;

    // Guards everything below. Held while writing stream-state.json so that
    // sessionEnded() can't race with a write that would recreate it.
    QMutex m_Lock;
    bool m_Active;
    StreamInfo m_Info;
    QString m_Started;
    bool m_StatsVisible;
    Dispatcher m_Dispatcher;
};
