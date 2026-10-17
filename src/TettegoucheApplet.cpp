/* SPDX-License-Identifier: GPL-2.0-or-later */

#include "TettegoucheApplet.h"
#include "ActivityModel.h"
#include "LauncherKeys.h"
#include "NotesDoor.h"
#include "NotesIslandProvider.h"
#include "ProductName.h"
#include "shared/SuiteSettings.h"

#include <KConfigGroup>
#include <KConfigLoader>
#include <KPluginFactory>
#include <KIO/CommandLauncherJob>
#include <KService>
#include <QStandardPaths>
#include <QDBusConnection>
#include <QDBusConnectionInterface>
#include <QDBusMessage>
#include <QDBusPendingCall>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QDBusServiceWatcher>
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

namespace
{
const QString LauncherService = QStringLiteral("io.github.carlsonjm.Tettegouche");
// How long a launcher just started is taken to be on its way, until its name
// is on the bus.
constexpr int StartingMs = 5000;
}

TettegoucheApplet::TettegoucheApplet(QObject *parent,
                                     const KPluginMetaData &data,
                                     const QVariantList &args)
    : Plasma::Applet(parent, data, args)
    , m_productName(tettegouche::productName())
{
    // Menus and the widget's title read the shown name; where Shuffle is
    // absent, the title stays the one metadata.json gives.
    if (tettegouche::shuffleInstalled()) {
        setTitle(m_productName);
    }
    setHasConfigurationInterface(true);
    suite::openConfigureInSuiteSettings(this, QStringLiteral("search"));

    // The launcher is a process of its own, started in a scope of its own,
    // so restarting or removing the panel leaves it and its work running. It
    // is known by its name on the bus.
    auto *launcher = new QDBusServiceWatcher(LauncherService, QDBusConnection::sessionBus(),
        QDBusServiceWatcher::WatchForRegistration | QDBusServiceWatcher::WatchForUnregistration, this);
    connect(launcher, &QDBusServiceWatcher::serviceRegistered, this, [this] { setLauncherRunning(true); });
    connect(launcher, &QDBusServiceWatcher::serviceUnregistered, this, [this] { setLauncherRunning(false); });
    if (QDBusConnectionInterface *bus = QDBusConnection::sessionBus().interface()) {
        auto *watcher = new QDBusPendingCallWatcher(bus->asyncCall(QStringLiteral("NameHasOwner"), LauncherService), this);
        connect(watcher, &QDBusPendingCallWatcher::finished, this, [this, watcher] {
            watcher->deleteLater();
            const QDBusPendingReply<bool> reply = *watcher;
            if (!reply.isError() && reply.value()) setLauncherRunning(true);
        });
    }
    m_starting.setSingleShot(true);
    m_starting.setInterval(StartingMs);
    connect(&m_starting, &QTimer::timeout, this, [this] {
        // Started, it never came: nothing is open.
        if (m_launcherRunning) return;
        m_launcherShown = false;
        Q_EMIT launcherActiveChanged();
    });
    QDBusConnection::sessionBus().connect(LauncherService,
        QStringLiteral("/Launcher"), LauncherService,
        QStringLiteral("shown"), this, SLOT(launcherShown(bool)));

    connect(this, &Plasma::Applet::activated, this, [this] {
        launch(setting(QStringLiteral("useKadunce"), true));
    });
    m_keys = LauncherKeys::acquire();
    m_keys->attach(this, [this](const QString &drawer) { openDrawer(drawer); });
    // Once the widget's settings are read.
    QTimer::singleShot(0, this, &TettegoucheApplet::refreshPearlDoors);

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
            startLauncher(setting(QStringLiteral("useKadunce"), true), {}, {}, udi);
        });
        connect(m_activities.get(), &ActivityModel::revealRequested, this, [this](const QString &path) {
            startLauncher(setting(QStringLiteral("useKadunce"), true), path);
        });
        setAmbientActivities(m_activities->activities());
    }
}

QString TettegoucheApplet::productName() const
{
    return m_productName;
}

bool TettegoucheApplet::launcherActive() const
{
    return (m_launcherRunning || m_starting.isActive()) && m_launcherShown;
}

void TettegoucheApplet::launcherShown(bool visible)
{
    if ((!m_launcherRunning && !m_starting.isActive()) || visible == m_launcherShown) return;
    m_launcherShown = visible;
    Q_EMIT launcherActiveChanged();
}

