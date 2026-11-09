#include "gamemode.h"
#include "boxartmanager.h"

#include <QCoreApplication>
#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QHash>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QMutex>
#include <QSaveFile>
#include <QStandardPaths>
#include <QUuid>
#include <QtDebug>

namespace {

QString dataDir()
{
    return QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation) + "/moonlight-stream";
}

QString stripZeroWidth(QString text)
{
    static const ushort k_ZeroWidthChars[] = { 0x200B, 0x200C, 0x200D, 0x2060, 0xFEFF };
    for (ushort c : k_ZeroWidthChars) {
        text.remove(QChar(c));
    }
    return text;
}

QJsonValue boxArtValue(NvComputer* computer, int appId)
{
    QString path = BoxArtManager::getCachedBoxArtPath(computer, appId);
    return path.isEmpty() ? QJsonValue(QJsonValue::Null) : QJsonValue(path);
}

// QSaveFile writes to a temporary file and renames it over the target on commit
bool writeAtomically(const QString& path, const QByteArray& data)
{
    QSaveFile file(path);
    if (!file.open(QIODevice::WriteOnly)) {
        return false;
    }
    file.write(data);
    return file.commit();
}

}

bool GameMode::isAvailable()
{
    bool gameMode = qgetenv("XDG_CURRENT_DESKTOP").compare("gamescope", Qt::CaseInsensitive) == 0 ||
                    qgetenv("SteamDeck") == "1" ||
                    qgetenv("SteamOS") == "1";
    return gameMode && QFile::exists(dataDir() + "/plugin.json");
}

void GameMode::writeHostApps(NvComputer* computer)
{
#ifdef Q_OS_LINUX
    static QMutex s_Lock;
    static QHash<QString, QJsonObject> s_LastWritten;

    QString hostUuid, hostName;
    QVector<NvApp> apps;
    {
        QReadLocker lock(&computer->lock);
        hostUuid = computer->uuid;
        hostName = computer->name;
        apps = computer->appList;
    }

    QJsonArray appArray;
    for (const NvApp& app : std::as_const(apps)) {
        QJsonObject appObject;
        appObject["name"] = stripZeroWidth(app.name);
        appObject["uuid"] = app.uuid;
        appObject["id"] = app.id;
        appObject["boxart"] = boxArtValue(computer, app.id);
        appArray.append(appObject);
    }

    QJsonObject hostObject;
    hostObject["name"] = hostName;
    hostObject["uuid"] = hostUuid;
    hostObject["apps"] = appArray;

    QMutexLocker locker(&s_Lock);

    QString path = dataDir() + "/host-apps.json";
    if (s_LastWritten.value(hostUuid) == hostObject && QFile::exists(path)) {
        return;
    }

    QDir().mkpath(dataDir());

    QJsonObject root;
    QFile existingFile(path);
    if (existingFile.open(QIODevice::ReadOnly)) {
        root = QJsonDocument::fromJson(existingFile.readAll()).object();
        existingFile.close();
    }

    QJsonObject newHostObject = hostObject;
    newHostObject["updated"] = QDateTime::currentDateTimeUtc().toString(Qt::ISODate);

    // Merge by host UUID so other hosts keep their entries
    QJsonArray hosts = root.value("hosts").toArray();
    bool found = false;
    for (int i = 0; i < hosts.size(); i++) {
        if (hosts.at(i).toObject().value("uuid").toString() == hostUuid) {
            hosts.replace(i, newHostObject);
            found = true;
            break;
        }
    }
    if (!found) {
        hosts.append(newHostObject);
    }

    QString exe = QString::fromLocal8Bit(qgetenv("APPIMAGE"));
    if (exe.isEmpty()) {
        exe = QCoreApplication::applicationFilePath();
    }

    root["version"] = 1;
    root["exe"] = exe;
    root["startDir"] = QFileInfo(exe).absolutePath();
    root["hosts"] = hosts;

    if (writeAtomically(path, QJsonDocument(root).toJson())) {
        s_LastWritten.insert(hostUuid, hostObject);
    }
    else {
        qWarning() << "Failed to write" << path;
    }
#else
    Q_UNUSED(computer);
#endif
}

int GameMode::requestAdd(NvComputer* computer, const QVector<NvApp>& apps, bool bulk)
{
    QString requestDir = dataDir() + "/requests";
    if (!QDir().mkpath(requestDir)) {
        qWarning() << "Failed to create" << requestDir;
        return 0;
    }

    QString hostUuid, hostName;
    {
        QReadLocker lock(&computer->lock);
        hostUuid = computer->uuid;
        hostName = computer->name;
    }

    int count = 0;
    for (const NvApp& app : apps) {
        QJsonObject request;
        request["version"] = 1;
        request["action"] = "add";
        request["hostUuid"] = hostUuid;
        request["hostName"] = hostName;
        request["appUuid"] = app.uuid;
        request["appName"] = stripZeroWidth(app.name);
        request["boxart"] = boxArtValue(computer, app.id);
        request["bulk"] = bulk;

        QString path = requestDir + "/" + QUuid::createUuid().toString(QUuid::WithoutBraces) + ".json";
        if (writeAtomically(path, QJsonDocument(request).toJson(QJsonDocument::Compact))) {
            count++;
        }
        else {
            qWarning() << "Failed to write" << path;
        }
    }

    return count;
}
