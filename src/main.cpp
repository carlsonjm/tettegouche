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
#include <QCursor>
#include <QFileInfo>
#include <QGuiApplication>
#include <QLockFile>
#include <QQuickView>
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

    Q_INVOKABLE bool applicationIsOpen(const QString &resultId,
                                       const QString &displayName) const
    {
        return m_context.applicationIsOpen(resultId, displayName);
    }

public Q_SLOTS:
    Q_SCRIPTABLE void open()
    {
        refreshContext();
        m_runnerManager->setupMatchSession();
        m_results->setQueryString(QString());
        m_view->show();
        m_view->requestActivate();
        Q_EMIT opened();
    }

    Q_INVOKABLE void close()
    {
        m_results->clear();
        m_runnerManager->matchSessionComplete();
        QGuiApplication::quit();
    }

    Q_INVOKABLE void finishLaunch()
    {
        // Runner actions may finish their launch asynchronously. Hide the
        // launcher immediately, but keep its event loop and match session
        // alive long enough for Plasma to dispatch the selected action.
        m_view->hide();
        QTimer::singleShot(750, this, [this]() {
            m_runnerManager->matchSessionComplete();
            QGuiApplication::quit();
        });
    }

Q_SIGNALS:
    void opened();
    void contextChanged();

private:
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
    if (session.registerService(QString::fromLatin1(ServiceName))) {
        session.registerObject(QStringLiteral("/Launcher"), &controller,
                               QDBusConnection::ExportScriptableSlots);
    }

    QTimer::singleShot(0, &controller, &LauncherController::open);
    const int result = application.exec();
    view.setSource(QUrl());
    return result;
}

#include "main.moc"
