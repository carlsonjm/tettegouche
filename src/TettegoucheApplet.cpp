/* SPDX-License-Identifier: GPL-2.0-or-later */

#include "TettegoucheApplet.h"
#include "ActivityModel.h"
#include "LauncherKeys.h"
#include "SuiteSettings.h"

#include <KConfigGroup>
#include <KPluginFactory>
#include <QProcess>
#include <QStandardPaths>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusPendingCall>
#include <QQuickItem>
#include <QTimer>
#include <Plasma/Containment>
#include <PlasmaQuick/AppletQuickItem>
#include <LayerShellQt/Window>
#include <QQuickWindow>
#include <QScreen>
#include <QWindow>

#include <algorithm>
#include <cmath>
#include <chrono>

TettegoucheApplet::TettegoucheApplet(QObject *parent,
                                     const KPluginMetaData &data,
                                     const QVariantList &args)
    : Plasma::Applet(parent, data, args)
    , m_process(new QProcess(this))
{
    setHasConfigurationInterface(true);
    openConfigureInSuiteSettings(this, QStringLiteral("search"));

    connect(m_process, &QProcess::stateChanged, this,
            [this] { Q_EMIT launcherActiveChanged(); });

    connect(this, &Plasma::Applet::activated, this, [this] {
        launch(settings().readEntry(QStringLiteral("useKadunce"), true));
    });
    m_keys = LauncherKeys::acquire();
    m_keys->attach(this, [this](const QString &drawer) { openDrawer(drawer); });

    const QString fixture = qEnvironmentVariable("TETTE_AMBIENT_FIXTURE");
    if (fixture == QStringLiteral("transfer-media") || fixture == QStringLiteral("paused")) {
        const QVariantMap transfer{
            {QStringLiteral("id"), QStringLiteral("transfer-1")},
            {QStringLiteral("generation"), 1},
            {QStringLiteral("kind"), QStringLiteral("transfer")},
            {QStringLiteral("state"), QStringLiteral("running")},
            {QStringLiteral("source"), QStringLiteral("Files")},
            {QStringLiteral("icon"), QStringLiteral("folder-download-symbolic")},
            {QStringLiteral("title"), QStringLiteral("Fedora.iso")},
            {QStringLiteral("progress"), 0.68},
            {QStringLiteral("processedBytes"), 3200000000.0},
            {QStringLiteral("totalBytes"), 4700000000.0},
            {QStringLiteral("capabilities"), QVariantMap{{QStringLiteral("cancel"), true}}},
        };
        const QVariantMap media{
            {QStringLiteral("id"), QStringLiteral("media-1")},
            {QStringLiteral("generation"), 1},
            {QStringLiteral("kind"), QStringLiteral("media")},
            {QStringLiteral("state"), fixture == QStringLiteral("paused")
                 ? QStringLiteral("paused") : QStringLiteral("playing")},
            {QStringLiteral("source"), QStringLiteral("Player")},
            {QStringLiteral("icon"), QStringLiteral("audio-x-generic-symbolic")},
            {QStringLiteral("title"), QStringLiteral("Houdini")},
            {QStringLiteral("artist"), QStringLiteral("Dua Lipa")},
            {QStringLiteral("positionUs"), 161000000.0},
            {QStringLiteral("sampledAtMonotonicUs"), static_cast<double>(monotonicNowUs())},
            {QStringLiteral("durationUs"), 185000000.0},
            {QStringLiteral("rate"), 1.0},
            {QStringLiteral("capabilities"), QVariantMap{
                 {QStringLiteral("play"), true}, {QStringLiteral("pause"), true},
                 {QStringLiteral("previous"), true}, {QStringLiteral("next"), true}}},
        };
        m_ambientActivities = {transfer, media};
    } else {
        m_activities = ActivityModel::acquire();
        connect(m_activities.get(), &ActivityModel::changed, this, [this] {
            setAmbientActivities(m_activities->activities());
        });
        connect(m_activities.get(), &ActivityModel::driveOpenRequested, this, [this](const QString &udi) {
            startLauncher(settings().readEntry(QStringLiteral("useKadunce"), true), {}, {}, udi);
        });
        connect(m_activities.get(), &ActivityModel::revealRequested, this, [this](const QString &path) {
            startLauncher(settings().readEntry(QStringLiteral("useKadunce"), true), path);
        });
        setAmbientActivities(m_activities->activities());
    }
}

bool TettegoucheApplet::launcherActive() const
{
    return m_process->state() != QProcess::NotRunning;
}

QVariantList TettegoucheApplet::ambientActivities() const
{
    return m_ambientActivities;
}