void TettegoucheApplet::setLauncherRunning(bool running)
{
    if (running == m_launcherRunning) return;
    m_launcherRunning = running;
    if (running) {
        m_starting.stop();
    } else {
        m_launcherShown = false;
        // A launcher that left for one with the widget's new settings.
        if (m_leaving) {
            m_leaving = false;
            const Request request = m_pending;
            m_pending = {};
            start(request);
        }
    }
    Q_EMIT launcherActiveChanged();
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
    return suite::panelRoom(const_cast<TettegoucheApplet *>(this), visualParent, minimumWidth, gap,
                            suite::Toward::After);
}

void TettegoucheApplet::watchPanelGeometry(QQuickItem *visualParent)
{
    m_panelWatch.follow(this, visualParent, [this] { Q_EMIT panelGeometryChanged(); });
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
            startLauncher(setting(QStringLiteral("useKadunce"), true), url.toLocalFile());
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
    // "note" is the quick note, and "note:" with a note's id that note, each
    // on the notes application's own card; on its page in Search's Notes
    // where the application cannot take it.
    const bool note = drawer == QLatin1String("note")
        || (drawer.startsWith(QLatin1String("note:")) && drawer.size() > 5);
    if (drawer != QLatin1String("apps") && drawer != QLatin1String("files")
        && drawer != QLatin1String("notes") && !note) return;
    if (note && NotesIslandProvider::openOnCard(drawer.mid(5), this)) return;
    startLauncher(setting(QStringLiteral("useKadunce"), true), {}, drawer);
}

void TettegoucheApplet::refreshPearlDoors()
{
    setPearlDoors();
}

void TettegoucheApplet::setPearlDoors()
{
    QStringList doors{QStringLiteral("apps"), QStringLiteral("files")};
    // Notes as Search's first screen shows its pill: offered, the pill
    // shown, and the notes application installed with its Capture action.
    if (setting(QStringLiteral("offerNotes"), true) && setting(QStringLiteral("showNotesPill"), true)) {
        if (const auto notes = KService::serviceByStorageId(QString::fromLatin1(NotesDoor::ApplicationId))) {
            const auto actions = notes->actions();
            if (std::any_of(actions.cbegin(), actions.cend(), [](const KServiceAction &action) {
                    return action.name() == QLatin1String(NotesDoor::ActionName);
                })) {
                doors << QStringLiteral("notes");
            }
        }
    }
    if (doors == m_pearlDoors) return;
    m_pearlDoors = doors;
    Q_EMIT pearlDoorsChanged();
}

bool TettegoucheApplet::setting(const QString &key, bool fallback)
{
    // The values Plasmoid.configuration and Plasma's scripting both change,
    // kept under the applet's Configuration group rather than beside it.
    if (KConfigLoader *scheme = configScheme()) {
        if (KConfigSkeletonItem *item = static_cast<KCoreConfigSkeleton *>(scheme)->findItem(key)) return item->property().toBool();
    }
    return config().group(QStringLiteral("Configuration")).group(QStringLiteral("General")).readEntry(key, fallback);
}

QString TettegoucheApplet::textSetting(const QString &key, const QString &fallback)
{
    if (KConfigLoader *scheme = configScheme()) {
        if (KConfigSkeletonItem *item = static_cast<KCoreConfigSkeleton *>(scheme)->findItem(key)) return item->property().toString();
    }
    return config().group(QStringLiteral("Configuration")).group(QStringLiteral("General")).readEntry(key, fallback);
}

QStringList TettegoucheApplet::launchFlags()
{
    QStringList flags = setting(QStringLiteral("useKadunce"), true) ? QStringList{} : QStringList{QStringLiteral("--standalone")};
    // Search's first screen offers what was used lately unless that is off.
    if (!setting(QStringLiteral("offerRecent"), true)) flags << QStringLiteral("--no-recent");
    // As a grid of large tiles, unless a single row is chosen.
    else if (textSetting(QStringLiteral("recentLayout"), QStringLiteral("grid")) == QLatin1String("row"))
        flags << QStringLiteral("--recent-row");
    // It offers Notes, where the notes application is installed, unless that is off.
    if (!setting(QStringLiteral("offerNotes"), true)) flags << QStringLiteral("--no-notes");
    // Its pill alone can be left out; notes still answer a search.
    else if (!setting(QStringLiteral("showNotesPill"), true)) flags << QStringLiteral("--no-notes-pill");
    return flags;
}

