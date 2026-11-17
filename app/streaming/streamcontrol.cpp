#include "streamcontrol.h"
#include "backend/gamemode.h"

#include <QCoreApplication>
#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileSystemWatcher>
#include <QJsonDocument>
#include <QJsonObject>
#include <QSaveFile>
#include <QThread>
#include <QTimer>
#include <QtDebug>

namespace {

#ifdef Q_OS_LINUX
QByteArray readComm(const QString& pid)
{
    QFile file("/proc/" + pid + "/comm");
    if (!file.open(QIODevice::ReadOnly)) {
        return QByteArray();
    }
    return file.readAll().trimmed();
}
#endif

// True if pid is a running process with the same executable name as us, so a
// recycled pid belonging to something else doesn't count
bool isMoonlightProcess(qint64 pid)
{
#ifdef Q_OS_LINUX
    if (pid <= 0) {
        return false;
    }
    QByteArray comm = readComm(QString::number(pid));
    return !comm.isEmpty() && comm == readComm("self");
#else
    Q_UNUSED(pid);
    return false;
#endif
}

}

StreamControl::StreamControl(const QString& dataDir, QObject* parent)
    : QObject(parent),
      m_DataDir(dataDir),
      m_Watcher(nullptr),
      m_StatsTimer(nullptr),
      m_Active(false),
      m_StatsVisible(false),
      m_HasStats(false)
{
}

StreamControl* StreamControl::get()
{
    static StreamControl* s_Instance = [] {
        auto thread = new QThread();
        thread->setObjectName("StreamControl");

        auto control = new StreamControl(GameMode::dataDir());
        control->moveToThread(thread);
        connect(thread, &QThread::started, control, &StreamControl::start);
        connect(qApp, &QCoreApplication::aboutToQuit, thread, [thread] {
            thread->quit();
            thread->wait();
        });

        thread->start();
        return control;
    }();
    return s_Instance;
}

QString StreamControl::statePath() const
{
    return m_DataDir + "/stream-state.json";
}

QString StreamControl::statsPath() const
{
    return m_DataDir + "/stream-stats.json";
}

QString StreamControl::controlDir() const
{
    return m_DataDir + "/control";
}

void StreamControl::removeStaleState(const QString& dataDir)
{
    QString path = dataDir + "/stream-state.json";
    QString statsPath = dataDir + "/stream-stats.json";
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly)) {
        QFile::remove(statsPath);
        return;
    }
    QJsonObject state = QJsonDocument::fromJson(file.readAll()).object();
    file.close();

    qint64 pid = (qint64)state.value("pid").toDouble();
    if (pid == QCoreApplication::applicationPid() || !isMoonlightProcess(pid)) {
        qInfo() << "Removing stale" << path << "from pid" << pid;
        QFile::remove(path);
        QFile::remove(statsPath);
    }
}

StreamControl::Command StreamControl::parseCommand(const QByteArray& json, qint64 nowSecs)
{
    QJsonObject object = QJsonDocument::fromJson(json).object();

    QJsonValue ts = object.value("ts");
    if (!ts.isDouble()) {
        return CommandNone;
    }
    qint64 age = nowSecs - (qint64)ts.toDouble();
    if (age > k_MaxCommandAgeSecs || age < -k_MaxCommandAgeSecs) {
        return CommandNone;
    }

    QString command = object.value("command").toString();
    if (command == "disconnect") {
        return CommandDisconnect;
    }
    else if (command == "quit") {
        return CommandQuit;
    }
    else if (command == "toggle-stats") {
        return CommandToggleStats;
    }
    else if (command == "steam-overlay") {
        return CommandSteamOverlay;
    }
    return CommandNone;
}

QByteArray StreamControl::statsToJson(const Stats& stats)
{
    QJsonObject object;
    object["version"] = 1;
    object["ts"] = (double)stats.ts;

    if (stats.width > 0 && stats.height > 0) {
        object["width"] = stats.width;
        object["height"] = stats.height;
    }
    if (!stats.codec.isEmpty()) {
        object["codec"] = stats.codec;
    }

    // Rounded to 2 decimals to keep the file readable
    auto addValue = [&object](const char* key, double value) {
        if (value >= 0) {
            object[key] = qRound64(value * 100) / 100.0;
        }
    };
    addValue("fpsIncoming", stats.fpsIncoming);
    addValue("fpsRendered", stats.fpsRendered);
    addValue("bitrateMbps", stats.bitrateMbps);
    addValue("networkLatencyMs", stats.networkLatencyMs);
    addValue("networkLatencyVarianceMs", stats.networkLatencyVarianceMs);
    addValue("hostLatencyMs", stats.hostLatencyMs);
    addValue("decodeMs", stats.decodeMs);
    addValue("queueMs", stats.queueMs);
    addValue("renderMs", stats.renderMs);
    addValue("framesDroppedNetworkPct", stats.framesDroppedNetworkPct);
    addValue("framesDroppedJitterPct", stats.framesDroppedJitterPct);

    return QJsonDocument(object).toJson();
}

