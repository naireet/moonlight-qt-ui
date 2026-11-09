#include "streamreconnector.h"
#include "backend/boxartmanager.h"
#include "backend/nvhttp.h"
#include "settings/streamingprofilemanager.h"

#include <QCoreApplication>
#include <QPointer>
#include <QRunnable>
#include <QThreadPool>

#include <functional>

#define RECONNECT_POLL_INTERVAL_MS 2000

namespace {

// QRunnable::create() needs Qt 5.15, which the Steam Link build lacks
class FunctionTask : public QRunnable
{
public:
    explicit FunctionTask(std::function<void()> fn) : m_Fn(std::move(fn)) {}

    void run() override
    {
        m_Fn();
    }

private:
    std::function<void()> m_Fn;
};

// Runs fn on the main thread unless the reconnector was destroyed meanwhile
void postToReconnector(QPointer<StreamReconnector> self, std::function<void(StreamReconnector*)> fn)
{
    QMetaObject::invokeMethod(QCoreApplication::instance(), [self, fn]() {
        if (self) {
            fn(self.data());
        }
    }, Qt::QueuedConnection);
}

}

StreamReconnector::StreamReconnector(NvComputer* computer, const NvApp& app,
                                     StreamingPreferences* preferences, bool perAppProfile)
    : m_Computer(computer),
      m_App(app),
      m_Preferences(preferences),
      m_PerAppProfile(perAppProfile),
      m_PollInFlight(false),
      m_WolSent(false)
{
    m_PollTimer.setInterval(RECONNECT_POLL_INTERVAL_MS);
    connect(&m_PollTimer, &QTimer::timeout, this, &StreamReconnector::poll);
}

QString StreamReconnector::hostName() const
{
    QReadLocker lock(&m_Computer->lock);
    return m_Computer->name;
}

QUrl StreamReconnector::boxArtUrl() const
{
    QString path = BoxArtManager::getCachedBoxArtPath(m_Computer, m_App.id);
    return path.isEmpty() ? QUrl() : QUrl::fromLocalFile(path);
}

void StreamReconnector::start()
{
    m_PollTimer.start();
    poll();
}

void StreamReconnector::stop()
{
    m_PollTimer.stop();
}

void StreamReconnector::poll()
{
    if (m_PollInFlight) {
        return;
    }
    m_PollInFlight = true;

    QPointer<StreamReconnector> self(this);
    NvComputer* computer = m_Computer;
    QThreadPool::globalInstance()->start(new FunctionTask([self, computer]() {
        int gameId = -1;

        // Same probe as PcMonitorThread::tryPollComputer()
        for (const NvAddress& address : computer->uniqueAddresses()) {
            try {
                NvHTTP http(address, 0, computer->serverCert, !computer->isNvidiaServerSoftware);
                QString serverInfo = http.getServerInfo(NvHTTP::NVLL_NONE, true);
                NvComputer newState(http, serverInfo);
                if (newState.uuid != computer->uuid) {
                    continue;
                }

                // Refresh the active address and current game so the new
                // Session resumes (rather than launches) on the right address
                computer->update(newState);
                gameId = newState.currentGameId;
                break;
            } catch (...) {
            }
        }

        postToReconnector(self, [gameId](StreamReconnector* r) {
            r->handlePollResult(gameId);
        });
    }));
}

void StreamReconnector::handlePollResult(int gameId)
{
    m_PollInFlight = false;

    // Ignore late results after stop()
    if (!m_PollTimer.isActive()) {
        return;
    }

    if (gameId < 0) {
        if (!m_WolSent) {
            m_WolSent = true;

            // wake() skips hosts it believes are online, which this one
            // still is from the client's point of view after a drop
            {
                QWriteLocker lock(&m_Computer->lock);
                m_Computer->state = NvComputer::CS_OFFLINE;
            }

            NvComputer* computer = m_Computer;
            QThreadPool::globalInstance()->start(new FunctionTask([computer]() {
                computer->wake();
            }));
        }
        return;
    }

    stop();

    if (gameId == m_App.id) {
        emit hostReady();
    }
    else {
        emit appNotRunning();
    }
}

void StreamReconnector::quitHostApp()
{
    stop();

    QPointer<StreamReconnector> self(this);
    NvComputer* computer = m_Computer;
    QThreadPool::globalInstance()->start(new FunctionTask([self, computer]() {
        QString error;

        try {
            NvHTTP http(computer);
            http.quitApp();
        } catch (const GfeHttpResponseException& e) {
            error = e.toQString();
        } catch (const QtNetworkReplyException& e) {
            error = e.toQString();
        }

        postToReconnector(self, [error](StreamReconnector* r) {
            emit r->quitFinished(error);
        });
    }));
}

Session* StreamReconnector::createSession()
{
    if (m_PerAppProfile) {
        StreamingPreferences* overridePreferences = StreamingPreferences::createStandalone(nullptr);
        if (StreamingProfileManager::get()->applyProfileTo(m_App.preferredProfileId, overridePreferences)) {
            return new Session(m_Computer, m_App, overridePreferences, /* ownsPreferences= */ true);
        }

        delete overridePreferences;
        return new Session(m_Computer, m_App);
    }

    return new Session(m_Computer, m_App, m_Preferences);
}