void TettegoucheApplet::startLauncher(bool useKadunce, const QString &showFile, const QString &drawer,
                                      const QString &drive)
{
    QStringList flags = launchFlags();
    // Activation asks for its own way into Kadunce, whatever the setting says.
    flags.removeAll(QStringLiteral("--standalone"));
    if (!useKadunce) flags.prepend(QStringLiteral("--standalone"));
    request({flags, showFile, drawer, drive});
}

void TettegoucheApplet::request(const Request &request)
{
    // Asked again while a launcher leaves, the latest request waits for the
    // one that takes its place.
    if (m_leaving) {
        m_pending = request;
        return;
    }
    if (!m_launcherRunning) {
        start(request);
        return;
    }
    // A launcher kept ready with other settings leaves for one started with
    // these, unless something keeps it; one that cannot be asked keeps going.
    auto leave = QDBusMessage::createMethodCall(LauncherService, QStringLiteral("/Launcher"),
        LauncherService, QStringLiteral("leaveFor"));
    leave.setArguments({request.flags});
    m_leaving = true;
    m_pending = request;
    auto *watcher = new QDBusPendingCallWatcher(QDBusConnection::sessionBus().asyncCall(leave, 1000), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this, watcher] {
        watcher->deleteLater();
        const QDBusPendingReply<bool> reply = *watcher;
        if (!reply.isError() && reply.value()) {
            // It is going; its name leaving starts the next one. A launcher
            // that is slow to go is not waited on for ever.
            QTimer::singleShot(3000, this, [this] {
                if (!m_leaving) return;
                m_leaving = false;
                const Request waiting = m_pending;
                m_pending = {};
                forward(waiting);
            });
            return;
        }
        m_leaving = false;
        const Request waiting = m_pending;
        m_pending = {};
        forward(waiting);
    });
}

void TettegoucheApplet::forward(const Request &request)
{
    if (!m_launcherRunning) {
        start(request);
        return;
    }
    auto call = QDBusMessage::createMethodCall(LauncherService, QStringLiteral("/Launcher"), LauncherService,
        !request.showFile.isEmpty() ? QStringLiteral("showFile")
            : !request.drive.isEmpty() ? QStringLiteral("showDrive")
            : !request.drawer.isEmpty() ? QStringLiteral("openDrawer") : QStringLiteral("toggle"));
    if (!request.showFile.isEmpty()) call.setArguments({request.showFile});
    else if (!request.drive.isEmpty()) call.setArguments({request.drive});
    else if (!request.drawer.isEmpty()) call.setArguments({request.drawer});
    auto *watcher = new QDBusPendingCallWatcher(QDBusConnection::sessionBus().asyncCall(call), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this, watcher, request] {
        watcher->deleteLater();
        // A launcher that went as it was asked is started again for it.
        const QDBusPendingReply<> reply = *watcher;
        if (reply.isError() && (reply.error().type() == QDBusError::ServiceUnknown
                                || (reply.error().type() == QDBusError::NoReply && !m_launcherRunning)))
            start(request);
    });
}

void TettegoucheApplet::start(const Request &request)
{
    const QString executable = QStandardPaths::findExecutable(QStringLiteral("tettegouche"));
    if (executable.isEmpty()) {
        return;
    }
    QStringList arguments = request.flags;
    if (!request.showFile.isEmpty()) arguments << QStringLiteral("--show-file") << request.showFile;
    else if (!request.drive.isEmpty()) arguments << QStringLiteral("--drive") << request.drive;
    else if (!request.drawer.isEmpty()) arguments << QStringLiteral("--drawer") << request.drawer;
    // Started while another is still on its way, the new process hands its
    // request to that one once it answers.
    m_launcherShown = true;
    m_starting.start();
    Q_EMIT launcherActiveChanged();
    Q_EMIT invocationRequested();
    // In a scope of its own, as a command started from a launcher is, so the
    // panel going does not take the launcher with it. It is started as a
    // command, not as its desktop entry, so no startup is announced for it.
    auto *job = new KIO::CommandLauncherJob(executable, arguments, this);
    connect(job, &KJob::result, this, [this](KJob *started) {
        if (!started->error() || m_launcherRunning) return;
        m_starting.stop();
        m_launcherShown = false;
        Q_EMIT launcherActiveChanged();
    });
    job->start();
}

K_PLUGIN_CLASS_WITH_JSON(TettegoucheApplet, "metadata.json")

#include "TettegoucheApplet.moc"
