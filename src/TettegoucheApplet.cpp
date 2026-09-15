/* SPDX-License-Identifier: GPL-2.0-or-later */

#include "TettegoucheApplet.h"

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

    connect(m_process, &QProcess::stateChanged, this,
            [this] { Q_EMIT launcherActiveChanged(); });

    connect(this, &Plasma::Applet::activated, this, [this] {
        launch(config().readEntry(QStringLiteral("useKadunce"), true));
    });

    const QString fixture = qEnvironmentVariable("TETTE_AMBIENT_FIXTURE");
    if (!fixture.isEmpty()) {
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
    qreal nearestLeftEdge = -1;
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
        const qreal itemRight = item->mapToScene(QPointF(item->width(), 0)).x();
        if (itemRight <= ownLeft + 1 && itemRight > nearestLeftEdge) {
            nearestLeftEdge = itemRight;
        }
    }
    if (nearestLeftEdge < 0) {
        return minimumWidth;
    }
    return std::max(minimumWidth,
                    static_cast<int>(std::floor(ownRight - nearestLeftEdge - gap)));
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

void TettegoucheApplet::invokeActivity(const QString &id, int generation, const QString &action)
{
    if (id.isEmpty() || generation < 0 || action.isEmpty()) {
        return;
    }
    Q_EMIT activityActionInvoked(id, generation, action);
}

qint64 TettegoucheApplet::monotonicNowUs() const
{
    using namespace std::chrono;
    return duration_cast<microseconds>(steady_clock::now().time_since_epoch()).count();
}

void TettegoucheApplet::launch(bool useKadunce)
{
    if (launcherActive()) {
        if (m_process->state() == QProcess::Running) {
            const auto request = QDBusMessage::createMethodCall(
                QStringLiteral("io.github.carlsonjm.Tettegouche"),
                QStringLiteral("/Launcher"),
                QStringLiteral("io.github.carlsonjm.Tettegouche"),
                QStringLiteral("toggle"));
            QDBusConnection::sessionBus().asyncCall(request);
        }
        return;
    }

    const QString executable = QStandardPaths::findExecutable(QStringLiteral("tettegouche"));
    if (executable.isEmpty()) {
        return;
    }

    m_process->setProgram(executable);
    m_process->setArguments(useKadunce ? QStringList{}
                                       : QStringList{QStringLiteral("--standalone")});
    Q_EMIT invocationRequested();
    m_process->start();
}

K_PLUGIN_CLASS_WITH_JSON(TettegoucheApplet, "metadata.json")

#include "TettegoucheApplet.moc"