void TettegoucheApplet::setAmbientActivities(const QVariantList &activities)
{
    if (m_ambientActivities == activities) {
        return;
    }
    m_ambientActivities = activities;
    Q_EMIT ambientActivitiesChanged();
}

int TettegoucheApplet::availablePanelWidth(QQuickItem *visualParent, int minimumWidth, int gap) const
{
    minimumWidth = std::max(1, minimumWidth);
    gap = std::max(0, gap);
    if (!visualParent || !visualParent->window() || !containment()) {
        return minimumWidth;
    }

    QQuickItem *ownItem = PlasmaQuick::AppletQuickItem::itemForApplet(
        const_cast<TettegoucheApplet *>(this));
    if (!ownItem || ownItem->window() != visualParent->window()) {
        ownItem = visualParent;
    }

    const qreal ownLeft = ownItem->mapToScene(QPointF(0, 0)).x();
    const qreal ownRight = ownItem->mapToScene(QPointF(ownItem->width(), 0)).x();
    qreal nearestRightEdge = -1;
    for (Plasma::Applet *applet : containment()->applets()) {
        if (!applet || applet == this || applet->destroyed()) {
            continue;
        }
        const QString pluginId = applet->pluginMetaData().pluginId();
        if (pluginId == QStringLiteral("org.kde.plasma.panelspacer")
            || pluginId == QStringLiteral("org.kde.plasma.marginsseparator")
            || !PlasmaQuick::AppletQuickItem::hasItemForApplet(applet)) {
            continue;
        }
        auto *item = PlasmaQuick::AppletQuickItem::itemForApplet(applet);
        if (!item || !item->isVisible() || item->window() != ownItem->window()) {
            continue;
        }
        const qreal itemLeft = item->mapToScene(QPointF(0, 0)).x();
        if (itemLeft >= ownRight - 1
            && (nearestRightEdge < 0 || itemLeft < nearestRightEdge)) {
            nearestRightEdge = itemLeft;
        }
    }
    if (nearestRightEdge < 0) {
        return minimumWidth;
    }
    return std::max(minimumWidth,
                    static_cast<int>(std::floor(nearestRightEdge - ownLeft - gap)));
}

void TettegoucheApplet::watchGeometryItem(QQuickItem *item)
{
    m_watchedGeometryItems.removeIf([](const QPointer<QQuickItem> &watched) {
        return watched.isNull();
    });
    if (!item || m_watchedGeometryItems.contains(item)) {
        return;
    }
    m_watchedGeometryItems.append(item);
    const auto changed = [this] { Q_EMIT panelGeometryChanged(); };
    connect(item, &QQuickItem::xChanged, this, changed);
    connect(item, &QQuickItem::widthChanged, this, changed);
    connect(item, &QQuickItem::visibleChanged, this, changed);
    connect(item, &QQuickItem::windowChanged, this, changed);
}

void TettegoucheApplet::watchPanelGeometry(QQuickItem *visualParent)
{
    watchGeometryItem(visualParent);
    if (!containment()) {
        return;
    }
    if (!m_watchingContainment) {
        m_watchingContainment = true;
        connect(containment(), &Plasma::Containment::appletAdded, this,
                [this](Plasma::Applet *) {
                    QTimer::singleShot(0, this, [this] { Q_EMIT panelGeometryChanged(); });
                });
        connect(containment(), &Plasma::Containment::appletRemoved, this,
                [this](Plasma::Applet *) { Q_EMIT panelGeometryChanged(); });
    }
    for (Plasma::Applet *applet : containment()->applets()) {
        if (applet && PlasmaQuick::AppletQuickItem::hasItemForApplet(applet)) {
            watchGeometryItem(PlasmaQuick::AppletQuickItem::itemForApplet(applet));
        }
    }
}

void TettegoucheApplet::invokeActivity(const QString &id, int generation, const QString &action,
                                       const QVariant &value)
{
    if (id.isEmpty() || generation < 0 || action.isEmpty()) {
        return;
    }
    Q_EMIT activityActionInvoked(id, generation, action);
    if (!m_activities) return;
    if (action == QLatin1String("showInFiles")) {
        const auto url = m_activities->destinationForReveal(id, generation);
        if (url.isLocalFile()) {
            m_activities->revealed(id, generation);
            startLauncher(settings().readEntry(QStringLiteral("useKadunce"), true), url.toLocalFile());
        }
    } else m_activities->invoke(id, generation, action, value);
}

qint64 TettegoucheApplet::monotonicNowUs() const
{
    using namespace std::chrono;
    return duration_cast<microseconds>(steady_clock::now().time_since_epoch()).count();
}

