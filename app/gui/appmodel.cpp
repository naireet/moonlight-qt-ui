#include "appmodel.h"

#include <algorithm>

AppModel::AppModel(QObject *parent)
    : QAbstractListModel(parent)
{
    connect(&m_BoxArtManager, &BoxArtManager::boxArtLoadComplete,
            this, &AppModel::handleBoxArtLoaded);
}

void AppModel::initialize(ComputerManager* computerManager, int computerIndex, bool showHiddenGames)
{
    m_ComputerManager = computerManager;
    connect(m_ComputerManager, &ComputerManager::computerStateChanged,
            this, &AppModel::handleComputerStateChanged);

    Q_ASSERT(computerIndex < m_ComputerManager->getComputers().count());
    m_Computer = m_ComputerManager->getComputers().at(computerIndex);
    m_CurrentGameId = m_Computer->currentGameId;
    m_ShowHiddenGames = showHiddenGames;

    updateAppList(m_Computer->appList);
}

int AppModel::getRunningAppId()
{
    return m_CurrentGameId;
}

QString AppModel::getRunningAppName()
{
    if (m_CurrentGameId != 0) {
        for (int i = 0; i < m_AllApps.count(); i++) {
            if (m_AllApps[i].id == m_CurrentGameId) {
                return m_AllApps[i].name;
            }
        }
    }

    return nullptr;
}

Session* AppModel::createSessionForApp(int appIndex)
{
    Q_ASSERT(appIndex < m_VisibleApps.count());
    NvApp app = m_VisibleApps.at(appIndex);

    return new Session(m_Computer, app);
}

int AppModel::getDirectLaunchAppIndex()
{
    for (int i = 0; i < m_VisibleApps.count(); i++) {
        if (m_VisibleApps[i].directLaunch) {
            return i;
        }
    }

    return -1;
}

int AppModel::rowCount(const QModelIndex &parent) const
{
    // For list models only the root node (an invalid parent) should return the list's size. For all
    // other (valid) parents, rowCount() should return 0 so that it does not become a tree model.
    if (parent.isValid())
        return 0;

    return m_VisibleApps.count();
}

QVariant AppModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid())
        return QVariant();

    Q_ASSERT(index.row() < m_VisibleApps.count());
    NvApp app = m_VisibleApps.at(index.row());

    switch (role)
    {
    case NameRole:
        return app.name;
    case RunningRole:
        return m_Computer->currentGameId == app.id;
    case BoxArtRole:
        // FIXME: const-correctness
        return const_cast<BoxArtManager&>(m_BoxArtManager).loadBoxArt(m_Computer, app);
    case HiddenRole:
        return app.hidden;
    case AppIdRole:
        return app.id;
    case DirectLaunchRole:
        return app.directLaunch;
    case FavoriteRole:
        return app.favorite;
    case FavoriteOrderRole:
        return app.favoriteOrder;
    case AppCollectorGameRole:
        return app.isAppCollectorGame;
    default:
        return QVariant();
    }
}

QHash<int, QByteArray> AppModel::roleNames() const
{
    QHash<int, QByteArray> names;

    names[NameRole] = "name";
    names[RunningRole] = "running";
    names[BoxArtRole] = "boxart";
    names[HiddenRole] = "hidden";
    names[AppIdRole] = "appid";
    names[DirectLaunchRole] = "directLaunch";
    names[FavoriteRole] = "favorite";
    names[FavoriteOrderRole] = "favoriteOrder";
    names[AppCollectorGameRole] = "appCollectorGame";

    return names;
}

void AppModel::quitRunningApp()
{
    m_ComputerManager->quitRunningApp(m_Computer);
}

bool AppModel::isAppCurrentlyVisible(const NvApp& app)
{
    for (const NvApp& visibleApp : std::as_const(m_VisibleApps)) {
        if (app.id == visibleApp.id) {
            return true;
        }
    }

    return false;
}

bool AppModel::appDisplayOrderLessThan(const NvApp& app1, const NvApp& app2) const
{
    if (app1.favorite != app2.favorite) {
        return app1.favorite && !app2.favorite;
    }

    if (app1.favorite) {
        const bool app1HasExplicitOrder = app1.favoriteOrder >= 0;
        const bool app2HasExplicitOrder = app2.favoriteOrder >= 0;

        if (app1HasExplicitOrder != app2HasExplicitOrder) {
            return app1HasExplicitOrder && !app2HasExplicitOrder;
        }

        if (app1HasExplicitOrder && app1.favoriteOrder != app2.favoriteOrder) {
            return app1.favoriteOrder < app2.favoriteOrder;
        }
    }

    return app1.name.toLower() < app2.name.toLower();
}

QVector<NvApp> AppModel::getVisibleApps(const QVector<NvApp>& appList)
{
    QVector<NvApp> visibleApps;

    for (const NvApp& app : appList) {
        // Don't immediately hide games that were previously visible. This
        // allows users to easily uncheck the "Hide App" checkbox if they
        // check it by mistake.
        if (m_ShowHiddenGames || !app.hidden || isAppCurrentlyVisible(app)) {
            visibleApps.append(app);
        }
    }

    std::stable_sort(visibleApps.begin(), visibleApps.end(),
                     [this](const NvApp& app1, const NvApp& app2) {
        return appDisplayOrderLessThan(app1, app2);
    });

    return visibleApps;
}

