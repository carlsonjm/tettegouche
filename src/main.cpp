/*
    SPDX-FileCopyrightText: 2026 Jared Carlson
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "WorkspaceContext.h"
#include "ApplicationCatalog.h"
#include "FileBrowser.h"
#include "FileDetails.h"
#include "FileThumbnails.h"
#include "TransferActivityBridge.h"
#include "OmniResults.h"
#include "RelatedInfo.h"
#include "NotesDoor.h"
#include "QuickNote.h"
#include "GenieChat.h"
#include "ProductName.h"

#include <memory>
#include "RecentUse.h"
#include "ScreenShareProvider.h"
#include <KIO/ApplicationLauncherJob>
#include <KIO/OpenUrlJob>
#include <KLocalizedString>

#include <KRunner/ResultsModel>
#include "RunnerIdentity.h"
#include <KRunner/RunnerManager>
#include <KService/KService>
#include <KService/KApplicationTrader>
#include <KShell>
#include <LayerShellQt/Window>

#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QDBusReply>
#include <QDBusServiceWatcher>
#include <QCursor>
#include <QDir>
#include <QDesktopServices>
#include <QDrag>
#include <QIcon>
#include <QProcess>
#include <QMimeDatabase>
#include <QUrlQuery>
#include <QFileInfo>
#include <QGuiApplication>
#include <QInputMethod>
#include <QJsonDocument>
#include <QJsonObject>
#include <QLoggingCategory>
#include <QLockFile>
#include <QQmlEngine>
#include <QQuickView>
#include <QRegion>
#include <QScreen>
#include <QTimer>
#include <QUuid>

#include <algorithm>
#include <functional>

namespace
{
constexpr auto ServiceName = "io.github.carlsonjm.Tettegouche";

QStringList applicationRunnerIds()
{
    QStringList ids;
    const auto metadata = KRunner::RunnerManager::runnerMetaDataList();
    for (const KPluginMetaData &plugin : metadata) {
        if (searchTier(plugin.pluginId()) < 3) {
            ids.append(plugin.pluginId());
        }
    }
    ids.removeDuplicates();
    return ids;
}

QScreen *preferredScreen()
{
    if (QScreen *screen = QGuiApplication::screenAt(QCursor::pos())) {
        return screen;
    }
    return QGuiApplication::primaryScreen();
}

void configureSurface(QQuickView *view, QScreen *screen)
{
    view->setScreen(screen);
    view->setColor(Qt::transparent);
    view->setResizeMode(QQuickView::SizeRootObjectToView);
    view->resize(screen->geometry().size());

    auto *surface = LayerShellQt::Window::get(view);
    surface->setScreen(screen);
    surface->setScope(QStringLiteral("tettegouche-launcher"));
    // Top, not overlay: KWin keeps the on-screen keyboard in the overlay layer,
    // and a later overlay surface stacks above it and takes every touch meant
    // for the keys. Opening activates the launcher, which takes a full-screen
    // window out of the layer above, so nothing covers the search either.
    surface->setLayer(LayerShellQt::Window::LayerTop);
    LayerShellQt::Window::Anchors anchors;
    anchors.setFlag(LayerShellQt::Window::AnchorTop);
    anchors.setFlag(LayerShellQt::Window::AnchorBottom);
    anchors.setFlag(LayerShellQt::Window::AnchorLeft);
    anchors.setFlag(LayerShellQt::Window::AnchorRight);
    surface->setAnchors(anchors);
    surface->setDesiredSize(QSize(0, 0));
    surface->setExclusiveZone(-1);
    surface->setKeyboardInteractivity(
        LayerShellQt::Window::KeyboardInteractivityExclusive);
    surface->setActivateOnShow(true);
}
}

// org.freedesktop.FileManager1, which a desktop asks to show folders and
// files, as in another application's "Show in folder". Each request goes to
// answer by the name of the launcher's own method for it.
class FileManagerService final : public QObject
{
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.freedesktop.FileManager1")
public:
    using Answer = std::function<void(const QString &method, const QStringList &locations)>;
    explicit FileManagerService(Answer answer, QObject *parent = nullptr)
        : QObject(parent), m_answer(std::move(answer)) {}
public Q_SLOTS:
    Q_SCRIPTABLE void ShowFolders(const QStringList &uris, const QString &) { m_answer(QStringLiteral("showFolders"), uris); }
    Q_SCRIPTABLE void ShowItems(const QStringList &uris, const QString &) { m_answer(QStringLiteral("revealItems"), uris); }
    Q_SCRIPTABLE void ShowItemProperties(const QStringList &uris, const QString &) { m_answer(QStringLiteral("showItemProperties"), uris); }
private:
    Answer m_answer;
};

class LauncherController final : public QObject
{
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "io.github.carlsonjm.Tettegouche")
    Q_PROPERTY(bool contextAvailable READ contextAvailable
               NOTIFY contextChanged)
    Q_PROPERTY(bool guestMode READ guestMode NOTIFY guestChanged)
    Q_PROPERTY(bool drawerExpanded READ drawerExpanded NOTIFY guestChanged)
    Q_PROPERTY(int guestX READ guestX NOTIFY guestChanged)
    Q_PROPERTY(int guestY READ guestY NOTIFY guestChanged)
    Q_PROPERTY(int guestWidth READ guestWidth NOTIFY guestChanged)
    Q_PROPERTY(int guestHeight READ guestHeight NOTIFY guestChanged)
    Q_PROPERTY(QRect availableArea READ availableArea NOTIFY guestChanged)
    Q_PROPERTY(int relatedRevision READ relatedRevision NOTIFY relatedChanged)
    // Whether Shuffle's dock answered when Search last asked what it pins.
    Q_PROPERTY(bool dockPresent READ dockPresent NOTIFY pinnedChanged)

public:
    LauncherController(QQuickView *view,
                       KRunner::RunnerManager *runnerManager,
                       OmniResults *results,
                       ApplicationCatalog *catalog,
                       bool guestAllowed,
                       QObject *parent = nullptr)
        : QObject(parent)
        , m_view(view)
        , m_runnerManager(runnerManager)
        , m_results(results)
        , m_catalog(catalog)
        , m_guestAllowed(guestAllowed)
    {
        connect(&m_related, &RelatedInfo::changed, this, [this]() { ++m_relatedRevision; Q_EMIT relatedChanged(); });
        m_lateQuit.setSingleShot(true);
        m_lateQuit.setInterval(1000);
        connect(&m_lateQuit, &QTimer::timeout, qApp, &QGuiApplication::quit);
        auto bus = QDBusConnection::sessionBus();
        bus.connect(QStringLiteral("org.kde.KWin"), QStringLiteral("/Kadunce"),
                    QStringLiteral("co.goodinput.Kadunce"), QStringLiteral("workspaceContextChanged"),
                    this, SLOT(workspaceUpdated()));
        bus.connect(QStringLiteral("org.kde.KWin"), QStringLiteral("/Kadunce"),
                    QStringLiteral("co.goodinput.Kadunce"), QStringLiteral("bridgeUnavailable"),
                    this, SLOT(bridgeLost()));
        bus.connect(QStringLiteral("co.goodinput.BottomSurface"), QStringLiteral("/BottomSurface"),
                    QStringLiteral("co.goodinput.BottomSurface"), QStringLiteral("pinnedApplicationsChanged"),
                    this, SLOT(askPinned()));
        auto *owner = new QDBusServiceWatcher(QStringLiteral("org.kde.KWin"), bus,
            QDBusServiceWatcher::WatchForOwnerChange, this);
        connect(owner, &QDBusServiceWatcher::serviceOwnerChanged, this,
                [this]() { bridgeLost(); });
        for (QScreen *screen : QGuiApplication::screens()) {
            const auto boundsChanged = [this, screen] {
                if (screen != m_view->screen()) return;
                const bool expanded = m_requestedExpanded;
                endGuestLease();
                m_requestedExpanded = expanded;
                m_drawerExpanded = expanded && tabletSurface();
                m_view->resize(screen->geometry().size());
                Q_EMIT guestChanged();
            };
            connect(screen, &QScreen::geometryChanged, this, boundsChanged);
            connect(screen, &QScreen::availableGeometryChanged, this, boundsChanged);
        }
    }

    bool contextAvailable() const { return m_context.available(); }
    int relatedRevision() const { return m_relatedRevision; }
    bool dockPresent() const { return m_dockPresent; }
    Q_INVOKABLE bool catalogPinned(int row) const
    {
        return m_catalog && m_pinned.contains(m_catalog->applicationId(row));
    }
    // Asks Shuffle's dock to pin an application from Apps, or to unpin it.
    // The dock does it as its own sheet does and says so with its change
    // signal; until then Search holds what it asked for.
    Q_INVOKABLE void pinCatalog(int row, bool pin)
    {
        const QString id = m_catalog ? m_catalog->applicationId(row) : QString();
        if (id.isEmpty() || !m_dockPresent) return;
        QDBusMessage request = QDBusMessage::createMethodCall(
            QStringLiteral("co.goodinput.BottomSurface"), QStringLiteral("/BottomSurface"),
            QStringLiteral("co.goodinput.BottomSurface"),
            pin ? QStringLiteral("pinApplication") : QStringLiteral("unpinApplication"));
        request << id;
        QDBusConnection::sessionBus().asyncCall(request, 500);
        if (pin) m_pinned.insert(id);
        else m_pinned.remove(id);
        if (m_recent) m_recent->refilter();
        Q_EMIT pinnedChanged();
    }
    Q_INVOKABLE QString relatedOptionLabel(int row) {
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
    Q_INVOKABLE QVariantList relatedItems(int row) {
        const auto match = m_results->getQueryMatch(m_results->index(row, 0));
        if (runnerApplicationId(match) == QStringLiteral("org.kde.kdeconnect.app.desktop"))
            return m_related.items(QStringLiteral("connect"));
        if (!match.runner() || !match.runner()->id().contains(QStringLiteral("systemsettings"))) return {};
        return m_related.items(RelatedInfo::keyForSetting(match.id()));
    }
    bool guestMode() const { return m_guestMode; }
    bool drawerExpanded() const { return m_drawerExpanded; }
    bool tabletSurface() const {
        return m_view->screen() && m_view->screen()->name().startsWith(QStringLiteral("eDP"), Qt::CaseInsensitive);
    }
    Q_INVOKABLE void setDrawerExpanded(bool expanded)
    {
        const quint64 generation = ++m_presentationGeneration;
        m_requestedExpanded = expanded;
        if (!m_guestMode) {
            m_drawerExpanded = expanded && tabletSurface();
            Q_EMIT guestChanged();
            return;
        }
        if (!m_guestExpansionSupported || !m_activeGuestRect.isValid()) {
            endGuestLease();
            m_requestedExpanded = expanded;
            m_drawerExpanded = expanded && tabletSurface();
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
                QDBusMessage request = guestMethod(QStringLiteral("setLauncherGuestExpanded"));
                request.setArguments({false});
                QDBusConnection::sessionBus().asyncCall(request);
                m_view->setMask(QRegion(m_guestRect.adjusted(-16, -16, 16, 16)));
            });
            return;
        }
        QDBusMessage request = guestMethod(QStringLiteral("setLauncherGuestExpanded"));
        request.setArguments({true});
        auto *watcher = new QDBusPendingCallWatcher(
            QDBusConnection::sessionBus().asyncCall(request, 700), this);
        connect(watcher, &QDBusPendingCallWatcher::finished, this, [this, watcher, generation] {
            const QDBusPendingReply<bool> reply = *watcher;
            watcher->deleteLater();
            if (generation != m_presentationGeneration || !m_guestMode) return;
            if (reply.isError() || !reply.value()) {
                endGuestLease();
                m_requestedExpanded = true;
                m_drawerExpanded = tabletSurface();
            } else {
                m_drawerExpanded = true;
                // Expanded input ends at the same dock-safe boundary as paint.
                m_view->setMask(QRegion(m_activeGuestRect));
                m_guestRect = m_activeGuestRect;
            }
            Q_EMIT guestChanged();
        });
    }
    int guestX() const { return m_guestRect.x(); }
    int guestY() const { return m_guestRect.y(); }
    int guestWidth() const { return m_guestRect.width(); }
    int guestHeight() const { return m_guestRect.height(); }
    QRect availableArea() const {
        const auto *screen = m_view->screen();
        return screen ? screen->availableGeometry().translated(-screen->geometry().topLeft())
                      : QRect(0, 0, m_view->width(), m_view->height());
    }

    Q_INVOKABLE bool resultIsOpen(int row) const
    {
        const QModelIndex index = m_results->index(row, 0);
        if (searchTier(m_results->getQueryMatch(index)) != 0) return false;
        return index.isValid() && m_context.applicationIsOpen(
            runnerApplicationId(m_results->data(index, KRunner::ResultsModel::QueryMatchRole).value<KRunner::QueryMatch>()),
            m_results->data(index, Qt::DisplayRole).toString());
    }

    Q_INVOKABLE int activateIfOpen(int row)
    {
        refreshContextBlocking();
        const QModelIndex index = m_results->index(row, 0);
        if (!index.isValid()) {
            return false;
        }
        if (searchTier(m_results->getQueryMatch(index)) != 0) return 0;
        const QString windowId = m_context.windowIdForApplication(
            runnerApplicationId(m_results->data(index, KRunner::ResultsModel::QueryMatchRole).value<KRunner::QueryMatch>()),
            m_results->data(index, Qt::DisplayRole).toString());
        if (windowId.isEmpty()) {
            return false;
        }

        QDBusMessage request = QDBusMessage::createMethodCall(
            QStringLiteral("org.kde.KWin"),
            QStringLiteral("/Kadunce"),
            QStringLiteral("co.goodinput.Kadunce"),
            QStringLiteral("activateApplicationWindow"));
        request.setArguments({windowId});
        const QDBusReply<bool> reply = QDBusConnection::sessionBus().call(
            request, QDBus::Block, 500);
        if (reply.isValid() && reply.value()) return 1;
        refreshContextBlocking();
        return m_context.applicationIsOpen(
            runnerApplicationId(m_results->data(index, KRunner::ResultsModel::QueryMatchRole).value<KRunner::QueryMatch>()),
            m_results->data(index, Qt::DisplayRole).toString()) ? -1 : 0;
    }

    Q_INVOKABLE int activateCatalogIfOpen(int row)
    {
        refreshContextBlocking();
        if (!m_catalog) {
            return false;
        }
        const QString windowId = m_context.windowIdForApplication(
            m_catalog->applicationId(row), m_catalog->applicationName(row));
        if (windowId.isEmpty()) {
            return false;
        }
        QDBusMessage request = QDBusMessage::createMethodCall(
            QStringLiteral("org.kde.KWin"),
            QStringLiteral("/Kadunce"),
            QStringLiteral("co.goodinput.Kadunce"),
            QStringLiteral("activateApplicationWindow"));
        request.setArguments({windowId});
        const QDBusReply<bool> reply = QDBusConnection::sessionBus().call(
            request, QDBus::Block, 500);
        if (reply.isValid() && reply.value()) return 1;
        refreshContextBlocking();
        return m_context.applicationIsOpen(m_catalog->applicationId(row), m_catalog->applicationName(row)) ? -1 : 0;
    }

public Q_SLOTS:
    void workspaceUpdated() { refreshContext(); }

    // The applications pinned in Shuffle's dock, which it publishes; with no
    // dock there, none.
    void askPinned()
    {
        const QDBusMessage request = QDBusMessage::createMethodCall(
            QStringLiteral("co.goodinput.BottomSurface"), QStringLiteral("/BottomSurface"),
            QStringLiteral("co.goodinput.BottomSurface"), QStringLiteral("pinnedApplications"));
        auto *watcher = new QDBusPendingCallWatcher(QDBusConnection::sessionBus().asyncCall(request, 500), this);
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

    void bridgeLost()
    {
        ++m_presentationGeneration;
        m_drawerExpanded = m_requestedExpanded && tabletSurface();
        m_launchToken.clear();
        ++m_contextGeneration;
        m_context.clear();
        m_guestMode = false;
        m_guestRect = {};
        m_view->setMask(QRegion());
        Q_EMIT contextChanged();
        Q_EMIT guestChanged();
        Q_EMIT guestBridgeLost();
    }

    Q_SCRIPTABLE void toggle()
    {
        if (m_view->isVisible()) close();
        else open();
    }

    // A drive plugged in, chosen in Ambient: Files opens it, mounting it first.
    Q_SCRIPTABLE void showDrive(const QString &id)
    {
        if (!m_fileBrowser) { open(); return; }
        showFiles();
        m_fileBrowser->openDrive(id);
    }

    Q_SCRIPTABLE void showFile(const QString &file)
    {
        const QFileInfo info(file);
        if (!m_fileBrowser || !info.isAbsolute() || !info.isFile() || info.isSymLink()) { open(); return; }
        open();
        m_fileBrowser->reveal({info.absoluteFilePath()});
        Q_EMIT filesRequested();
    }

    // Another application asks to see a folder, as it would ask a file
    // manager: a local folder opens in Files.
    Q_SCRIPTABLE void showFolder(const QString &location) { showFolders({location}); }
    // The first folder opens in the tab shown and each other in a tab of its
    // own. Recent opens Files' Recent, and a phone plugged in opens as its drive
    // does when nothing else was asked for; places Files does not browse, such
    // as Trash or a network share, go on to Dolphin.
    Q_SCRIPTABLE void showFolders(const QStringList &locations)
    {
        QStringList folders, phones;
        QList<QUrl> elsewhere;
        bool recent = false;
        for (const auto &location : locations) {
            const QUrl url = QUrl::fromUserInput(location, QString(), QUrl::AssumeLocalFile);
            const auto phone = m_fileBrowser ? m_fileBrowser->phoneForAddress(url) : QString();
            if (url.isLocalFile()) folders.append(QDir::cleanPath(QFileInfo(url.toLocalFile()).absoluteFilePath()));
            else if (url.scheme() == QLatin1String("recentlyused")) recent = true;
            else if (!phone.isEmpty()) phones.append(phone);
            else if (url.isValid()) elsewhere.append(url);
        }
        if (!elsewhere.isEmpty()) handOn(elsewhere);
        if (!m_fileBrowser || (folders.isEmpty() && !recent && phones.isEmpty())) return;
        showFiles();
        if (recent) m_fileBrowser->navigate(FileBrowser::recentLocation());
        for (int i = 0; i < folders.size(); ++i) {
            if (i == 0 && !recent) m_fileBrowser->navigate(folders[i]);
            else m_fileBrowser->openTab(folders[i]);
        }
        if (folders.isEmpty() && !recent) m_fileBrowser->openDrive(phones.first());
    }
    // Items shown chosen in their folder, as "Show in folder" asks; any outside
    // the first one's folder are left out.
    Q_SCRIPTABLE void revealItems(const QStringList &locations) { reveal(locations, false); }
    // The same, with the first one's Properties open.
    Q_SCRIPTABLE void showItemProperties(const QStringList &locations) { reveal(locations, true); }

    // Meta+G opens Apps and Meta+E Files; the drawer already
    // open closes the launcher instead.
    Q_SCRIPTABLE void openDrawer(const QString &drawer)
    {
        if (!m_view->isVisible()) open();
        if (drawer == QLatin1String("apps") || drawer == QLatin1String("files"))
            Q_EMIT drawerRequested(drawer);
    }

    Q_SCRIPTABLE void open()
    {
        m_quitAfterFiles=false;
        m_lateQuit.stop();
        m_launchToken.clear();
        endGuestLease();
        tryBeginGuest();
        refreshContext();
        m_runnerManager->setupMatchSession();
        m_results->setQueryString(QString());
        if (m_recent) {
            m_recent->setWithheld(!m_shares.activities().isEmpty());
            m_recent->refresh();
        }
        askPinned();
        if (m_notes) m_notes->refresh();
        m_view->show();
        m_view->requestActivate();
        Q_EMIT opened();
    }

    Q_INVOKABLE void close()
    {
        endGuestLease();
        m_results->clear();
        m_runnerManager->matchSessionComplete();
        m_view->hide();
        finishOrDeferQuit();
    }

    // Files carried past the sheet's edge leave as a drag any application can
    // take, offered only as a copy.
    Q_INVOKABLE void carryOut(const QStringList &paths, const QRectF &sheet)
    {
        if (m_carrying || !m_fileBrowser) return;
        QMimeData *mime = m_fileBrowser->carriedFiles(paths);
        if (!mime) return;
        // KDE's document portal lets a sandboxed application read them too.
        KUrlMimeData::exportUrlsToPortal(mime);
        const QIcon icon = QIcon::fromTheme(QMimeDatabase().mimeTypeForFile(paths.first()).iconName(),
            QIcon::fromTheme(QStringLiteral("text-x-generic")));
        carry(mime, icon, sheet);
    }

    // An application carried past its tile leaves as its desktop file, which
    // Shuffle's dock pins where it is let go, as it pins one from any other
    // launcher.
    Q_INVOKABLE void carryApplication(int row, const QRectF &sheet)
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

    // A folder carried from Apps leaves as its applications' desktop files,
    // which any launcher pins, with the folder's name beside them, which
    // Shuffle's dock reads to pin them as one folder.
    Q_INVOKABLE void carryFolder(int row, const QRectF &sheet)
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

    // Starts a carry while the press that began it is still held, which the
    // compositor requires.
    void carry(QMimeData *mime, const QIcon &icon, const QRectF &sheet)
    {
        m_carrying = true;
        // Standalone, the launcher's surface covers the display so a press
        // outside the sheet can close it. Carrying, that cover would take
        // the drop meant for the windows beside the sheet. A changed input
        // region reaches the compositor only with the next frame, so each
        // change asks for one; without it the cover stayed away after a drop.
        const bool uncovered = !m_guestMode;
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

    Q_INVOKABLE void finishLaunch()
    {
        // Runner actions may finish their launch asynchronously. Hide the
        // launcher immediately, but keep its event loop and match session
        // alive long enough for Plasma to dispatch the selected action. A
        // folder found by search comes back to this launcher's Files, which
        // may show it before then; it stays.
        endGuestLease();
        m_view->hide();
        QTimer::singleShot(750, this, [this]() {
            if (m_view->isVisible()) return;
            m_runnerManager->matchSessionComplete();
            finishOrDeferQuit();
        });
    }

    // A launcher started only to answer as the file manager leaves if no
    // request has shown it.
    void leaveIfUnused()
    {
        if (!m_view->isVisible()) finishOrDeferQuit();
    }

    Q_INVOKABLE void updateGuestDrag(double horizontalDelta)
    {
        if (!m_guestMode) {
            return;
        }
        QDBusMessage request = guestMethod(
            QStringLiteral("updateLauncherGuest"));
        request.setArguments({horizontalDelta});
        QDBusConnection::sessionBus().asyncCall(request);
    }

    Q_INVOKABLE bool finishGuestDrag(double horizontalDelta)
    {
        if (!m_guestMode) {
            return false;
        }
        QDBusMessage request = guestMethod(
            QStringLiteral("finishLauncherGuest"));
        request.setArguments({horizontalDelta});
        const QDBusReply<bool> reply = QDBusConnection::sessionBus().call(
            request, QDBus::Block, 500);
        return reply.isValid() && reply.value();
    }

    Q_INVOKABLE bool beginGuestApplicationLaunch(int row, bool catalog = false)
    {
        if (!m_guestMode) {
            return false;
        }
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

    bool prepareGuestIdentity(QString appId, const QStringList &aliases = {})
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
        QDBusMessage request = guestMethod(QStringLiteral("prepareLauncherGuestLaunch"));
        m_launchToken = QUuid::createUuid().toString(QUuid::WithoutBraces);
        request.setArguments({identities, m_launchToken});
        const QDBusReply<bool> reply = QDBusConnection::sessionBus().call(
            request,
            QDBus::Block, 500);
        const bool accepted = reply.isValid() && reply.value();
        if (!accepted) m_launchToken.clear();
        return accepted;
    }

    // The notes application's board, awaited in Spread as any launch from
    // Search is, so its window takes Search's place.
    Q_INVOKABLE bool beginGuestNotesLaunch()
    {
        return prepareGuestIdentity(QString::fromLatin1(NotesDoor::ApplicationId));
    }

    // The assistant's full window, awaited the same way.
    Q_INVOKABLE bool beginGuestGenieLaunch()
    {
        return prepareGuestIdentity(QString::fromLatin1(GenieChat::ApplicationId));
    }

    Q_INVOKABLE void cancelGuestApplicationLaunch()
    {
        m_launchToken.clear();
        if (!m_guestMode) {
            return;
        }
        QDBusConnection::sessionBus().asyncCall(
            guestMethod(QStringLiteral("cancelLauncherGuestLaunch")));
    }

    Q_INVOKABLE void showInputMethod()
    {
        if (QInputMethod *inputMethod = QGuiApplication::inputMethod()) {
            inputMethod->show();
        }
    }

    Q_INVOKABLE bool searchWeb(const QString &query)
    {
        if (query.trimmed().isEmpty() || m_results->querying()
            || m_results->rowCount() != 0) return false;
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
                const QString name = QFileInfo(program).fileName().toLower();
                if (name == QStringLiteral("zen") || name == QStringLiteral("firefox")
                    || name == QStringLiteral("librewolf") || name == QStringLiteral("floorp")) {
                    args.removeIf([](const QString &arg) { return arg.startsWith(QLatin1Char('%')); });
                    args << QStringLiteral("--new-tab") << url.toString(QUrl::FullyEncoded);
                    opened = QProcess::startDetached(program, args);
                }
            }
        }
        if (!opened) opened = QDesktopServices::openUrl(url);
        if (!opened) return false;
        if (m_launchToken.isEmpty()) finishLaunch();
        return true;
    }

    Q_INVOKABLE bool beginGuestWebLaunch()
    {
        const auto browser = KApplicationTrader::preferredService(QStringLiteral("x-scheme-handler/https"));
        if (!browser) return false;
        const auto args = KShell::splitArgs(browser->exec());
        const auto executable = args.isEmpty() ? QString() : QFileInfo(args.first()).fileName();
        return prepareGuestIdentity(browser->storageId(), {executable});
    }

    Q_INVOKABLE void completeGuestHandoff()
    {
        m_guestMode = false;
        m_view->hide();
        QTimer::singleShot(340, this, [this]() {
            finishOrDeferQuit();
        });
    }

    Q_SCRIPTABLE void dismissGuest()
    {
        m_guestMode = false;
        m_view->hide();
        finishOrDeferQuit();
    }

    Q_SCRIPTABLE void completeGuestLaunch(const QString &requestToken)
    {
        if (m_guestMode && !m_launchToken.isEmpty() && requestToken == m_launchToken) {
            m_launchToken.clear();
            Q_EMIT guestLaunchReady();
        }
    }

    Q_SCRIPTABLE void completeGuestNavigation(int slot)
    {
        if (m_guestMode && slot != 0) {
            Q_EMIT guestNavigationReady(slot);
        }
    }

Q_SIGNALS:
    void filesRequested();
    void drawerRequested(const QString &drawer);
    void relatedChanged();
    void pinnedChanged();
    void opened();
    void contextChanged();
    void guestChanged();
    void guestLaunchReady();
    void guestNavigationReady(int slot);
    void guestBridgeLost();

public:
    void setFileBrowser(FileBrowser *browser) {
        m_fileBrowser=browser;
        connect(browser,&FileBrowser::operationChanged,this,[this] {
            if (m_quitAfterFiles && !m_fileBrowser->working()) finishOrDeferQuit();
        });
        // A copy that meets a name already taken waits for an answer; the
        // launcher comes back to Files to ask it rather than wait unseen.
        connect(browser,&FileBrowser::questionChanged,this,[this] {
            if (!m_view->isVisible() && !m_fileBrowser->question().isEmpty()) showFiles();
        });
    }
    void setNotesDoor(NotesDoor *notes) { m_notes = notes; }
    // What was used lately leaves out what the dock holds, what is open and
    // what is hidden from Apps, and is withheld while the screen is shared.
    void setRecentUse(RecentUse *recent) {
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
    // A recent application, or a recent file's usual one, is awaited as a card
    // as any launch from Search is.
    Q_INVOKABLE bool beginGuestRecentLaunch(int row)
    {
        return m_recent ? prepareGuestIdentity(m_recent->applicationFor(row)) : false;
    }
private:
    void showFiles()
    {
        if (!m_view->isVisible()) open();
        Q_EMIT filesRequested();
    }
    void reveal(const QStringList &locations, bool properties)
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
        m_fileBrowser->reveal(paths, properties);
    }
    // Places Files does not browse open in Dolphin, KDE's file manager.
    void handOn(const QList<QUrl> &urls)
    {
        const auto dolphin = KService::serviceByDesktopName(QStringLiteral("org.kde.dolphin"));
        if (!dolphin) {
            if (!m_fileBrowser) return;
            showFiles();
            m_fileBrowser->setStatus(i18n("Files cannot open %1, and Dolphin is not installed.", urls.first().toDisplayString()));
            return;
        }
        auto *job = new KIO::ApplicationLauncherJob(dolphin);
        job->setUrls(urls);
        connect(job, &KJob::result, this, [this]() { if (!m_view->isVisible()) finishOrDeferQuit(); });
        job->start();
    }
    FileBrowser *m_fileBrowser=nullptr;
    bool m_quitAfterFiles=false;
    // The second a failed copy is given to reach Ambient; reopening stops it.
    QTimer m_lateQuit;
    // Files carried out are offered until the other application takes them.
    bool m_carrying=false;
    void finishOrDeferQuit() {
        m_quitAfterFiles=true;
        if (m_carrying || (m_fileBrowser && m_fileBrowser->working())) return;
        // A copy that just failed is told to Ambient before the launcher goes.
        if (m_fileBrowser && m_fileBrowser->failedJustNow()) m_lateQuit.start();
        else QGuiApplication::quit();
    }
    static QDBusMessage guestMethod(const QString &method)
    {
        return QDBusMessage::createMethodCall(
            QStringLiteral("org.kde.KWin"),
            QStringLiteral("/Kadunce"),
            QStringLiteral("co.goodinput.Kadunce"), method);
    }

    void tryBeginGuest()
    {
        m_guestMode = false;
        m_guestRect = {};
        m_view->setMask(QRegion());

        if (!m_guestAllowed) {
            Q_EMIT guestChanged();
            return;
        }

        const QDBusReply<int> protocol = QDBusConnection::sessionBus().call(
            guestMethod(QStringLiteral("launcherGuestProtocolVersion")),
            QDBus::Block, 350);
        if (!protocol.isValid() || protocol.value() != 3) {
            Q_EMIT guestChanged();
            return;
        }

        QDBusMessage request = guestMethod(
            QStringLiteral("beginLauncherGuest"));
        request.setArguments({QDBusConnection::sessionBus().baseService()});
        const QDBusReply<QString> reply = QDBusConnection::sessionBus().call(
            request, QDBus::Block, 700);
        if (!reply.isValid()) {
            Q_EMIT guestChanged();
            return;
        }

        QJsonParseError error;
        const QJsonDocument document = QJsonDocument::fromJson(
            reply.value().toUtf8(), &error);
        const QJsonObject root = document.object();
        const QJsonObject card = root.value(QStringLiteral("card")).toObject();
        if (error.error != QJsonParseError::NoError
            || root.value(QStringLiteral("protocol")).toInt() != 3
            || !root.value(QStringLiteral("accepted")).toBool()
            || card.isEmpty()) {
            Q_EMIT guestChanged();
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
            Q_EMIT guestChanged();
            return;
        }

        m_view->setScreen(guestScreen);
        LayerShellQt::Window::get(m_view)->setScreen(guestScreen);
        m_view->resize(guestScreen->geometry().size());
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
            Q_EMIT guestChanged();
            return;
        }
        constexpr int InputSafety = 16;
        m_view->setMask(QRegion(m_guestRect.adjusted(
            -InputSafety, -InputSafety, InputSafety, InputSafety)));
        m_guestMode = true;
        Q_EMIT guestChanged();
    }

    void endGuestLease()
    {
        ++m_presentationGeneration;
        m_drawerExpanded = false;
        m_requestedExpanded = false;
        if (!m_guestMode) {
            return;
        }
        QDBusConnection::sessionBus().asyncCall(
            guestMethod(QStringLiteral("endLauncherGuest")));
        m_guestMode = false;
        m_view->setMask(QRegion());
        Q_EMIT guestChanged();
    }

    void refreshContextBlocking()
    {
        ++m_contextGeneration;
        const QDBusMessage request = QDBusMessage::createMethodCall(
            QStringLiteral("org.kde.KWin"),
            QStringLiteral("/Kadunce"),
            QStringLiteral("co.goodinput.Kadunce"),
            QStringLiteral("workspaceContext"));
        const QDBusReply<QString> reply = QDBusConnection::sessionBus().call(
            request, QDBus::Block, 500);
        if (reply.isValid()) {
            m_context.update(reply.value());
        } else {
            m_context.clear();
        }
        Q_EMIT contextChanged();
    }

    void refreshContext()
    {
        const auto generation = ++m_contextGeneration;
        const QDBusMessage request = QDBusMessage::createMethodCall(
            QStringLiteral("org.kde.KWin"),
            QStringLiteral("/Kadunce"),
            QStringLiteral("co.goodinput.Kadunce"),
            QStringLiteral("workspaceContext"));
        auto *watcher = new QDBusPendingCallWatcher(
            QDBusConnection::sessionBus().asyncCall(request), this);
        connect(watcher, &QDBusPendingCallWatcher::finished,
                this, [this, watcher, generation]() {
            watcher->deleteLater();
            if (generation != m_contextGeneration) return;
            const QDBusPendingReply<QString> reply = *watcher;
            if (reply.isError()) {
                m_context.clear();
            } else {
                m_context.update(reply.value());
            }
            Q_EMIT contextChanged();
            watcher->deleteLater();
        });
    }

    QQuickView *m_view;
    KRunner::RunnerManager *m_runnerManager;
    OmniResults *m_results;
    RelatedInfo m_related;
    int m_relatedRevision = 0;
    ApplicationCatalog *m_catalog;
    RecentUse *m_recent = nullptr;
    NotesDoor *m_notes = nullptr;
    QSet<QString> m_pinned;
    bool m_dockPresent = false;
    ScreenShareProvider m_shares{QDBusConnection::sessionBus()};
    WorkspaceContext m_context;
    QRect m_guestRect;
    QRect m_compactGuestRect, m_activeGuestRect;
    bool m_drawerExpanded = false;
    bool m_requestedExpanded = false;
    bool m_guestExpansionSupported = false;
    quint64 m_presentationGeneration = 0;
    bool m_guestMode = false;
    bool m_guestAllowed = true;
    quint64 m_contextGeneration = 0;
    QString m_launchToken;
};

namespace
{
// Asks the running launcher; false when it did not answer.
bool launcherCall(const QString &method, const QVariantList &arguments)
{
    QDBusMessage request = QDBusMessage::createMethodCall(
        QString::fromLatin1(ServiceName), QStringLiteral("/Launcher"),
        QString::fromLatin1(ServiceName), method);
    request.setArguments(arguments);
    return QDBusConnection::sessionBus().call(request, QDBus::Block, 1000).type() != QDBusMessage::ErrorMessage;
}

// Started by D-Bus as the file manager while a launcher already runs: each
// request goes on to it, and this process leaves once nothing has come for a
// few seconds. A launcher that left meanwhile is started again for the request.
int answerForRunningLauncher(QGuiApplication &application)
{
    QTimer idle;
    idle.setSingleShot(true);
    idle.setInterval(3000);
    QObject::connect(&idle, &QTimer::timeout, &application, &QCoreApplication::quit);
    FileManagerService service([&idle](const QString &method, const QStringList &locations) {
        idle.start();
        if (launcherCall(method, {locations}) || locations.isEmpty()) return;
        QStringList arguments;
        if (method == QLatin1String("showFolders")) arguments = {QStringLiteral("--folder"), locations.first()};
        else if (method == QLatin1String("showItemProperties")) arguments = {QStringLiteral("--properties"), locations.first()};
        else arguments = QStringList{QStringLiteral("--reveal")} + locations;
        QProcess::startDetached(QCoreApplication::applicationFilePath(), arguments);
    });
    auto session = QDBusConnection::sessionBus();
    session.registerObject(QStringLiteral("/org/freedesktop/FileManager1"), &service, QDBusConnection::ExportScriptableSlots);
    if (!session.registerService(QStringLiteral("org.freedesktop.FileManager1"))) return 1;
    idle.start();
    return application.exec();
}
}

int main(int argc, char **argv)
{
    if (qEnvironmentVariableIsEmpty("QT_QPA_PLATFORM")) {
        qputenv("QT_QPA_PLATFORM", QByteArrayLiteral("wayland"));
    }

    // KIO's file worker runs in this process and writes a debug line for each
    // file it copies, which on a large copy floods the system journal. Its
    // debug output stays off unless QT_LOGGING_RULES asks for it.
    QLoggingCategory::setFilterRules(QStringLiteral("kf.kio.*.debug=false"));
    QGuiApplication application(argc, argv);
    // The launcher's words, in C++ and in QML through KI18n, come from this catalog.
    KLocalizedString::setApplicationDomain(QByteArrayLiteral("tettegouche"));
    application.setApplicationName(QStringLiteral("tettegouche"));
    application.setDesktopFileName(
        QStringLiteral("io.github.carlsonjm.Tettegouche"));
    application.setOrganizationDomain(QStringLiteral("github.com/carlsonjm"));
    application.setQuitOnLastWindowClosed(false); // a hidden Files job still owns this process
    const QStringList arguments = application.arguments();
    const auto valueAfter = [&arguments](const QString &flag) {
        const int index = arguments.indexOf(flag);
        return index >= 0 ? arguments.value(index + 1) : QString();
    };
    const QString showFile = valueAfter(QStringLiteral("--show-file"));
    const QString drawer = valueAfter(QStringLiteral("--drawer"));
    // A folder another application asks to open, and the items it asks to
    // show, all given after --reveal, or whose Properties it asks for.
    const QString folder = valueAfter(QStringLiteral("--folder"));
    // A drive by its device identifier, to open in Files.
    const QString drive = valueAfter(QStringLiteral("--drive"));
    const QString properties = valueAfter(QStringLiteral("--properties"));
    const int revealIndex = arguments.indexOf(QStringLiteral("--reveal"));
    QStringList reveal = revealIndex >= 0 ? arguments.mid(revealIndex + 1) : QStringList();
    reveal.removeIf([](const QString &argument) { return argument.startsWith(QLatin1String("--")); });
    // Started by D-Bus to answer as the file manager.
    const bool fileManager = arguments.contains(QStringLiteral("--file-manager"));

    const QByteArray runtime = qgetenv("XDG_RUNTIME_DIR");
    QLockFile instanceLock(QString::fromLocal8Bit(runtime)
                           + QStringLiteral("/tettegouche.lock"));
    instanceLock.setStaleLockTime(0);
    if (!instanceLock.tryLock()) {
        if (fileManager) return answerForRunningLauncher(application);
        QString method = QStringLiteral("toggle");
        QVariantList request;
        if (!showFile.isEmpty()) { method = QStringLiteral("showFile"); request = {showFile}; }
        else if (!folder.isEmpty()) { method = QStringLiteral("showFolder"); request = {folder}; }
        else if (!drive.isEmpty()) { method = QStringLiteral("showDrive"); request = {drive}; }
        else if (!reveal.isEmpty()) { method = QStringLiteral("revealItems"); request = {reveal}; }
        else if (!properties.isEmpty()) { method = QStringLiteral("showItemProperties"); request = {QStringList{properties}}; }
        else if (!drawer.isEmpty()) { method = QStringLiteral("openDrawer"); request = {drawer}; }
        // This forwarding process exits immediately: wait for delivery, not an
        // asynchronous call whose connection may disappear before dispatch.
        if (launcherCall(method, request)) return 0;
        // A launcher on its way out lets go of the lock as the call fails; this
        // process then takes its place.
        if (!instanceLock.tryLock(1500)) return 0;
    }

    const QStringList runners = applicationRunnerIds();
    if (runners.isEmpty()) {
        qCritical("The installed-application search provider is unavailable.");
        return 2;
    }

    KRunner::RunnerManager runnerManager;
    runnerManager.setAllowedRunners(runners);
    OmniResults results;
    results.setRunnerManager(&runnerManager);
    results.setLimit(0);
    ApplicationCatalog catalog;
    catalog.setUseReader(&RecentUse::readApplicationUse);
    FileDevices fileDevices;
    FileBrowser fileBrowser;
    fileBrowser.setDevices(&fileDevices);
    fileBrowser.setThumbnailSource([](const QString &path, const QString &mimeType, qint64 modified) {
        return FileThumbnails::covers(mimeType) ? FileThumbnails::source(path, mimeType, modified) : QString();
    });
    fileBrowser.setDetailReader(readMediaDetails);
    const bool guestAllowed =
        !application.arguments().contains(QStringLiteral("--standalone"));

    QScreen *screen = preferredScreen();
    if (!screen) {
        return 1;
    }

    QQuickView view;
    view.setTitle(tettegouche::productName());
    view.engine()->addImageProvider(QStringLiteral("thumbnail"), new FileThumbnails);
    configureSurface(&view, screen);
    LauncherController controller(&view, &runnerManager, &results, &catalog,
                                  guestAllowed);
    controller.setFileBrowser(&fileBrowser);
    // With the setting off, nothing used lately is read or offered.
    const bool offerRecent = !application.arguments().contains(QStringLiteral("--no-recent"));
    RecentUse recent;
    recent.setThumbnails([](const QString &path, const QString &mimeType, qint64 modified) {
        return FileThumbnails::covers(mimeType) ? FileThumbnails::source(path, mimeType, modified) : QString();
    });
    if (offerRecent) controller.setRecentUse(&recent);
    // With the setting off, the Notes door is never offered.
    const bool offerNotes = !application.arguments().contains(QStringLiteral("--no-notes"));
    NotesDoor notes;
    if (offerNotes) controller.setNotesDoor(&notes);
    // Notes found by their words are listed among the results, as Gooseberry
    // answers, only while Notes is offered.
    results.setNotesOffered(offerNotes);
    // The quick note itself, written in Search's window and kept by the notes
    // application; asked for only while Notes is offered.
    std::unique_ptr<QuickNote> quickNote;
    if (offerNotes) quickNote = std::make_unique<QuickNote>();
    // Genie's chat, kept by Split Rock; with the setting off, never offered.
    const bool offerGenie = !application.arguments().contains(QStringLiteral("--no-genie"));
    std::unique_ptr<GenieChat> genie;
    if (offerGenie) genie = std::make_unique<GenieChat>();
    QObject::connect(&application, &QGuiApplication::lastWindowClosed,
                     &controller, &LauncherController::close);
    QObject::connect(&fileBrowser, &FileBrowser::openRequested, &controller,
                     [&fileBrowser, &controller](const QUrl &url) {
        auto *job = new KIO::OpenUrlJob(url);
        job->setRunExecutables(false);
        job->setShowOpenOrExecuteDialog(false);
        QObject::connect(job, &KJob::result, &controller,
                         [&fileBrowser, &controller](KJob *completed) {
            const QString error = completed->error() ? completed->errorString() : QString();
            fileBrowser.finishOpen(error);
            if (!completed->error()) controller.finishLaunch();
        });
        job->start();
    });
    QObject::connect(&fileBrowser, &FileBrowser::openWithRequested, &controller,
                     [&fileBrowser, &controller](const QUrl &url, const QString &applicationId) {
        auto *job = new KIO::ApplicationLauncherJob(KService::serviceByStorageId(applicationId));
        job->setUrls({url});
        QObject::connect(job, &KJob::result, &controller,
                         [&fileBrowser, &controller](KJob *completed) {
            const QString error = completed->error() ? completed->errorString() : QString();
            fileBrowser.finishOpen(error);
            if (!completed->error()) controller.finishLaunch();
        });
        job->start();
    });
    view.setInitialProperties({
        {QStringLiteral("fileBrowser"), QVariant::fromValue(static_cast<QObject *>(&fileBrowser))},
        {QStringLiteral("launcherController"),
         QVariant::fromValue(static_cast<QObject *>(&controller))},
        {QStringLiteral("searchResults"),
         QVariant::fromValue(static_cast<QObject *>(&results))},
        {QStringLiteral("applicationCatalog"),
         QVariant::fromValue(static_cast<QObject *>(&catalog))},
        // What is not offered is passed as null; an empty QVariant would
        // reach QML as undefined, which its "!== null" checks let through.
        {QStringLiteral("recentUse"), QVariant::fromValue<QObject *>(offerRecent ? &recent : nullptr)},
        {QStringLiteral("notesDoor"), QVariant::fromValue<QObject *>(offerNotes ? &notes : nullptr)},
        // The Notes pill can be left off the first screen on its own.
        {QStringLiteral("notesPillShown"),
         !application.arguments().contains(QStringLiteral("--no-notes-pill"))},
        {QStringLiteral("quickNote"), QVariant::fromValue<QObject *>(quickNote.get())},
        {QStringLiteral("genie"), QVariant::fromValue<QObject *>(genie.get())},
    });
    view.setSource(QUrl(QStringLiteral("qrc:/qml/Launcher.qml")));
    if (view.status() == QQuickView::Error) {
        return 3;
    }

    QDBusConnection session = QDBusConnection::sessionBus();
    TransferActivityBridge activities(&fileBrowser);
    session.registerObject(QStringLiteral("/Activities"), &activities,
                           QDBusConnection::ExportAllSlots | QDBusConnection::ExportAllSignals);
    session.registerObject(QStringLiteral("/Launcher"), &controller,
                           QDBusConnection::ExportScriptableSlots);
    session.registerService(QString::fromLatin1(ServiceName));
    // Answering as the file manager is switched on by pointing D-Bus at this
    // launcher; a launcher started any other way leaves it to whoever answers
    // now.
    FileManagerService fileManagerService([&controller](const QString &method, const QStringList &locations) {
        if (method == QLatin1String("showFolders")) controller.showFolders(locations);
        else if (method == QLatin1String("revealItems")) controller.revealItems(locations);
        else if (method == QLatin1String("showItemProperties")) controller.showItemProperties(locations);
    });
    if (fileManager) {
        session.registerObject(QStringLiteral("/org/freedesktop/FileManager1"), &fileManagerService,
                               QDBusConnection::ExportScriptableSlots);
        session.registerService(QStringLiteral("org.freedesktop.FileManager1"));
        QTimer::singleShot(5000, &controller, &LauncherController::leaveIfUnused);
    }

    QTimer::singleShot(0, &controller, [&controller, showFile, drawer, folder, drive, reveal, properties, fileManager] {
        if (!showFile.isEmpty()) controller.showFile(showFile);
        else if (!folder.isEmpty()) controller.showFolder(folder);
        else if (!drive.isEmpty()) controller.showDrive(drive);
        else if (!reveal.isEmpty()) controller.revealItems(reveal);
        else if (!properties.isEmpty()) controller.showItemProperties({properties});
        else if (!drawer.isEmpty()) controller.openDrawer(drawer);
        else if (!fileManager) controller.open();
    });
    const int result = application.exec();
    view.setSource(QUrl());
    return result;
}

#include "main.moc"
