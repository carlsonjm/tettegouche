/*
    SPDX-FileCopyrightText: 2026 Jared Carlson
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "WorkspaceContext.h"

#include <KRunner/ResultsModel>
#include <KRunner/RunnerManager>
#include <LayerShellQt/Window>

#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QDBusReply>
#include <QCursor>
#include <QFileInfo>
#include <QGuiApplication>
#include <QJsonDocument>
#include <QJsonObject>
#include <QLockFile>
#include <QQuickView>
#include <QRegion>
#include <QScreen>
#include <QTimer>

#include <algorithm>

namespace
{
constexpr auto ServiceName = "io.github.carlsonjm.Tettegouche";

QStringList applicationRunnerIds()
{
    QStringList ids;
    const auto metadata = KRunner::RunnerManager::runnerMetaDataList();
    for (const KPluginMetaData &plugin : metadata) {
        const QString identity = (plugin.pluginId() + QLatin1Char(' ')
            + plugin.fileName()).toLower();
        if (identity.contains(QStringLiteral("services"))) {
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

public:
    LauncherController(QQuickView *view,
                       KRunner::RunnerManager *runnerManager,
                       KRunner::ResultsModel *results,
                       QObject *parent = nullptr)
        : QObject(parent)
        , m_view(view)
        , m_runnerManager(runnerManager)
        , m_results(results)
    {
    }

    bool contextAvailable() const { return m_context.available(); }
    bool guestMode() const { return m_guestMode; }
    int guestX() const { return m_guestRect.x(); }
    int guestY() const { return m_guestRect.y(); }
    int guestWidth() const { return m_guestRect.width(); }
    int guestHeight() const { return m_guestRect.height(); }

    Q_INVOKABLE bool resultIsOpen(int row) const
    {
        const QModelIndex index = m_results->index(row, 0);
        return index.isValid() && m_context.applicationIsOpen(
            m_results->data(index, KRunner::ResultsModel::IdRole).toString(),
            m_results->data(index, Qt::DisplayRole).toString());
    }

    Q_INVOKABLE bool activateIfOpen(int row)
    {
        if (!m_context.available()) {
            refreshContextBlocking();
        }
        const QModelIndex index = m_results->index(row, 0);
        if (!index.isValid()) {
            return false;
        }
        const QString windowId = m_context.windowIdForApplication(
            m_results->data(index, KRunner::ResultsModel::IdRole).toString(),
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
        return reply.isValid() && reply.value();
    }

public Q_SLOTS:
    Q_SCRIPTABLE void open()
    {
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

    Q_INVOKABLE bool beginGuestApplicationLaunch()
    {
        if (!m_guestMode) {
            return false;
        }
        const QDBusReply<bool> reply = QDBusConnection::sessionBus().call(
            guestMethod(QStringLiteral("prepareLauncherGuestLaunch")),
            QDBus::Block, 500);
        return reply.isValid() && reply.value();
    }

    Q_INVOKABLE void cancelGuestApplicationLaunch()
    {
        if (!m_guestMode) {
            return;
        }
        QDBusConnection::sessionBus().asyncCall(
            guestMethod(QStringLiteral("cancelLauncherGuestLaunch")));
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

    Q_SCRIPTABLE void completeGuestLaunch()
    {
        if (m_guestMode) {
            Q_EMIT guestLaunchReady();
        }
    }

Q_SIGNALS:
    void opened();
    void contextChanged();
    void guestChanged();
    void guestLaunchReady();

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

        const QDBusReply<int> protocol = QDBusConnection::sessionBus().call(
            guestMethod(QStringLiteral("launcherGuestProtocolVersion")),
            QDBus::Block, 350);
        if (!protocol.isValid() || protocol.value() != 2) {
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
            || root.value(QStringLiteral("protocol")).toInt() != 2
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
        const QDBusMessage request = QDBusMessage::createMethodCall(
            QStringLiteral("org.kde.KWin"),
            QStringLiteral("/Kadunce"),
            QStringLiteral("studio.warbler.Kadunce"),
            QStringLiteral("workspaceContext"));
        auto *watcher = new QDBusPendingCallWatcher(
            QDBusConnection::sessionBus().asyncCall(request), this);
        connect(watcher, &QDBusPendingCallWatcher::finished,
                this, [this, watcher]() {
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
    KRunner::ResultsModel *m_results;
    WorkspaceContext m_context;
    QRect m_guestRect;
    bool m_guestMode = false;
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
    KRunner::ResultsModel results;
    results.setRunnerManager(&runnerManager);
    results.setLimit(12);

    QScreen *screen = preferredScreen();
    if (!screen) {
        return 1;
    }

    QQuickView view;
    view.setTitle(QStringLiteral("Tettegouche"));
    configureSurface(&view, screen);
    LauncherController controller(&view, &runnerManager, &results);
    view.setInitialProperties({
        {QStringLiteral("launcherController"),
         QVariant::fromValue(static_cast<QObject *>(&controller))},
        {QStringLiteral("searchResults"),
         QVariant::fromValue(static_cast<QObject *>(&results))},
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