QRectF TettegoucheApplet::screenRect(QQuickItem *item) const
{
    if (!item || !item->window()) {
        return {};
    }
    const QPointF topLeft = item->mapToGlobal(QPointF(0, 0));
    const QScreen *screen = item->window()->screen();
    const QPointF origin = screen ? QPointF(screen->geometry().topLeft()) : QPointF();
    return QRectF(topLeft - origin, QSizeF(item->width(), item->height()));
}

bool TettegoucheApplet::prepareIslandSurface(QWindow *window, QQuickItem *panelItem) const
{
    // The open island goes on the display the panel is on. The panel's window
    // knows it; asked from QML, a panel window gives no screen at all.
    QScreen *screen = panelItem && panelItem->window() ? panelItem->window()->screen() : nullptr;
    if (!window || !screen) {
        return false;
    }
    window->setScreen(screen);
    // A clear top-layer surface over the whole display, as the launcher's:
    // it reserves nothing, stays under the on-screen keys in the overlay
    // layer, and takes the keyboard so Esc closes it.
    auto *surface = LayerShellQt::Window::get(window);
    surface->setScreen(screen);
    surface->setScope(QStringLiteral("tettegouche-island"));
    surface->setLayer(LayerShellQt::Window::LayerTop);
    LayerShellQt::Window::Anchors anchors;
    anchors.setFlag(LayerShellQt::Window::AnchorTop);
    anchors.setFlag(LayerShellQt::Window::AnchorBottom);
    anchors.setFlag(LayerShellQt::Window::AnchorLeft);
    anchors.setFlag(LayerShellQt::Window::AnchorRight);
    surface->setAnchors(anchors);
    surface->setDesiredSize(QSize(0, 0));
    surface->setExclusiveZone(-1);
    surface->setKeyboardInteractivity(LayerShellQt::Window::KeyboardInteractivityExclusive);
    surface->setActivateOnShow(true);
    window->setGeometry(screen->geometry());
    return true;
}

void TettegoucheApplet::launch(bool useKadunce)
{
    startLauncher(useKadunce);
}

void TettegoucheApplet::openDrawer(const QString &drawer)
{
    if (drawer != QLatin1String("apps") && drawer != QLatin1String("files")) return;
    startLauncher(settings().readEntry(QStringLiteral("useKadunce"), true), {}, drawer);
}

KConfigGroup TettegoucheApplet::settings() const
{
    return config().group(QStringLiteral("General"));
}

void TettegoucheApplet::startLauncher(bool useKadunce, const QString &showFile, const QString &drawer,
                                      const QString &drive)
{
    if (launcherActive()) {
        if (m_process->state() == QProcess::Running) {
            auto request = QDBusMessage::createMethodCall(
                QStringLiteral("io.github.carlsonjm.Tettegouche"),
                QStringLiteral("/Launcher"),
                QStringLiteral("io.github.carlsonjm.Tettegouche"),
                !showFile.isEmpty() ? QStringLiteral("showFile")
                    : !drive.isEmpty() ? QStringLiteral("showDrive")
                    : !drawer.isEmpty() ? QStringLiteral("openDrawer") : QStringLiteral("toggle"));
            if (!showFile.isEmpty()) request.setArguments({showFile});
            else if (!drive.isEmpty()) request.setArguments({drive});
            else if (!drawer.isEmpty()) request.setArguments({drawer});
            QDBusConnection::sessionBus().asyncCall(request);
        }
        return;
    }

    const QString executable = QStandardPaths::findExecutable(QStringLiteral("tettegouche"));
    if (executable.isEmpty()) {
        return;
    }

    m_process->setProgram(executable);
    QStringList arguments = useKadunce ? QStringList{} : QStringList{QStringLiteral("--standalone")};
    // Search's first screen offers what was used lately unless that is off.
    if (!settings().readEntry(QStringLiteral("offerRecent"), true)) arguments << QStringLiteral("--no-recent");
    // It offers Notes, where the notes application is installed, unless that is off.
    if (!settings().readEntry(QStringLiteral("offerNotes"), true)) arguments << QStringLiteral("--no-notes");
    // And Genie, where Split Rock is installed, unless that is off.
    if (!settings().readEntry(QStringLiteral("offerGenie"), true)) arguments << QStringLiteral("--no-genie");
    if (!showFile.isEmpty()) arguments << QStringLiteral("--show-file") << showFile;
    else if (!drive.isEmpty()) arguments << QStringLiteral("--drive") << drive;
    else if (!drawer.isEmpty()) arguments << QStringLiteral("--drawer") << drawer;
    m_process->setArguments(arguments);
    Q_EMIT invocationRequested();
    m_process->start();
}

K_PLUGIN_CLASS_WITH_JSON(TettegoucheApplet, "metadata.json")

#include "TettegoucheApplet.moc"