void AppModel::updateAppList(QVector<NvApp> newList)
{
    m_AllApps = newList;

    QVector<NvApp> newVisibleList = getVisibleApps(newList);

    // Process removals and updates first
    for (int i = 0; i < m_VisibleApps.count(); i++) {
        const NvApp& existingApp = m_VisibleApps.at(i);

        bool found = false;
        for (const NvApp& newApp : std::as_const(newVisibleList)) {
            if (existingApp.id == newApp.id) {
                // If the data changed, update it in our list
                if (existingApp != newApp) {
                    m_VisibleApps.replace(i, newApp);
                    emit dataChanged(createIndex(i, 0), createIndex(i, 0));
                }

                found = true;
                break;
            }
        }

        if (!found) {
            beginRemoveRows(QModelIndex(), i, i);
            m_VisibleApps.removeAt(i);
            endRemoveRows();
            i--;
        }
    }

    // Process additions now
    for (const NvApp& newApp : std::as_const(newVisibleList)) {
        int insertionIndex = m_VisibleApps.size();
        bool found = false;

        for (int i = 0; i < m_VisibleApps.count(); i++) {
            const NvApp& existingApp = m_VisibleApps.at(i);

            if (existingApp.id == newApp.id) {
                found = true;
                break;
            }
            else if (appDisplayOrderLessThan(newApp, existingApp)) {
                insertionIndex = i;
                break;
            }
        }

        if (!found) {
            beginInsertRows(QModelIndex(), insertionIndex, insertionIndex);
            m_VisibleApps.insert(insertionIndex, newApp);
            endInsertRows();
        }
    }

    for (int i = 0; i < newVisibleList.count(); i++) {
        if (m_VisibleApps.at(i).id == newVisibleList.at(i).id) {
            continue;
        }

        int currentIndex = -1;
        for (int j = i + 1; j < m_VisibleApps.count(); j++) {
            if (m_VisibleApps.at(j).id == newVisibleList.at(i).id) {
                currentIndex = j;
                break;
            }
        }

        Q_ASSERT(currentIndex >= 0);
        beginMoveRows(QModelIndex(), currentIndex, currentIndex, QModelIndex(), i);
        m_VisibleApps.move(currentIndex, i);
        endMoveRows();
    }

    Q_ASSERT(newVisibleList == m_VisibleApps);
}

void AppModel::setAppHidden(int appIndex, bool hidden)
{
    Q_ASSERT(appIndex < m_VisibleApps.count());
    int appId = m_VisibleApps.at(appIndex).id;

    {
        QWriteLocker lock(&m_Computer->lock);

        for (NvApp& app : m_Computer->appList) {
            if (app.id == appId) {
                app.hidden = hidden;
                break;
            }
        }
    }

    m_ComputerManager->clientSideAttributeUpdated(m_Computer);
}

void AppModel::setAppDirectLaunch(int appIndex, bool directLaunch)
{
    Q_ASSERT(appIndex < m_VisibleApps.count());
    int appId = m_VisibleApps.at(appIndex).id;

    {
        QWriteLocker lock(&m_Computer->lock);

        for (NvApp& app : m_Computer->appList) {
            if (directLaunch) {
                // We must clear direct launch from all other apps
                // to set it on the new app.
                app.directLaunch = app.id == appId;
            }
            else if (app.id == appId) {
                // If we're clearing direct launch, we're done once we
                // find our matching app ID.
                app.directLaunch = false;
                break;
            }
        }
    }

    m_ComputerManager->clientSideAttributeUpdated(m_Computer);
}

void AppModel::setAppFavorite(int appIndex, bool favorite)
{
    Q_ASSERT(appIndex < m_VisibleApps.count());
    int appId = m_VisibleApps.at(appIndex).id;

    {
        QWriteLocker lock(&m_Computer->lock);

        for (NvApp& app : m_Computer->appList) {
            if (app.id == appId) {
                if (favorite) {
                    if (!app.favorite) {
                        app.favorite = true;
                        app.favoriteOrder = -1;
                    }
                }
                else {
                    app.favorite = false;
                    app.favoriteOrder = -1;
                }
                break;
            }
        }
    }

    m_ComputerManager->clientSideAttributeUpdated(m_Computer);
}