void StreamControl::start()
{
    if (!QDir().mkpath(controlDir())) {
        qWarning() << "Failed to create" << controlDir();
        return;
    }

    m_Watcher = new QFileSystemWatcher(this);
    connect(m_Watcher, &QFileSystemWatcher::directoryChanged, this, &StreamControl::scan);
    if (!m_Watcher->addPath(controlDir())) {
        qWarning() << "Failed to watch" << controlDir();
    }

    scan();
}

void StreamControl::scan()
{
    QDir dir(controlDir());
    const QFileInfoList files = dir.entryInfoList(QStringList("*.json"), QDir::Files,
                                                  QDir::Time | QDir::Reversed);
    for (const QFileInfo& info : files) {
        QFile file(info.absoluteFilePath());
        if (!file.open(QIODevice::ReadOnly)) {
            continue;
        }
        QByteArray json = file.readAll();
        file.close();

        // Never act on a file we couldn't consume, or we'd repeat it
        if (!file.remove()) {
            qWarning() << "Failed to delete" << info.absoluteFilePath();
            continue;
        }

        Dispatcher dispatcher;
        {
            QMutexLocker locker(&m_Lock);
            if (m_Active) {
                dispatcher = m_Dispatcher;
            }
        }

        Command command = parseCommand(json, QDateTime::currentSecsSinceEpoch());
        if (!dispatcher || command == CommandNone) {
            qInfo() << "Ignoring stream control file" << info.fileName()
                    << (dispatcher ? "(invalid or too old)" : "(no active stream)");
            continue;
        }

        qInfo() << "Stream control command:" << command;
        dispatcher(command);
    }
}

void StreamControl::sessionStarted(const StreamInfo& info, bool statsVisible, Dispatcher dispatcher)
{
    {
        QMutexLocker locker(&m_Lock);
        m_Active = true;
        m_Info = info;
        m_Started = QDateTime::currentDateTimeUtc().toString(Qt::ISODate);
        m_StatsVisible = statsVisible;
        m_Dispatcher = std::move(dispatcher);
        m_HasStats = false;
    }

    // Write the state before picking up commands that arrived early
    QMetaObject::invokeMethod(this, "writeState", Qt::QueuedConnection);
    QMetaObject::invokeMethod(this, "scan", Qt::QueuedConnection);
    QMetaObject::invokeMethod(this, "startStatsTimer", Qt::QueuedConnection);
}

void StreamControl::setStatsVisible(bool visible)
{
    {
        QMutexLocker locker(&m_Lock);
        if (!m_Active || m_StatsVisible == visible) {
            return;
        }
        m_StatsVisible = visible;
    }

    QMetaObject::invokeMethod(this, "writeState", Qt::QueuedConnection);
}

void StreamControl::updateStats(const Stats& stats)
{
    QMutexLocker locker(&m_Lock);
    if (m_Active) {
        m_Stats = stats;
        m_HasStats = true;
    }
}

void StreamControl::sessionEnded()
{
    // Done synchronously so the files are gone before the process can exit
    QMutexLocker locker(&m_Lock);
    m_Active = false;
    m_Dispatcher = nullptr;
    m_HasStats = false;
    QFile::remove(statePath());
    QFile::remove(statsPath());
}

void StreamControl::startStatsTimer()
{
    if (m_StatsTimer == nullptr) {
        m_StatsTimer = new QTimer(this);
        m_StatsTimer->setInterval(k_StatsIntervalMs);
        connect(m_StatsTimer, &QTimer::timeout, this, &StreamControl::writeStats);
    }
    m_StatsTimer->start();
}

void StreamControl::writeStats()
{
    QMutexLocker locker(&m_Lock);
    if (!m_Active) {
        m_StatsTimer->stop();
        return;
    }
    if (!m_HasStats) {
        return;
    }

    QSaveFile file(statsPath());
    if (!file.open(QIODevice::WriteOnly) ||
            file.write(statsToJson(m_Stats)) < 0 ||
            !file.commit()) {
        qWarning() << "Failed to write" << statsPath();
    }
}

void StreamControl::writeState()
{
    QMutexLocker locker(&m_Lock);
    if (!m_Active) {
        return;
    }

    QJsonObject state;
    state["version"] = 1;
    state["pid"] = (double)QCoreApplication::applicationPid();
    state["hostUuid"] = m_Info.hostUuid;
    state["hostName"] = m_Info.hostName;
    state["appUuid"] = m_Info.appUuid;
    state["appName"] = m_Info.appName;
    state["started"] = m_Started;
    state["statsVisible"] = m_StatsVisible;

    QDir().mkpath(m_DataDir);
    QSaveFile file(statePath());
    if (!file.open(QIODevice::WriteOnly) ||
            file.write(QJsonDocument(state).toJson()) < 0 ||
            !file.commit()) {
        qWarning() << "Failed to write" << statePath();
    }
}
