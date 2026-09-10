/*
    SPDX-FileCopyrightText: 2026 Jared Carlson
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "WorkspaceContext.h"
#include "ApplicationCatalog.h"
#include "OmniResults.h"
#include "RelatedInfo.h"

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
#include <QDesktopServices>
#include <QProcess>
#include <QMimeDatabase>
#include <QUrlQuery>
#include <QFileInfo>
#include <QGuiApplication>
#include <QInputMethod>
#include <QJsonDocument>
#include <QJsonObject>
#include <QLockFile>
#include <QQuickView>
#include <QRegion>
#include <QScreen>
#include <QTimer>
#include <QUuid>

#include <algorithm>

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
    surface->setLayer(LayerShellQt::Window::LayerOverlay);
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

class LauncherController final : public QObject
{
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "io.github.carlsonjm.Tettegouche")
    Q_PROPERTY(bool contextAvailable READ contextAvailable
               NOTIFY contextChanged)
    Q_PROPERTY(bool guestMode READ guestMode NOTIFY guestChanged)
    Q_PROPERTY(int guestX READ guestX NOTIFY guestChanged)
    Q_PROPERTY(int guestY READ guestY NOTIFY guestChanged)
    Q_PROPERTY(int guestWidth READ guestWidth NOTIFY guestChanged)
    Q_PROPERTY(int guestHeight READ guestHeight NOTIFY guestChanged)
    Q_PROPERTY(QRect availableArea READ availableArea NOTIFY guestChanged)
    Q_PROPERTY(int relatedRevision READ relatedRevision NOTIFY relatedChanged)

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
        auto bus = QDBusConnection::sessionBus();
        bus.connect(QStringLiteral("org.kde.KWin"), QStringLiteral("/Kadunce"),
                    QStringLiteral("studio.warbler.Kadunce"), QStringLiteral("workspaceContextChanged"),
                    this, SLOT(workspaceUpdated()));
        bus.connect(QStringLiteral("org.kde.KWin"), QStringLiteral("/Kadunce"),
                    QStringLiteral("studio.warbler.Kadunce"), QStringLiteral("bridgeUnavailable"),
                    this, SLOT(bridgeLost()));
        auto *owner = new QDBusServiceWatcher(QStringLiteral("org.kde.KWin"), bus,
            QDBusServiceWatcher::WatchForOwnerChange, this);
        connect(owner, &QDBusServiceWatcher::serviceOwnerChanged, this,
                [this]() { bridgeLost(); });
    }

    bool contextAvailable() const { return m_context.available(); }
    int relatedRevision() const { return m_relatedRevision; }
    Q_INVOKABLE QString relatedOptionLabel(int row) {
        const auto match = m_results->getQueryMatch(m_results->index(row, 0));
        const auto key = RelatedInfo::keyForSetting(match.id());
        const QHash<QString, QString> labels = {
            {QStringLiteral("bluetooth"), tr("Open Bluetooth settings")},
            {QStringLiteral("audio"), tr("Open Sound settings")},
            {QStringLiteral("network"), tr("Open Network settings")},
            {QStringLiteral("display"), tr("Open Display settings")},
            {QStringLiteral("power"), tr("Open Power settings")},
            {QStringLiteral("printers"), tr("Open Printer settings")},
            {QStringLiteral("storage"), tr("Open Device Actions")},
            {QStringLiteral("defaults"), tr("Open Default Applications")},
            {QStringLiteral("nightlight"), tr("Open Night Light settings")},
            {QStringLiteral("connect"), tr("Open KDE Connect")}};
        if (runnerApplicationId(match) == QStringLiteral("org.kde.kdeconnect.app.desktop"))
            return tr("Open KDE Connect");
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
            QStringLiteral("studio.warbler.Kadunce"),
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
            QStringLiteral("studio.warbler.Kadunce"),
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

    void bridgeLost()
    {
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

    Q_SCRIPTABLE void open()
    {
        m_launchToken.clear();
        endGuestLease();
        tryBeginGuest();
        refreshContext();
        m_runnerManager->setupMatchSession();
        m_results->setQueryString(QString());
        m_view->show();
        m_view->requestActivate();
        Q_EMIT opened();
    }

    Q_INVOKABLE void close()
    {
        endGuestLease();
        m_results->clear();
        m_runnerManager->matchSessionComplete();
        QGuiApplication::quit();
    }

    Q_INVOKABLE void finishLaunch()
    {
        // Runner actions may finish their launch asynchronously. Hide the
        // launcher immediately, but keep its event loop and match session
        // alive long enough for Plasma to dispatch the selected action.
        endGuestLease();
        m_view->hide();
        QTimer::singleShot(750, this, [this]() {
            m_runnerManager->matchSessionComplete();
            QGuiApplication::quit();
        });
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
        QTimer::singleShot(340, this, []() {
            QGuiApplication::quit();
        });
    }

    Q_SCRIPTABLE void dismissGuest()
    {
        m_guestMode = false;
        m_view->hide();
        QGuiApplication::quit();
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
    void relatedChanged();
    void opened();
    void contextChanged();
    void guestChanged();
    void guestLaunchReady();
    void guestNavigationReady(int slot);
    void guestBridgeLost();

private:
    static QDBusMessage guestMethod(const QString &method)
    {
        return QDBusMessage::createMethodCall(
            QStringLiteral("org.kde.KWin"),
            QStringLiteral("/Kadunce"),
            QStringLiteral("studio.warbler.Kadunce"), method);
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
            QStringLiteral("studio.warbler.Kadunce"),
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
            QStringLiteral("studio.warbler.Kadunce"),
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
    WorkspaceContext m_context;
    QRect m_guestRect;
    bool m_guestMode = false;
    bool m_guestAllowed = true;
    quint64 m_contextGeneration = 0;
    QString m_launchToken;
};

int main(int argc, char **argv)
{
    if (qEnvironmentVariableIsEmpty("QT_QPA_PLATFORM")) {
        qputenv("QT_QPA_PLATFORM", QByteArrayLiteral("wayland"));
    }

    QGuiApplication application(argc, argv);
    application.setApplicationName(QStringLiteral("tettegouche"));
    application.setDesktopFileName(
        QStringLiteral("io.github.carlsonjm.Tettegouche"));
    application.setOrganizationDomain(QStringLiteral("github.com/carlsonjm"));

    const QByteArray runtime = qgetenv("XDG_RUNTIME_DIR");
    QLockFile instanceLock(QString::fromLocal8Bit(runtime)
                           + QStringLiteral("/tettegouche.lock"));
    instanceLock.setStaleLockTime(0);
    if (!instanceLock.tryLock()) {
        QDBusMessage request = QDBusMessage::createMethodCall(
            QString::fromLatin1(ServiceName), QStringLiteral("/Launcher"),
            QString::fromLatin1(ServiceName), QStringLiteral("open"));
        QDBusConnection::sessionBus().asyncCall(request);
        return 0;
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
    const bool guestAllowed =
        !application.arguments().contains(QStringLiteral("--standalone"));

    QScreen *screen = preferredScreen();
    if (!screen) {
        return 1;
    }

    QQuickView view;
    view.setTitle(QStringLiteral("Tettegouche"));
    configureSurface(&view, screen);
    LauncherController controller(&view, &runnerManager, &results, &catalog,
                                  guestAllowed);
    view.setInitialProperties({
        {QStringLiteral("launcherController"),
         QVariant::fromValue(static_cast<QObject *>(&controller))},
        {QStringLiteral("searchResults"),
         QVariant::fromValue(static_cast<QObject *>(&results))},
        {QStringLiteral("applicationCatalog"),
         QVariant::fromValue(static_cast<QObject *>(&catalog))},
    });
    view.setSource(QUrl(QStringLiteral("qrc:/qml/Launcher.qml")));
    if (view.status() == QQuickView::Error) {
        return 3;
    }

    QDBusConnection session = QDBusConnection::sessionBus();
    session.registerObject(QStringLiteral("/Launcher"), &controller,
                           QDBusConnection::ExportScriptableSlots);
    session.registerService(QString::fromLatin1(ServiceName));

    QTimer::singleShot(0, &controller, &LauncherController::open);
    const int result = application.exec();
    view.setSource(QUrl());
    return result;
}

#include "main.moc"