void AppModel::moveFavorite(int appIndex, int direction)
{
    Q_ASSERT(appIndex < m_VisibleApps.count());

    if (direction != -1 && direction != 1) {
        return;
    }

    NvApp app = m_VisibleApps.at(appIndex);
    if (!app.favorite) {
        return;
    }

    {
        QWriteLocker lock(&m_Computer->lock);
        QVector<NvApp> favoriteApps;

        for (const NvApp& existingApp : std::as_const(m_Computer->appList)) {
            if (existingApp.favorite) {
                favoriteApps.append(existingApp);
            }
        }

        if (favoriteApps.count() < 2) {
            return;
        }

        std::stable_sort(favoriteApps.begin(), favoriteApps.end(),
                         [this](const NvApp& app1, const NvApp& app2) {
            return appDisplayOrderLessThan(app1, app2);
        });

        int currentFavoriteIndex = -1;
        for (int i = 0; i < favoriteApps.count(); i++) {
            if (favoriteApps.at(i).id == app.id) {
                currentFavoriteIndex = i;
                break;
            }
        }

        if (currentFavoriteIndex < 0) {
            return;
        }

        // Skip over any favorites that aren't currently visible in this grid
        // (e.g. hidden games when "show hidden" isn't enabled here), so a
        // reorder always swaps with the next visible neighbor rather than
        // silently swapping against a favorite the user can't see.
        int swapIndex = currentFavoriteIndex + direction;
        while (swapIndex >= 0 && swapIndex < favoriteApps.count() &&
               !isAppCurrentlyVisible(favoriteApps.at(swapIndex))) {
            swapIndex += direction;
        }

        if (swapIndex < 0 || swapIndex >= favoriteApps.count()) {
            return;
        }

        for (int i = 0; i < favoriteApps.count(); i++) {
            favoriteApps[i].favoriteOrder = i;
        }

        std::swap(favoriteApps[currentFavoriteIndex].favoriteOrder,
                  favoriteApps[swapIndex].favoriteOrder);

        for (NvApp& existingApp : m_Computer->appList) {
            for (const NvApp& favoriteApp : std::as_const(favoriteApps)) {
                if (existingApp.id == favoriteApp.id) {
                    existingApp.favoriteOrder = favoriteApp.favoriteOrder;
                    break;
                }
            }
        }
    }

    updateAppList(m_Computer->appList);
}

void AppModel::commitFavoriteOrder()
{
    {
        QWriteLocker lock(&m_Computer->lock);
        QVector<NvApp> favoriteApps;

        for (const NvApp& app : std::as_const(m_Computer->appList)) {
            if (app.favorite) {
                favoriteApps.append(app);
            }
        }

        std::stable_sort(favoriteApps.begin(), favoriteApps.end(),
                         [this](const NvApp& app1, const NvApp& app2) {
            return appDisplayOrderLessThan(app1, app2);
        });

        for (int i = 0; i < favoriteApps.count(); i++) {
            favoriteApps[i].favoriteOrder = i;
        }

        for (NvApp& app : m_Computer->appList) {
            if (!app.favorite) {
                continue;
            }

            for (const NvApp& favoriteApp : std::as_const(favoriteApps)) {
                if (app.id == favoriteApp.id) {
                    app.favoriteOrder = favoriteApp.favoriteOrder;
                    break;
                }
            }
        }
    }

    m_ComputerManager->clientSideAttributeUpdated(m_Computer);
}

void AppModel::handleComputerStateChanged(NvComputer* computer)
{
    // Ignore updates for computers that aren't ours
    if (computer != m_Computer) {
        return;
    }

    // If the computer has gone offline or we've been unpaired,
    // signal the UI so we can go back to the PC view.
    if (m_Computer->state == NvComputer::CS_OFFLINE ||
            m_Computer->pairState == NvComputer::PS_NOT_PAIRED) {
        emit computerLost();
        return;
    }

    // First, process additions/removals from the app list. This
    // is required because the new game may now be running, so
    // we can't check that first.
    if (computer->appList != m_AllApps) {
        updateAppList(computer->appList);
    }

    // Finally, process changes to the active app
    if (computer->currentGameId != m_CurrentGameId) {
        // First, invalidate the running state of newly running game
        for (int i = 0; i < m_VisibleApps.count(); i++) {
            if (m_VisibleApps[i].id == computer->currentGameId) {
                emit dataChanged(createIndex(i, 0),
                                 createIndex(i, 0),
                                 QVector<int>() << RunningRole);
                break;
            }
        }

        // Next, invalidate the running state of the old game (if it exists)
        if (m_CurrentGameId != 0) {
            for (int i = 0; i < m_VisibleApps.count(); i++) {
                if (m_VisibleApps[i].id == m_CurrentGameId) {
                    emit dataChanged(createIndex(i, 0),
                                     createIndex(i, 0),
                                     QVector<int>() << RunningRole);
                    break;
                }
            }
        }

        // Now update our internal state
        m_CurrentGameId = m_Computer->currentGameId;
    }
}

void AppModel::handleBoxArtLoaded(NvComputer* computer, NvApp app, QUrl /* image */)
{
    Q_ASSERT(computer == m_Computer);

    int index = m_VisibleApps.indexOf(app);

    // Make sure we're not delivering a callback to an app that's already been removed
    if (index >= 0) {
        // Let our view know the box art data has changed for this app
        emit dataChanged(createIndex(index, 0),
                         createIndex(index, 0),
                         QVector<int>() << BoxArtRole);
    }
    else {
        qWarning() << "App not found for box art callback:" << app.name;
    }
}
