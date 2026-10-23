/*
    SPDX-FileCopyrightText: 2026 Jared Carlson
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "LauncherController.h"

#include "ApplicationCatalog.h"
#include "DockBand.h"
#include "FileBrowser.h"
#include "KadunceClient.h"
#include "NotesDoor.h"
#include "OmniResults.h"
#include "OpenWindows.h"
#include "RecentUse.h"
#include "RunnerIdentity.h"

#include <KIO/ApplicationLauncherJob>
#include <KIO/CommandLauncherJob>
#include <KLocalizedString>
#include <KConfigGroup>
#include <KRunner/ResultsModel>
#include <KRunner/RunnerManager>
#include <KService/KApplicationTrader>
#include <KService/KService>
#include <KSharedConfig>
#include <KShell>
#include <KUrlMimeData>
#include <LayerShellQt/Window>

#include <QClipboard>
#include <QCoreApplication>
#include <QDBusConnection>
#include <QDBusError>
#include <QDBusMessage>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QDBusReply>
#include <QDBusServiceWatcher>
#include <QDesktopServices>
#include <QDir>
#include <QDrag>
#include <QFileInfo>
#include <QGuiApplication>
#include <QIcon>
#include <QInputMethod>
#include <QJsonDocument>
#include <QJsonObject>
#include <QMimeData>
#include <QMimeDatabase>
#include <QQuickView>
#include <QRegion>
#include <QScreen>
#include <QUrlQuery>
#include <QUuid>

#include <algorithm>
#include <utility>

namespace
{
// How long Search waits on Kadunce's answer to its guest before it shows on
// its own. Kadunce answers from KWin, which a busy moment can hold up.
constexpr int GuestWait = 500;

QDBusMessage bottomSurfaceMethod(const QString &method)
{
    return QDBusMessage::createMethodCall(
        QStringLiteral("co.goodinput.BottomSurface"), QStringLiteral("/BottomSurface"),
        QStringLiteral("co.goodinput.BottomSurface"), method);
}
}

LauncherController::LauncherController(QQuickView *view,
                                       KRunner::RunnerManager *runnerManager,
                                       OmniResults *results,
                                       ApplicationCatalog *catalog,
                                       bool guestAllowed,
                                       QObject *parent)
    : QObject(parent)
    , m_view(view)
    , m_screen(view->screen())
    , m_runnerManager(runnerManager)
    , m_results(results)
    , m_catalog(catalog)
    , m_shares(QDBusConnection::sessionBus())
    , m_guestAllowed(guestAllowed)
    , m_programModified(QFileInfo(QCoreApplication::applicationFilePath()).lastModified())
{
    connect(&m_related, &RelatedInfo::changed, this, [this]() { ++m_relatedRevision; Q_EMIT relatedChanged(); });
    m_lateQuit.setSingleShot(true);
    m_lateQuit.setInterval(1000);
    connect(&m_lateQuit, &QTimer::timeout, qApp, &QCoreApplication::quit);
    m_guestWait.setSingleShot(true);
    m_guestWait.setInterval(GuestWait);
    connect(&m_guestWait, &QTimer::timeout, this, [this] {
        if (m_opening) present();
    });
    auto bus = QDBusConnection::sessionBus();
    Kadunce::follow(QStringLiteral("workspaceContextChanged"), this, SLOT(workspaceUpdated()));
    Kadunce::follow(QStringLiteral("bridgeUnavailable"), this, SLOT(bridgeLost()));
    bus.connect(QStringLiteral("co.goodinput.BottomSurface"), QStringLiteral("/BottomSurface"),
                QStringLiteral("co.goodinput.BottomSurface"), QStringLiteral("pinnedApplicationsChanged"),
                this, SLOT(askPinned()));
    bus.connect(QStringLiteral("co.goodinput.BottomSurface"), QStringLiteral("/BottomSurface"),
                QStringLiteral("co.goodinput.BottomSurface"), QStringLiteral("dockExtentChanged"),
                this, SLOT(dockExtentUpdated()));
    bus.connect(QStringLiteral("co.goodinput.ContextBar"), QStringLiteral("/ContextBar"),
                QStringLiteral("co.goodinput.ContextBar"), QStringLiteral("clockExtentChanged"),
                this, SLOT(contextBarUpdated()));
    auto *owner = new QDBusServiceWatcher(Kadunce::service(), bus,
        QDBusServiceWatcher::WatchForOwnerChange, this);
    connect(owner, &QDBusServiceWatcher::serviceOwnerChanged, this,
            [this]() { bridgeLost(); });
    // Every display, those plugged in later included.
    for (QScreen *screen : QGuiApplication::screens()) watchScreen(screen);
    connect(qGuiApp, &QGuiApplication::screenAdded, this, &LauncherController::watchScreen);
    // Read before the first open, so that open is drawn above the dock.
    readDockBand();
}

LauncherController::~LauncherController() = default;

void LauncherController::watchScreen(QScreen *screen)
{
    const auto boundsChanged = [this, screen] {
        if (screen != placedScreen()) return;
        const bool expanded = m_requestedExpanded;
        const bool chosen = m_expansionChosen;
        endGuestLease();
        m_requestedExpanded = expanded;
        m_expansionChosen = chosen;
        m_drawerExpanded = expanded && (chosen || tabletSurface());
        m_view->setGeometry(screen->geometry());
        readDockBand();
        Q_EMIT guestChanged();
    };
    connect(screen, &QScreen::geometryChanged, this, boundsChanged);
    connect(screen, &QScreen::availableGeometryChanged, this, boundsChanged);
}

bool LauncherController::catalogPinned(int row) const
{
    return m_catalog && m_pinned.contains(m_catalog->applicationId(row));
}

void LauncherController::pinCatalog(int row, bool pin)
{
    const QString id = m_catalog ? m_catalog->applicationId(row) : QString();
    if (id.isEmpty() || !m_dockPresent) return;
    QDBusMessage request = bottomSurfaceMethod(pin ? QStringLiteral("pinApplication") : QStringLiteral("unpinApplication"));
    request << id;
    QDBusConnection::sessionBus().asyncCall(request, 500);
    if (pin) m_pinned.insert(id);
    else m_pinned.remove(id);
    if (m_recent) m_recent->refilter();
    Q_EMIT pinnedChanged();
}

QString LauncherController::relatedOptionLabel(int row)
{
    const auto match = m_results->getQueryMatch(m_results->index(row, 0));
    const auto key = RelatedInfo::keyForSetting(match.id());
    const QHash<QString, QString> labels = {
        {QStringLiteral("bluetooth"), i18n("Open Bluetooth settings")},
        {QStringLiteral("audio"), i18n("Open Sound settings")},
        {QStringLiteral("network"), i18n("Open Network settings")},
        {QStringLiteral("display"), i18n("Open Display settings")},
        {QStringLiteral("power"), i18n("Open Power settings")},
        {QStringLiteral("printers"), i18n("Open Printer settings")},
        {QStringLiteral("storage"), i18n("Open Device Actions")},
        {QStringLiteral("defaults"), i18n("Open Default Applications")},
        {QStringLiteral("nightlight"), i18n("Open Night Light settings")},
        {QStringLiteral("connect"), i18n("Open KDE Connect")}};
    if (runnerApplicationId(match) == QStringLiteral("org.kde.kdeconnect.app.desktop"))
        return i18n("Open KDE Connect");
    return labels.value(key);
}

QVariantList LauncherController::relatedItems(int row)
{
    const auto match = m_results->getQueryMatch(m_results->index(row, 0));
    if (runnerApplicationId(match) == QStringLiteral("org.kde.kdeconnect.app.desktop"))
        return m_related.items(QStringLiteral("connect"));
    if (!match.runner() || !match.runner()->id().contains(QStringLiteral("systemsettings"))) return {};
    return m_related.items(RelatedInfo::keyForSetting(match.id()));
}

// An application's own actions as its entry lists them, separators and
// hidden ones left out, at most four.
static QList<int> shownServiceActions(const KService::Ptr &service)
{
    QList<int> shown;
    if (!service) return shown;
    const auto own = service->actions();
    for (int i = 0; i < own.size() && shown.size() < 4; ++i)
        if (!own.at(i).isSeparator() && !own.at(i).noDisplay() && !own.at(i).text().trimmed().isEmpty()) shown.append(i);
    return shown;
}

QVariantList LauncherController::resultActions(int row) const
{
    const QModelIndex index = m_results->index(row, 0);
    if (!index.isValid()) return {};
    const auto match = m_results->getQueryMatch(index);
    QVariantList actions;
    auto add = [&actions](const QString &label, const QString &action) {
        actions.append(QVariantMap{{QStringLiteral("label"), label}, {QStringLiteral("action"), action}});
    };
    if (searchTier(match) == 0) {
        const auto service = KService::serviceByStorageId(resultApplicationId(row));
        for (const int i : shownServiceActions(service))
            add(service->actions().at(i).text().trimmed(), QStringLiteral("app:%1").arg(i));
        return actions;
    }
    if (searchTier(match) != 1) return {};
    const QFileInfo file(matchFilePath(match));
    if (!file.isAbsolute() || !file.exists()) return {};
    if (file.isFile()) add(i18n("Open With…"), QStringLiteral("open-with"));
    if (m_fileBrowser) add(i18n("Show in Folder"), QStringLiteral("show-in-folder"));
    add(i18n("Copy Path"), QStringLiteral("copy-path"));
    if (m_fileBrowser) add(i18n("Move to Trash"), QStringLiteral("trash"));
    return actions;
}

int LauncherController::runResultAction(int row, const QString &action)
{
    const QModelIndex index = m_results->index(row, 0);
    if (!index.isValid()) return -1;
    const auto match = m_results->getQueryMatch(index);
    if (action.startsWith(QStringLiteral("app:"))) {
        const auto service = KService::serviceByStorageId(resultApplicationId(row));
        bool known = false;
        const int i = action.mid(4).toInt(&known);
        if (!known || !shownServiceActions(service).contains(i)) return -1;
        // A fresh start, never the open window brought forward.
        (new KIO::ApplicationLauncherJob(service->actions().at(i), this))->start();
        return 1;
    }
    if (searchTier(match) != 1) return -1;
    const auto path = QDir::cleanPath(QFileInfo(matchFilePath(match)).absoluteFilePath());
    if (!QFileInfo::exists(path)) return -1;
    if (action == QStringLiteral("copy-path")) {
        QGuiApplication::clipboard()->setText(path);
        return 1;
    }
    if (!m_fileBrowser) return -1;
    if (action == QStringLiteral("show-in-folder")) reveal({path}, false);
    else if ((action == QStringLiteral("open-with") && QFileInfo(path).isFile())
             || action == QStringLiteral("trash")) reveal({path}, false, action);
    else return -1;
    return 0;
}

bool LauncherController::tabletSurface() const
{
    const QScreen *screen = placedScreen();
    return screen && screen->name().startsWith(QStringLiteral("eDP"), Qt::CaseInsensitive);
}

void LauncherController::setDrawerExpanded(bool expanded, bool chosen)
{
    const quint64 generation = ++m_presentationGeneration;
    m_requestedExpanded = expanded;
    m_expansionChosen = chosen;
    if (!m_guestMode) {
        m_drawerExpanded = expanded && (chosen || tabletSurface());
        Q_EMIT guestChanged();
        return;
    }
    if (!m_guestExpansionSupported || !m_activeGuestRect.isValid()) {
        endGuestLease();
        m_requestedExpanded = expanded;
        m_expansionChosen = chosen;
        m_drawerExpanded = expanded && (chosen || tabletSurface());
        Q_EMIT guestChanged();
        return;
    }
    if (!expanded) {
        m_drawerExpanded = false;
        m_guestRect = m_compactGuestRect;
        Q_EMIT guestChanged();
        // Keep the expanded input envelope until the visual collapse ends.
        QTimer::singleShot(260, this, [this, generation] {
            if (generation != m_presentationGeneration || !m_guestMode) return;
            Kadunce::tell(QStringLiteral("setLauncherGuestExpanded"), {false});
            m_view->setMask(QRegion(m_guestRect.adjusted(-16, -16, 16, 16)));
        });
        return;
    }
    auto *watcher = new QDBusPendingCallWatcher(
        Kadunce::ask(QStringLiteral("setLauncherGuestExpanded"), {true}, 700), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this, watcher, generation] {
        const QDBusPendingReply<bool> reply = *watcher;
        watcher->deleteLater();
        if (generation != m_presentationGeneration || !m_guestMode) return;
        if (reply.isError() || !reply.value()) {
            const bool chosen = m_expansionChosen;
            endGuestLease();
            m_requestedExpanded = true;
            m_expansionChosen = chosen;
            m_drawerExpanded = chosen || tabletSurface();
        } else {
            m_drawerExpanded = true;
            // Expanded input ends at the same dock-safe boundary as paint.
            m_view->setMask(QRegion(m_activeGuestRect));
            m_guestRect = m_activeGuestRect;
        }
        Q_EMIT guestChanged();
    });
}

QRect LauncherController::availableArea() const
{
    const auto *screen = placedScreen();
    return screen ? workArea(screen->availableGeometry().translated(-screen->geometry().topLeft()),
                             screen->geometry().size(), m_dockBand, m_contextBar)
                  : QRect(0, 0, m_view->width(), m_view->height());
}

bool LauncherController::resultIsOpen(int row) const
{
    const QModelIndex index = m_results->index(row, 0);
    if (searchTier(m_results->getQueryMatch(index)) != 0) return false;
    return index.isValid() && m_context.applicationIsOpen(
        runnerApplicationId(m_results->data(index, KRunner::ResultsModel::QueryMatchRole).value<KRunner::QueryMatch>()),
        m_results->data(index, Qt::DisplayRole).toString());
}

QString LauncherController::resultApplicationId(int row) const
{
    const QModelIndex index = m_results->index(row, 0);
    if (!index.isValid() || searchTier(m_results->getQueryMatch(index)) != 0) return {};
    const QString id = QFileInfo(runnerApplicationId(m_results->getQueryMatch(index))).fileName();
    return id.endsWith(QStringLiteral(".desktop")) && !id.startsWith(QStringLiteral("kcm_")) ? id : QString();
}

int LauncherController::activateIfOpen(int row)
{
    const QModelIndex index = m_results->index(row, 0);
    if (!index.isValid()) return 0;
    if (searchTier(m_results->getQueryMatch(index)) != 0) return 0;
    return bringForward(
        runnerApplicationId(m_results->data(index, KRunner::ResultsModel::QueryMatchRole).value<KRunner::QueryMatch>()),
        m_results->data(index, Qt::DisplayRole).toString());
}

int LauncherController::activateCatalogIfOpen(int row)
{
    if (!m_catalog) return 0;
    return bringForward(m_catalog->applicationId(row), m_catalog->applicationName(row));
}

int LauncherController::bringForward(const QString &applicationId, const QString &name)
{
    // What is open is read as Search opens and again at each change, so a
    // tap reads it afresh only while that reading has not answered.
    if (m_contextPending) refreshContextBlocking();
    const QString windowId = m_context.windowIdForApplication(applicationId, name);
    if (windowId.isEmpty()) return 0;
    bool brought = false;
    if (m_contextFromKadunce) {
        const QDBusReply<bool> reply = Kadunce::call(QStringLiteral("activateApplicationWindow"), {windowId}, 500);
        brought = reply.isValid() && reply.value();
    } else {
        brought = m_openWindows && m_openWindows->activate(windowId);
    }
    if (brought) return 1;
    refreshContextBlocking();
    return m_context.applicationIsOpen(applicationId, name) ? -1 : 0;
}

void LauncherController::workspaceUpdated()
{
    if (m_view->isVisible() || filesWindowOpen()) refreshContext();
}

void LauncherController::askPinned()
{
    auto *watcher = new QDBusPendingCallWatcher(
        QDBusConnection::sessionBus().asyncCall(bottomSurfaceMethod(QStringLiteral("pinnedApplications")), 500), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this, watcher] {
        watcher->deleteLater();
        const QDBusPendingReply<QStringList> reply = *watcher;
        const bool present = !reply.isError();
        QSet<QString> pinned;
        if (!reply.isError()) {
            for (QString id : reply.value()) {
                if (id.startsWith(QStringLiteral("applications:"))) id.remove(0, 13);
                pinned.insert(id);
            }
        }
        if (pinned == m_pinned && present == m_dockPresent) return;
        m_dockPresent = present;
        m_pinned = pinned;
        if (m_recent) m_recent->refilter();
        Q_EMIT pinnedChanged();
    });
}

void LauncherController::contextBarUpdated()
{
    readContextBar();
}

void LauncherController::dockExtentUpdated()
{
    if (!m_view->isVisible()) return;
    readDockBand();
    Q_EMIT guestChanged();
}

void LauncherController::bridgeLost()
{
    ++m_presentationGeneration;
    m_drawerExpanded = m_requestedExpanded && (m_expansionChosen || tabletSurface());
    m_launchToken.clear();
    ++m_contextGeneration;
    m_contextPending = false;
    m_context.clear();
    m_contextFromKadunce = false;
    m_guestMode = false;
    m_guestRect = {};
    m_view->setMask(QRegion());
    // A Kadunce gone answers nothing, and the next may speak another protocol.
    ++m_guestGeneration;
    m_guestAsking = false;
    m_guestProtocol = 0;
    Q_EMIT contextChanged();
    Q_EMIT guestChanged();
    Q_EMIT guestBridgeLost();
    if (m_opening) present();
    // Kadunce gone, what is open comes from Plasma's window list.
    if (m_view->isVisible() || filesWindowOpen()) refreshContext();
}

void LauncherController::toggle()
{
    if (openOrOpening()) close();
    else open();
}

void LauncherController::toggleToType()
{
    if (openOrOpening()) {
        close();
        return;
    }
    openFor(true);
}

void LauncherController::showDrive(const QString &id)
{
    if (!m_fileBrowser) { open(); return; }
    showFiles();
    whenShown([this, id] { filesTarget()->openDrive(id); });
}

void LauncherController::showFile(const QString &file)
{
    const QFileInfo info(file);
    if (!m_fileBrowser || !info.isAbsolute() || !info.isFile() || info.isSymLink()) { open(); return; }
    if (filesWindowOpen()) {
        showFilesWindow();
        filesTarget()->reveal({info.absoluteFilePath()});
        return;
    }
    open();
    whenShown([this, path = info.absoluteFilePath()] {
        m_fileBrowser->reveal({path});
        Q_EMIT filesRequested();
    });
}

void LauncherController::showFolder(const QString &location)
{
    showFolders({location});
}

void LauncherController::showFolders(const QStringList &locations)
{
    QStringList folders, phones;
    QList<QUrl> elsewhere;
    bool recent = false;
    for (const auto &location : locations) {
        const QUrl url = QUrl::fromUserInput(location, QString(), QUrl::AssumeLocalFile);
        const auto phone = m_fileBrowser ? m_fileBrowser->phoneForAddress(url) : QString();
        if (url.isLocalFile()) folders.append(QDir::cleanPath(QFileInfo(url.toLocalFile()).absoluteFilePath()));
        else if (url.scheme() == QLatin1String("recentlyused")) recent = true;
        // Trash is one of Files' own places, so it never goes on to Dolphin.
        else if (url.scheme() == QLatin1String("trash")) folders.append(PlaceBook::trashLocation());
        else if (!phone.isEmpty()) phones.append(phone);
        else if (url.isValid()) elsewhere.append(url);
    }
    if (!elsewhere.isEmpty()) handOn(elsewhere);
    if (!m_fileBrowser || (folders.isEmpty() && !recent && phones.isEmpty())) return;
    showFiles();
    whenShown([this, folders, phones, recent] {
        FileBrowser *files = filesTarget();
        if (recent) files->navigate(FileBrowser::recentLocation());
        for (int i = 0; i < folders.size(); ++i) {
            if (i == 0 && !recent) files->navigate(folders[i]);
            else files->openTab(folders[i]);
        }
        if (folders.isEmpty() && !recent) files->openDrive(phones.first());
    });
}

void LauncherController::revealItems(const QStringList &locations)
{
    reveal(locations, false);
}

void LauncherController::showItemProperties(const QStringList &locations)
{
    reveal(locations, true);
}

void LauncherController::openDrawer(const QString &drawer)
{
    if (drawer == QLatin1String("files") && filesWindowOpen()) {
        if (openOrOpening()) close();
        showFilesWindow();
        return;
    }
    if (!openOrOpening()) open();
    // "note" is a new quick note, and "note:" with a note's id that note.
    const bool note = drawer == QLatin1String("note")
        || (drawer.startsWith(QLatin1String("note:")) && drawer.size() > 5);
    if (drawer == QLatin1String("apps") || drawer == QLatin1String("files")
        || drawer == QLatin1String("notes") || drawer == QLatin1String("notes-back")
        || drawer == QLatin1String("helpers") || note)
        whenShown([this, drawer] { Q_EMIT drawerRequested(drawer); });
}

void LauncherController::open()
{
    openFor(false);
}

void LauncherController::openFor(bool toType)
{
    m_quitAfterFiles = false;
    m_lateQuit.stop();
    if (m_opening) return;
    m_openedToType = toType;
    m_opening = true;
    m_launchToken.clear();
    endGuestLease();
    m_guestRect = {};
    m_view->setMask(QRegion());
    refreshContext();
    m_runnerManager->setupMatchSession();
    m_results->setQueryString(QString());
    if (m_recent) {
        m_recent->setWithheld(!m_shares.activities().isEmpty());
        m_recent->refresh();
    }
    askPinned();
    if (m_notes) m_notes->refresh();
    askGuest();
}

void LauncherController::present()
{
    m_opening = false;
    m_guestWait.stop();
    readDockBand();
    Q_EMIT guestChanged();
    // Search sets out its first screen before the window shows, since the
    // window's first frame can be drawn as it is shown: what it held when it
    // last closed never reaches the screen. It takes the keys once shown.
    Q_EMIT aboutToOpen();
    m_view->show();
    m_view->requestActivate();
    Q_EMIT opened();
    keepTheKeys();
    const auto steps = std::exchange(m_whenShown, {});
    for (const auto &step : steps) step();
}

void LauncherController::keepTheKeys()
{
    m_shownAt.start();
    // Started cold, or as the desktop is still settling, the window may not
    // be on screen yet when it first asks to take the keys, and the ask is
    // lost: it asks again once its first frame is shown, and a few times
    // more while it still has not been given them.
    // Tied to the window itself, so nothing is asked of a window that is
    // gone.
    const auto ask = [view = m_view] {
        if (view->isVisible() && !view->isActive()) view->requestActivate();
    };
    connect(m_view, &QQuickWindow::frameSwapped, m_view, ask, Qt::SingleShotConnection);
    for (const int after : {100, 300, 700})
        QTimer::singleShot(after, m_view, ask);
    // Another window made active just as Search opens, as one the desktop
    // was still raising, gives the keys straight back: what is typed then
    // was meant for Search.
    if (m_keysKept) return;
    m_keysKept = true;
    connect(m_view, &QWindow::activeChanged, this, [this, ask] {
        if (!m_view->isActive() && m_view->isVisible() && !m_guestMode
                && m_shownAt.isValid() && m_shownAt.elapsed() < 1500)
            QTimer::singleShot(0, m_view, ask);
    });
}

bool LauncherController::openOrOpening() const
{
    return m_opening || m_view->isVisible();
}

void LauncherController::whenShown(std::function<void()> step)
{
    if (m_opening) m_whenShown.append(std::move(step));
    else step();
}

bool LauncherController::leaveFor(const QStringList &settings)
{
    QStringList mine = m_startedWith;
    QStringList theirs = settings;
    mine.sort();
    theirs.sort();
    // Shown, or holding Files' window, a copy or a carry, it stays as it is.
    if (mine == theirs || openOrOpening() || filesWindowOpen() || m_carrying
        || filesWorking())
        return false;
    // After this answer has gone.
    QTimer::singleShot(0, qApp, &QCoreApplication::quit);
    return true;
}

void LauncherController::close()
{
    m_opening = false;
    m_guestWait.stop();
    m_whenShown.clear();
    m_shownAt.invalidate();
    endGuestLease();
    m_results->clear();
    m_runnerManager->matchSessionComplete();
    m_view->hide();
    finishOrDeferQuit();
}

void LauncherController::carryOut(const QStringList &paths, const QRectF &sheet, QObject *from)
{
    FileBrowser *files = from ? qobject_cast<FileBrowser *>(from) : m_fileBrowser;
    if (m_carrying || !files) return;
    QMimeData *mime = files->carriedFiles(paths);
    if (!mime) return;
    // KDE's document portal lets a sandboxed application read them too.
    KUrlMimeData::exportUrlsToPortal(mime);
    const QIcon icon = QIcon::fromTheme(QMimeDatabase().mimeTypeForFile(paths.first()).iconName(),
        QIcon::fromTheme(QStringLiteral("text-x-generic")));
    carry(mime, icon, sheet);
}

void LauncherController::carryApplication(int row, const QRectF &sheet)
{
    if (m_carrying || !m_catalog) return;
    const QUrl url = m_catalog->applicationUrl(row);
    if (!url.isValid()) return;
    auto *mime = new QMimeData;
    mime->setUrls({url});
    // Apps itself reads which application it is, to make a folder.
    mime->setData(QStringLiteral("application/x-tettegouche-application"),
                  m_catalog->applicationId(row).toUtf8());
    carry(mime, QIcon::fromTheme(m_catalog->applicationIcon(row),
        QIcon::fromTheme(QStringLiteral("application-x-executable"))), sheet);
}

void LauncherController::carryFolder(int row, const QRectF &sheet)
{
    if (m_carrying || !m_catalog) return;
    const QList<QUrl> urls = m_catalog->folderUrls(row);
    if (urls.isEmpty()) return;
    auto *mime = new QMimeData;
    mime->setUrls(urls);
    mime->setData(QStringLiteral("application/x-tettegouche-folder"),
                  QJsonDocument(QJsonObject{{QStringLiteral("name"), m_catalog->folderName(row)}})
                      .toJson(QJsonDocument::Compact));
    carry(mime, QIcon::fromTheme(QStringLiteral("folder")), sheet);
}

void LauncherController::carry(QMimeData *mime, const QIcon &icon, const QRectF &sheet)
{
    m_carrying = true;
    // Standalone, the launcher's surface covers the display so a press
    // outside the sheet can close it. Carrying, that cover would take
    // the drop meant for the windows beside the sheet. A changed input
    // region reaches the compositor only with the next frame, so each
    // change asks for one; without it the cover stayed away after a drop.
    const bool uncovered = !m_guestMode && m_view->isVisible();
    if (uncovered) { m_view->setMask(QRegion(sheet.toAlignedRect())); m_view->update(); }
    QMetaObject::invokeMethod(this, [this, mime, icon, uncovered]() {
        auto *drag = new QDrag(this);
        drag->setMimeData(mime);
        drag->setPixmap(icon.pixmap(QSize(48, 48), m_view->devicePixelRatio()));
        drag->exec(Qt::CopyAction, Qt::CopyAction);
        drag->deleteLater();
        m_carrying = false;
        if (uncovered && !m_guestMode) { m_view->setMask(QRegion()); m_view->update(); }
        if (m_quitAfterFiles) finishOrDeferQuit();
    }, Qt::QueuedConnection);
}

void LauncherController::finishLaunch()
{
    // Runner actions may finish their launch asynchronously. Hide the
    // launcher immediately, but keep its event loop and match session
    // alive long enough for Plasma to dispatch the selected action. A
    // folder found by search comes back to this launcher's Files, which
    // may show it before then; it stays.
    endGuestLease();
    m_view->hide();
    QTimer::singleShot(750, this, [this]() {
        if (openOrOpening()) return;
        m_runnerManager->matchSessionComplete();
        finishOrDeferQuit();
    });
}

void LauncherController::warmUp()
{
    if (openOrOpening()) return;
    if (m_recent) m_recent->refresh();
    if (m_notes) m_notes->refresh();
}

void LauncherController::leaveIfUnused()
{
    if (!openOrOpening()) finishOrDeferQuit(false);
}

void LauncherController::updateGuestDrag(double horizontalDelta)
{
    if (!m_guestMode) return;
    Kadunce::tell(QStringLiteral("updateLauncherGuest"), {horizontalDelta});
}

bool LauncherController::finishGuestDrag(double horizontalDelta)
{
    if (!m_guestMode) return false;
    const QDBusReply<bool> reply = Kadunce::call(QStringLiteral("finishLauncherGuest"), {horizontalDelta}, 500);
    return reply.isValid() && reply.value();
}

bool LauncherController::beginGuestApplicationLaunch(int row, bool catalog)
{
    if (!m_guestMode) return false;
    const auto match = m_results->getQueryMatch(m_results->index(row, 0));
    QString appId = catalog && m_catalog ? m_catalog->applicationId(row)
        : (searchTier(match) == 0 ? runnerApplicationId(match) : QString());
    if (!catalog && searchTier(match) == 1) {
        auto urls = match.urls();
        if (urls.isEmpty() && match.data().canConvert<QUrl>()) urls.append(match.data().toUrl());
        if (!urls.isEmpty() && urls.first().isLocalFile()) {
            const auto service = KApplicationTrader::preferredService(
                QMimeDatabase().mimeTypeForUrl(urls.first()).name());
            if (service) appId = service->storageId();
        }
    }
    if (!catalog && match.runner()
        && match.runner()->id().contains(QStringLiteral("systemsettings")))
        appId = QStringLiteral("systemsettings.desktop");
    return prepareGuestIdentity(appId);
}

bool LauncherController::prepareGuestIdentity(QString appId, const QStringList &aliases)
{
    if (!m_guestMode) return false;
    if (appId.isEmpty()) return false;
    if (appId.startsWith(QStringLiteral("services_"))) appId.remove(0, 9);
    if (appId.startsWith(QStringLiteral("applications:"))) appId.remove(0, 13);
    QStringList identities{appId};
    identities.append(aliases);
    if (const auto service = KService::serviceByStorageId(appId)) {
        const auto wmClass = service->property<QString>(QStringLiteral("StartupWMClass"));
        if (!wmClass.isEmpty()) identities.append(wmClass);
    }
    m_launchToken = QUuid::createUuid().toString(QUuid::WithoutBraces);
    const QDBusReply<bool> reply = Kadunce::call(QStringLiteral("prepareLauncherGuestLaunch"),
                                                 {identities, m_launchToken}, 500);
    const bool accepted = reply.isValid() && reply.value();
    if (!accepted) m_launchToken.clear();
    return accepted;
}

bool LauncherController::beginGuestNotesLaunch()
{
    return prepareGuestIdentity(QString::fromLatin1(NotesDoor::ApplicationId));
}

void LauncherController::cancelGuestApplicationLaunch()
{
    m_launchToken.clear();
    if (!m_guestMode) return;
    Kadunce::tell(QStringLiteral("cancelLauncherGuestLaunch"));
}

bool LauncherController::filesWindowOpen() const
{
    return frontFilesWindow() != nullptr;
}

LauncherController::FilesWindow *LauncherController::frontFilesWindow() const
{
    FilesWindow *open = nullptr;
    for (const auto &window : m_filesWindows) {
        if (!window->view->isVisible()) continue;
        if (window->view.get() == m_lastFilesWindow) return window.get();
        open = window.get();
    }
    return open;
}

FileBrowser *LauncherController::filesTarget() const
{
    const FilesWindow *window = frontFilesWindow();
    return window ? window->files(m_fileBrowser) : m_fileBrowser;
}

bool LauncherController::showFilesWindow()
{
    if (!filesWindowOpen()) return popOutFilesWindow();
    m_lateQuit.stop();
    raiseFilesWindow();
    return true;
}

bool LauncherController::popOutFilesWindow()
{
    if (!m_fileBrowser) return false;
    m_lateQuit.stop();
    // Without a Files of its own to give each window, the one window shares
    // Search's and is brought forward again.
    if (!m_makeFileBrowser && filesWindowOpen()) {
        raiseFilesWindow();
        return true;
    }
    FilesWindow *window = nullptr;
    for (const auto &kept : m_filesWindows) {
        if (!kept->view->isVisible() && !(kept->browser && kept->browser->working())) {
            window = kept.get();
            break;
        }
    }
    if (!window) {
        auto made = std::make_unique<FilesWindow>();
        if (m_makeFileBrowser) {
            made->browser = m_makeFileBrowser();
            if (!made->browser) return false;
            made->browser->setRemembered(false);
        }
        FileBrowser *files = made->files(m_fileBrowser);
        made->view = std::make_unique<QQuickView>(m_view->engine(), nullptr);
        QQuickView *view = made->view.get();
        view->setTitle(i18n("Files"));
        view->setIcon(QIcon::fromTheme(QStringLiteral("system-file-manager")));
        view->setResizeMode(QQuickView::SizeRootObjectToView);
        view->setMinimumSize(QSize(420, 320));
        view->setInitialProperties({
            {QStringLiteral("fileBrowser"), QVariant::fromValue<QObject *>(files)},
            {QStringLiteral("launcherController"), QVariant::fromValue<QObject *>(this)},
        });
        view->setSource(QUrl(QStringLiteral("qrc:/qml/FilesWindow.qml")));
        if (view->status() == QQuickView::Error) return false;
        connect(view, &QWindow::visibleChanged, this, [this](bool visible) {
            if (!visible && !filesWindowOpen()) QGuiApplication::setDesktopFileName(m_launcherApplicationId);
            Q_EMIT filesWindowChanged();
            // The last closed with Search gone too, the launcher's work is done.
            if (!visible && !m_view->isVisible()) finishOrDeferQuit();
        });
        connect(view, &QWindow::activeChanged, this, [this, view] {
            if (view->isActive()) m_lastFilesWindow = view;
        });
        if (made->browser) watchFiles(made->browser.get(), made.get());
        window = made.get();
        m_filesWindows.push_back(std::move(made));
    }
    // It starts where Search's Files is, with its places and drives beside.
    if (window->browser) {
        window->browser->adopt(*m_fileBrowser);
        window->browser->open();
    }
    QQuickView *view = window->view.get();
    const QRect area = availableArea();
    const QSize size = m_guestMode && m_compactGuestRect.isValid()
        ? m_compactGuestRect.size()
        : QSize(qRound(area.width() * 0.64), qRound(area.height() * 0.64));
    view->resize(size.expandedTo(view->minimumSize()));
    view->setScreen(placedScreen());
    // A window takes the application's identity as it is shown, and Files
    // keeps it while a window of its own is open.
    if (!filesWindowOpen()) m_launcherApplicationId = QGuiApplication::desktopFileName();
    QGuiApplication::setDesktopFileName(QString::fromLatin1(FilesApplicationId));
    m_lastFilesWindow = view;
    view->show();
    view->requestActivate();
    Q_EMIT filesWindowChanged();
    return true;
}

bool LauncherController::beginGuestFilesLaunch()
{
    return prepareGuestIdentity(QString::fromLatin1(FilesApplicationId));
}

void LauncherController::showInputMethod()
{
    if (QInputMethod *inputMethod = QGuiApplication::inputMethod()) {
        inputMethod->show();
    }
}

bool LauncherController::searchWeb(const QString &query, bool chosen)
{
    if (query.trimmed().isEmpty()) return false;
    if (!chosen && (m_results->querying() || m_results->rowCount() != 0)) return false;
    QUrl url(QStringLiteral("https://duckduckgo.com/"));
    QUrlQuery parameters;
    parameters.addQueryItem(QStringLiteral("q"), query.trimmed());
    url.setQuery(parameters);
    // URL activation is deliberate; never run text as a shell command.
    const auto browser = KApplicationTrader::preferredService(QStringLiteral("x-scheme-handler/https"));
    bool opened = false;
    if (browser) {
        auto args = KShell::splitArgs(browser->exec());
        if (!args.isEmpty()) {
            const QString program = args.takeFirst();
            // A browser installed by hand runs as zen-bin or firefox-bin.
            QString name = QFileInfo(program).fileName().toLower();
            if (name.endsWith(QStringLiteral("-bin"))) name.chop(4);
            if (name == QStringLiteral("zen") || name == QStringLiteral("zen-browser")
                || name == QStringLiteral("firefox") || name == QStringLiteral("librewolf")
                || name == QStringLiteral("floorp")) {
                args.removeIf([](const QString &arg) { return arg.startsWith(QLatin1Char('%')); });
                args << QStringLiteral("--new-tab") << url.toString(QUrl::FullyEncoded);
                // Launched as a job, the browser gets an activation token from
                // Search's window, so a running browser that takes the tab
                // comes to the front with it rather than staying behind.
                auto *job = new KIO::CommandLauncherJob(program, args, this);
                job->setDesktopName(browser->desktopEntryName());
                connect(job, &KJob::result, this, [url](KJob *done) {
                    if (done->error()) QDesktopServices::openUrl(url);
                });
                job->start();
                opened = true;
            }
        }
        if (!opened) {
            // Any other browser is started as its own entry with the address,
            // so it too carries Search's activation token and comes forward.
            auto *job = new KIO::ApplicationLauncherJob(browser, this);
            job->setUrls({url});
            connect(job, &KJob::result, this, [url](KJob *done) {
                if (done->error()) QDesktopServices::openUrl(url);
            });
            job->start();
            opened = true;
        }
    }
    if (!opened) opened = QDesktopServices::openUrl(url);
    if (!opened) return false;
    if (m_launchToken.isEmpty()) finishLaunch();
    return true;
}

bool LauncherController::beginGuestWebLaunch()
{
    const auto browser = KApplicationTrader::preferredService(QStringLiteral("x-scheme-handler/https"));
    if (!browser) return false;
    const auto args = KShell::splitArgs(browser->exec());
    const auto executable = args.isEmpty() ? QString() : QFileInfo(args.first()).fileName();
    return prepareGuestIdentity(browser->storageId(), {executable});
}

void LauncherController::completeGuestHandoff()
{
    m_guestMode = false;
    m_view->hide();
    QTimer::singleShot(340, this, [this]() {
        finishOrDeferQuit();
    });
}

void LauncherController::dismissGuest()
{
    m_guestMode = false;
    m_view->hide();
    finishOrDeferQuit();
}

void LauncherController::completeGuestLaunch(const QString &requestToken)
{
    if (m_guestMode && !m_launchToken.isEmpty() && requestToken == m_launchToken) {
        m_launchToken.clear();
        Q_EMIT guestLaunchReady();
    }
}

void LauncherController::reportShowing(const QString &mode, bool loading)
{
    m_showingMode = mode;
    m_showingLoading = loading;
    Q_EMIT showing(mode, loading);
}

void LauncherController::repeatShowing()
{
    Q_EMIT showing(m_showingMode, m_showingLoading);
}

void LauncherController::completeGuestNavigation(int slot)
{
    if (m_guestMode && slot != 0) {
        Q_EMIT guestNavigationReady(slot);
    }
}

void LauncherController::setFileBrowser(FileBrowser *browser)
{
    m_fileBrowser = browser;
    watchFiles(browser, nullptr);
}

void LauncherController::watchFiles(FileBrowser *browser, FilesWindow *window)
{
    connect(browser, &FileBrowser::operationChanged, this, [this] {
        if (m_quitAfterFiles && !filesWorking()) finishOrDeferQuit();
    });
    // A copy that meets a name already taken waits for an answer; the
    // launcher comes back to the Files that started it to ask it rather
    // than wait unseen.
    connect(browser, &FileBrowser::questionChanged, this, [this, browser, window] {
        if (browser->question().isEmpty()) return;
        if (!window) {
            if (m_view->isVisible()) return;
            open();
            whenShown([this] { Q_EMIT filesRequested(); });
            return;
        }
        if (!window->view->isVisible()) window->view->show();
        m_lastFilesWindow = window->view.get();
        raiseFilesWindow();
    });
}

bool LauncherController::filesWorking() const
{
    if (m_fileBrowser && m_fileBrowser->working()) return true;
    return std::any_of(m_filesWindows.cbegin(), m_filesWindows.cend(),
                       [](const auto &window) { return window->browser && window->browser->working(); });
}

void LauncherController::setRecentUse(RecentUse *recent)
{
    m_recent = recent;
    recent->setExcluded([this](const QString &applicationId, const QString &name) {
        return m_pinned.contains(applicationId) || m_context.applicationIsOpen(applicationId, name)
            || (m_catalog && m_catalog->isHiddenApplication(applicationId));
    });
    connect(this, &LauncherController::contextChanged, recent, &RecentUse::refilter);
    connect(&m_shares, &ScreenShareProvider::changed, recent, [this] {
        m_recent->setWithheld(!m_shares.activities().isEmpty());
    });
}

void LauncherController::setOpenWindows(OpenWindows *windows)
{
    m_openWindows = windows;
    // A window opening or closing while Search is seen, where Kadunce does
    // not say what is open; a burst of changes is read once.
    auto *settle = new QTimer(this);
    settle->setSingleShot(true);
    settle->setInterval(150);
    connect(windows, &OpenWindows::changed, settle, qOverload<>(&QTimer::start));
    connect(settle, &QTimer::timeout, this, [this] {
        if (m_contextFromKadunce || m_contextPending || !(m_view->isVisible() || filesWindowOpen())) return;
        takeContext(false, QString());
    });
}

bool LauncherController::beginGuestRecentLaunch(int row)
{
    return m_recent ? prepareGuestIdentity(m_recent->applicationFor(row)) : false;
}

void LauncherController::showFiles()
{
    if (filesWindowOpen()) {
        showFilesWindow();
        return;
    }
    if (!openOrOpening()) open();
    whenShown([this] { Q_EMIT filesRequested(); });
}

void LauncherController::raiseFilesWindow()
{
    FilesWindow *window = frontFilesWindow();
    if (!window) return;
    // Through the window list, which also brings a minimized window back;
    // the window itself, where that list cannot.
    if (bringForward(QString::fromLatin1(FilesApplicationId), QString()) == 1) return;
    window->view->showNormal();
    window->view->raise();
    window->view->requestActivate();
}

void LauncherController::reveal(const QStringList &locations, bool properties, const QString &action)
{
    QStringList paths;
    QList<QUrl> elsewhere;
    for (const auto &location : locations) {
        const QUrl url = QUrl::fromUserInput(location, QString(), QUrl::AssumeLocalFile);
        if (url.isLocalFile()) paths.append(QDir::cleanPath(QFileInfo(url.toLocalFile()).absoluteFilePath()));
        else if (url.isValid()) elsewhere.append(url.adjusted(QUrl::RemoveFilename));
    }
    if (!elsewhere.isEmpty()) handOn(elsewhere);
    if (paths.isEmpty() || !m_fileBrowser) return;
    showFiles();
    whenShown([this, paths, properties, action] { filesTarget()->reveal(paths, properties, action); });
}

void LauncherController::handOn(const QList<QUrl> &urls)
{
    const auto dolphin = KService::serviceByDesktopName(QStringLiteral("org.kde.dolphin"));
    if (!dolphin) {
        if (!m_fileBrowser) return;
        showFiles();
        whenShown([this, place = urls.first().toDisplayString()] {
            filesTarget()->setStatus(i18n("Files cannot open %1, and Dolphin is not installed.", place));
        });
        return;
    }
    auto *job = new KIO::ApplicationLauncherJob(dolphin);
    job->setUrls(urls);
    connect(job, &KJob::result, this, [this]() { if (!m_view->isVisible()) finishOrDeferQuit(); });
    job->start();
}

void LauncherController::finishOrDeferQuit(bool keepReady)
{
    m_quitAfterFiles = true;
    // Files' own window keeps the launcher, and with it Files, running.
    if (filesWindowOpen()) return;
    if (m_carrying || filesWorking()) return;
    // Closed, the launcher stays ready, hidden, so the next open shows at
    // once; it gives back what it drew with. One whose program was
    // replaced since it started leaves, so an update takes effect.
    if (keepReady && stayReady()) {
        m_view->releaseResources();
        return;
    }
    // A copy that just failed is told to Ambient before the launcher goes.
    if (m_fileBrowser && m_fileBrowser->failedJustNow()) m_lateQuit.start();
    else QCoreApplication::quit();
}

bool LauncherController::stayReady() const
{
    if (qEnvironmentVariableIsSet("TETTEGOUCHE_QUIT_ON_CLOSE")) return false;
    if (!KSharedConfig::openConfig(QStringLiteral("tettegoucherc"))->group(QStringLiteral("Launcher"))
             .readEntry("StayReady", true)) return false;
    const QFileInfo program(QCoreApplication::applicationFilePath());
    return program.exists() && program.lastModified() == m_programModified;
}

// The Context Bar along the top of Search's display, which a full Search
// stops below as it stops above the dock. Each display has its own bar, so a
// display that has none takes none. Read with the dock's band, whenever that
// is read.
void LauncherController::readContextBar()
{
    const auto *screen = placedScreen();
    const quint64 generation = ++m_barGeneration;
    m_barRetried = false;
    if (!screen) {
        m_contextBar = 0;
        return;
    }
    askContextBar(screen->name(), generation, 250);
}

// The bar's shell can be slow to answer, most of all just after sign-in. An
// unanswered read keeps the height already known and asks once more, longer,
// rather than letting a full Search run over the bar. Only an answer, or no
// bar on the bus at all, sets it to none.
void LauncherController::askContextBar(const QString &outputName, quint64 generation, int timeout)
{
    QDBusMessage request = QDBusMessage::createMethodCall(
        QStringLiteral("co.goodinput.ContextBar"), QStringLiteral("/ContextBar"),
        QStringLiteral("co.goodinput.ContextBar"), QStringLiteral("clockExtent"));
    request << outputName;
    auto *watcher = new QDBusPendingCallWatcher(QDBusConnection::sessionBus().asyncCall(request, timeout), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this, watcher, generation, outputName] {
        watcher->deleteLater();
        const QDBusPendingReply<QString> reply = *watcher;
        if (generation != m_barGeneration) return;
        if (reply.isError() && reply.error().type() != QDBusError::ServiceUnknown) {
            if (!m_barRetried) {
                m_barRetried = true;
                askContextBar(outputName, generation, 1500);
            }
            return;
        }
        const int bar = reply.isError() ? 0 : contextBarHeight(reply.value().toUtf8());
        if (bar == m_contextBar) return;
        m_contextBar = bar;
        Q_EMIT guestChanged();
    });
}

void LauncherController::readDockBand()
{
    readContextBar();
    const auto *screen = placedScreen();
    if (!screen) {
        m_dockBand = 0;
        return;
    }
    // One dock answers on the bus for the display it presents; the others are
    // its copies, so a display it does not answer for takes the same band.
    // A display it answers for as not presenting there has none: Search
    // fills down to the screen's edge.
    const quint64 generation = ++m_dockGeneration;
    const auto ask = [](const QString &outputName) {
        QDBusMessage request = bottomSurfaceMethod(QStringLiteral("dockExtent"));
        request << outputName;
        return QDBusConnection::sessionBus().asyncCall(request, 250);
    };
    const auto settle = [this, generation](int band) {
        if (generation != m_dockGeneration || band == m_dockBand) return;
        m_dockBand = band;
        Q_EMIT guestChanged();
    };
    auto *here = new QDBusPendingCallWatcher(ask(screen->name()), this);
    connect(here, &QDBusPendingCallWatcher::finished, this, [this, here, ask, settle] {
        here->deleteLater();
        const QDBusPendingReply<QString> reply = *here;
        const QByteArray payload = reply.isError() ? QByteArray() : reply.value().toUtf8();
        if (payload.isEmpty()) {
            settle(0);
            return;
        }
        const int band = dockBandHeight(payload);
        if (band != 0 || isDockExtent(payload)) {
            settle(band);
            return;
        }
        auto *any = new QDBusPendingCallWatcher(ask(QString()), this);
        connect(any, &QDBusPendingCallWatcher::finished, this, [any, settle] {
            any->deleteLater();
            const QDBusPendingReply<QString> elsewhere = *any;
            settle(elsewhere.isError() ? 0 : dockBandHeight(elsewhere.value().toUtf8()));
        });
    });
}

void LauncherController::floatOn(const QString &outputName)
{
    if (outputName.isEmpty()) return;
    for (QScreen *screen : QGuiApplication::screens()) {
        if (screen->name() != outputName) continue;
        placeOn(screen);
        return;
    }
}

void LauncherController::placeOn(QScreen *screen)
{
    m_screen = screen;
    m_view->setScreen(screen);
    if (auto *surface = LayerShellQt::Window::get(m_view)) surface->setScreen(screen);
    // The whole display, where it sits: a window left at the origin is taken
    // by Qt for whichever display is there.
    m_view->setGeometry(screen->geometry());
}

QScreen *LauncherController::placedScreen() const
{
    return m_screen ? m_screen.data() : m_view->screen();
}

void LauncherController::askGuest()
{
    m_guestMode = false;
    if (!m_guestAllowed) {
        present();
        return;
    }
    m_guestWait.start();
    // An answer still on its way, asked by an open closed before it came,
    // answers this open too: a second ask would cross with it.
    if (m_guestAsking) return;
    m_guestAsking = true;
    const quint64 generation = m_guestGeneration;
    const auto answered = [this, generation](QDBusPendingCallWatcher *watcher) {
        watcher->deleteLater();
        return generation == m_guestGeneration;
    };
    // Kadunce knows the launcher by its own connection's name. Its answer is
    // heard however late it comes, so a place it made is always given back.
    const auto begin = [this, answered] {
        auto *watcher = new QDBusPendingCallWatcher(Kadunce::ask(QStringLiteral("beginLauncherGuest"),
            {QDBusConnection::sessionBus().baseService()}), this);
        connect(watcher, &QDBusPendingCallWatcher::finished, this, [this, watcher, answered] {
            if (!answered(watcher)) return;
            m_guestAsking = false;
            const QDBusPendingReply<QString> reply = *watcher;
            takeGuest(reply.isError() ? QByteArray() : reply.value().toUtf8());
        });
    };
    // Only launcher-guest protocol 3 is spoken.
    if (m_guestProtocol == 3) {
        begin();
        return;
    }
    auto *watcher = new QDBusPendingCallWatcher(
        Kadunce::ask(QStringLiteral("launcherGuestProtocolVersion"), {}, 350), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this, watcher, answered, begin] {
        if (!answered(watcher)) return;
        const QDBusPendingReply<int> reply = *watcher;
        if (!reply.isError()) m_guestProtocol = reply.value();
        if (m_guestProtocol == 3 && m_opening) {
            begin();
            return;
        }
        m_guestAsking = false;
        takeGuest({});
    });
}

void LauncherController::takeGuest(const QByteArray &answer)
{
    QJsonParseError error;
    const QJsonDocument document = QJsonDocument::fromJson(answer, &error);
    const QJsonObject root = document.object();
    const QJsonObject card = root.value(QStringLiteral("card")).toObject();
    const bool accepted = error.error == QJsonParseError::NoError
        && root.value(QStringLiteral("protocol")).toInt() == 3
        && root.value(QStringLiteral("accepted")).toBool();
    if (!m_opening) {
        // Closed, or shown on its own, before Kadunce answered: the place it
        // made in Spread is given back.
        if (accepted) Kadunce::tell(QStringLiteral("endLauncherGuest"));
        return;
    }
    if (!accepted || card.isEmpty()) {
        if (accepted) Kadunce::tell(QStringLiteral("endLauncherGuest"));
        // Declined, Kadunce may name the display the person is working
        // on; the launcher floats there.
        else if (error.error == QJsonParseError::NoError)
            floatOn(root.value(QStringLiteral("output")).toString());
        present();
        return;
    }
    m_guestMode = true;

    const QString outputName =
        root.value(QStringLiteral("output")).toString();
    QScreen *guestScreen = nullptr;
    for (QScreen *screen : QGuiApplication::screens()) {
        if (screen->name() == outputName) {
            guestScreen = screen;
            break;
        }
    }
    if (!guestScreen) {
        endGuestLease();
        present();
        return;
    }

    placeOn(guestScreen);
    const QRect globalCard(
        card.value(QStringLiteral("x")).toInt(),
        card.value(QStringLiteral("y")).toInt(),
        card.value(QStringLiteral("width")).toInt(),
        card.value(QStringLiteral("height")).toInt());
    m_guestRect = globalCard.translated(
        -guestScreen->geometry().topLeft());
    m_compactGuestRect = m_guestRect;
    const auto active = root.value(QStringLiteral("active")).toObject();
    m_activeGuestRect = QRect(active.value(QStringLiteral("x")).toInt(),
        active.value(QStringLiteral("y")).toInt(),
        active.value(QStringLiteral("width")).toInt(),
        active.value(QStringLiteral("height")).toInt()).translated(-guestScreen->geometry().topLeft());
    m_guestExpansionSupported = root.value(QStringLiteral("presentationCapability")).toInt() == 1
        && QRect(QPoint(), guestScreen->geometry().size()).contains(m_activeGuestRect);
    if (!m_guestRect.isValid()) {
        endGuestLease();
        present();
        return;
    }
    constexpr int InputSafety = 16;
    m_view->setMask(QRegion(m_guestRect.adjusted(
        -InputSafety, -InputSafety, InputSafety, InputSafety)));
    m_guestMode = true;
    present();
}

void LauncherController::endGuestLease()
{
    ++m_presentationGeneration;
    m_drawerExpanded = false;
    m_requestedExpanded = false;
    m_expansionChosen = false;
    if (!m_guestMode) return;
    Kadunce::tell(QStringLiteral("endLauncherGuest"));
    m_guestMode = false;
    m_view->setMask(QRegion());
    Q_EMIT guestChanged();
}

void LauncherController::takeContext(bool answered, const QString &payload)
{
    if (answered && m_context.update(payload)) {
        m_contextFromKadunce = true;
    } else {
        m_contextFromKadunce = false;
        if (m_openWindows && m_openWindows->available()) m_context.update(m_openWindows->context());
        else m_context.clear();
    }
    Q_EMIT contextChanged();
}

void LauncherController::refreshContextBlocking()
{
    ++m_contextGeneration;
    m_contextPending = false;
    const QDBusReply<QString> reply = Kadunce::call(QStringLiteral("workspaceContext"), {}, 500);
    takeContext(reply.isValid(), reply.isValid() ? reply.value() : QString());
}

void LauncherController::refreshContext()
{
    const auto generation = ++m_contextGeneration;
    m_contextPending = true;
    auto *watcher = new QDBusPendingCallWatcher(Kadunce::ask(QStringLiteral("workspaceContext")), this);
    connect(watcher, &QDBusPendingCallWatcher::finished,
            this, [this, watcher, generation]() {
        watcher->deleteLater();
        if (generation != m_contextGeneration) return;
        m_contextPending = false;
        const QDBusPendingReply<QString> reply = *watcher;
        takeContext(!reply.isError(), reply.isError() ? QString() : reply.value());
    });
}
