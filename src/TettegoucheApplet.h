/* SPDX-License-Identifier: GPL-2.0-or-later */

#pragma once

#include "shared/PanelRoom.h"

#include <KConfigGroup>
#include <Plasma/Applet>
#include <QList>
#include <QStringList>
#include <QPointer>
#include <QTimer>
#include <QVariantList>
#include <memory>
class ActivityModel;
class LauncherKeys;

class QQuickItem;
class QWindow;

class TettegoucheApplet final : public Plasma::Applet
{
    Q_OBJECT
    Q_PROPERTY(bool launcherActive READ launcherActive NOTIFY launcherActiveChanged)
    // Search where Shuffle is installed, Tettegouche elsewhere.
    Q_PROPERTY(QString productName READ productName CONSTANT)
    Q_PROPERTY(QVariantList ambientActivities READ ambientActivities WRITE setAmbientActivities
               NOTIFY ambientActivitiesChanged)
    // What a slide from the dot can open, in Search's order: "apps", "files",
    // then "notes" where Search offers it.
    Q_PROPERTY(QStringList pearlDoors READ pearlDoors NOTIFY pearlDoorsChanged)

public:
    TettegoucheApplet(QObject *parent, const KPluginMetaData &data,
                      const QVariantList &args);

    bool launcherActive() const;
    QString productName() const;
    QVariantList ambientActivities() const;
    void setAmbientActivities(const QVariantList &activities);
    Q_INVOKABLE void launch(bool useKadunce);
    // "apps" or "files": opens the launcher on that drawer, as Meta+G and Meta+E do;
    // "notes" opens it on Notes, as the dot's slide does.
    Q_INVOKABLE void openDrawer(const QString &drawer);
    QStringList pearlDoors() const { return m_pearlDoors; }
    // Looks again for Notes, as a press on the dot does.
    Q_INVOKABLE void refreshPearlDoors();
    Q_INVOKABLE int availablePanelWidth(QQuickItem *visualParent, int minimumWidth, int gap) const;
    Q_INVOKABLE void watchPanelGeometry(QQuickItem *visualParent);
    Q_INVOKABLE void invokeActivity(const QString &id, int generation, const QString &action,
                                    const QVariant &value = {});
    Q_INVOKABLE qint64 monotonicNowUs() const;
    Q_INVOKABLE QRectF screenRect(QQuickItem *item) const;
    Q_INVOKABLE bool prepareIslandSurface(QWindow *window, QQuickItem *panelItem) const;

private Q_SLOTS:
    void launcherShown(bool visible);

Q_SIGNALS:
    void invocationRequested();
    void launcherActiveChanged();
    void ambientActivitiesChanged();
    void panelGeometryChanged();
    void activityActionInvoked(const QString &id, int generation, const QString &action);
    void pearlDoorsChanged();

private:
    // One of the widget's settings as main.xml declares it, read where its
    // settings page and Shuffle Settings both write it.
    bool setting(const QString &key, bool fallback);
    QString textSetting(const QString &key, const QString &fallback);
    void startLauncher(bool useKadunce, const QString &showFile = {}, const QString &drawer = {},
                       const QString &drive = {});
    // What is asked of the launcher: the widget's settings as its arguments,
    // and a file to show, a drawer or a drive; with none of them, a toggle.
    struct Request {
        QStringList flags;
        QString showFile, drawer, drive;
    };
    // The widget's settings, as the launcher's arguments.
    QStringList launchFlags();
    void request(const Request &request);
    // Asks the running launcher.
    void forward(const Request &request);
    // Starts a launcher for the request.
    void start(const Request &request);
    void setLauncherRunning(bool running);

    // Whether the launcher's name is on the bus.
    bool m_launcherRunning = false;
    // Running from a start, until its name is on the bus or a while has passed.
    QTimer m_starting;
    // A launcher kept ready runs on hidden; it says when it shows or hides.
    bool m_launcherShown = false;
    // Asked to leave for the widget's new settings; the request waits for
    // the launcher that takes its place.
    bool m_leaving = false;
    Request m_pending;
    QString m_productName;
    QVariantList m_ambientActivities;
    QStringList m_pearlDoors{QStringLiteral("apps"), QStringLiteral("files")};
    void setPearlDoors();
    suite::PanelWatch m_panelWatch;
    std::shared_ptr<ActivityModel> m_activities;
    std::shared_ptr<LauncherKeys> m_keys;
};
