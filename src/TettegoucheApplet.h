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
    // While Search is up: the mode it shows ("apps", "files", "notes", or ""
    // on its first screen), and whether an application is on its way.
    Q_PROPERTY(QString launcherMode READ launcherMode NOTIFY launcherShowingChanged)
    Q_PROPERTY(bool launcherLoading READ launcherLoading NOTIFY launcherShowingChanged)
    // Search where Shuffle is installed, Tettegouche elsewhere.
    Q_PROPERTY(QString productName READ productName CONSTANT)
    Q_PROPERTY(QVariantList ambientActivities READ ambientActivities WRITE setAmbientActivities
               NOTIFY ambientActivitiesChanged)
    // What a slide from the dot can open, in Search's order: "apps", "files",
    // then "notes" where Search offers it.
    Q_PROPERTY(QStringList pearlDoors READ pearlDoors NOTIFY pearlDoorsChanged)
    // Split Rock's Ask is installed, so the Helpers door reads Ask, as
    // Search's chip does.
    Q_PROPERTY(bool askOffered READ askOffered NOTIFY pearlDoorsChanged)
    // Split Rock's Core keeps saved layouts, for the Layouts island: each
    // layout as Core lists it, and what is open now once asked for.
    Q_PROPERTY(bool keepsLayouts READ keepsLayouts NOTIFY layoutsChanged)
    Q_PROPERTY(QVariantList layouts READ layouts NOTIFY layoutsChanged)
    // What is open on the workspace in use, as Core reads it from Cards
    // (`available`, `groups`), with the workspace's name (`workspaceName`)
    // where KWin gives it; empty until readCurrentLayout() is answered.
    Q_PROPERTY(QVariantMap currentLayout READ currentLayout NOTIFY currentLayoutChanged)

public:
    TettegoucheApplet(QObject *parent, const KPluginMetaData &data,
                      const QVariantList &args);
    ~TettegoucheApplet() override;

    bool launcherActive() const;
    QString launcherMode() const { return m_launcherMode; }
    bool launcherLoading() const { return m_launcherLoading; }
    QString productName() const;
    QVariantList ambientActivities() const;
    void setAmbientActivities(const QVariantList &activities);
    Q_INVOKABLE void launch(bool useKadunce);
    // "apps" or "files": opens the launcher on that drawer, as Meta+G and Meta+E do;
    // "notes" opens it on Notes, as the dot's slide does; "note" on the quick
    // note's page, and "note:" with a note's id on that note's page, as the
    // quick note's island does.
    Q_INVOKABLE void openDrawer(const QString &drawer);
    QStringList pearlDoors() const { return m_pearlDoors; }
    bool askOffered() const { return m_askOffered; }
    // Looks again for Notes, as a press on the dot does.
    Q_INVOKABLE void refreshPearlDoors();
    Q_INVOKABLE int availablePanelWidth(QQuickItem *visualParent, int minimumWidth, int gap) const;
    Q_INVOKABLE void watchPanelGeometry(QQuickItem *visualParent);
    Q_INVOKABLE void invokeActivity(const QString &id, int generation, const QString &action,
                                    const QVariant &value = {});
    // Whether this widget shows the quick note's island now.
    Q_INVOKABLE void showNoteIsland(bool shown);
    Q_INVOKABLE qint64 monotonicNowUs() const;
    Q_INVOKABLE QRectF screenRect(QQuickItem *item) const;
    Q_INVOKABLE bool prepareIslandSurface(QWindow *window, QQuickItem *panelItem) const;
    // The name of the display the item is on.
    Q_INVOKABLE QString screenName(QQuickItem *item) const;
    bool keepsLayouts() const;
    QVariantList layouts() const;
    QVariantMap currentLayout() const { return m_currentLayout; }
    Q_INVOKABLE void readCurrentLayout();
    Q_INVOKABLE void saveLayout(const QString &name, const QVariantList &groups, bool atSignIn);
    Q_INVOKABLE void openLayout(const QString &id);
    Q_INVOKABLE void removeLayout(const QString &id);
    Q_INVOKABLE void setLayoutAtSignIn(const QString &id, bool on);

private Q_SLOTS:
    void launcherShown(bool visible);
    void launcherShowing(const QString &mode, bool loading);
    void launcherIslandRequested(const QString &kind, const QString &output);

Q_SIGNALS:
    void invocationRequested();
    void launcherActiveChanged();
    void launcherShowingChanged();
    void ambientActivitiesChanged();
    void panelGeometryChanged();
    void activityActionInvoked(const QString &id, int generation, const QString &action);
    void pearlDoorsChanged();
    void layoutsChanged();
    void currentLayoutChanged();
    // Search asked for an island in the band, such as Layouts, on the
    // display named (empty where Search could not say).
    void islandRequested(const QString &kind, const QString &output);

private:
    // One of the widget's settings as main.xml declares it, read where its
    // settings page and Shuffle Settings both write it.
    bool setting(const QString &key, bool fallback);
    void startLauncher(bool useKadunce, const QString &showFile = {}, const QString &drawer = {},
                       const QString &drive = {}, bool toType = false);
    // What is asked of the launcher: the widget's settings as its arguments,
    // and a file to show, a drawer or a drive; with none of them, a toggle.
    struct Request {
        QStringList flags;
        QString showFile, drawer, drive;
        // Asked by Search's key, not its button: Search opens ready to type.
        bool toType = false;
    };
    // The widget's settings, as the launcher's arguments.
    QStringList launchFlags();
    void request(const Request &request);
    // Asks the running launcher.
    void forward(const Request &request);
    // Starts a launcher for the request.
    void start(const Request &request);
    // Starts a launcher that stays hidden, ready for the first touch.
    void warmLauncher();
    void setLauncherRunning(bool running);

    // Whether the launcher's name is on the bus.
    bool m_launcherRunning = false;
    // Running from a start, until its name is on the bus or a while has passed.
    QTimer m_starting;
    // A launcher kept ready runs on hidden; it says when it shows or hides.
    bool m_launcherShown = false;
    QString m_launcherMode;
    bool m_launcherLoading = false;
    void clearLauncherShowing();
    // Asked to leave for the widget's new settings; the request waits for
    // the launcher that takes its place.
    bool m_leaving = false;
    Request m_pending;
    QString m_productName;
    QVariantList m_ambientActivities;
    QStringList m_pearlDoors{QStringLiteral("apps"), QStringLiteral("files")};
    bool m_askOffered = false;
    void setPearlDoors();
    suite::PanelWatch m_panelWatch;
    // Names the workspace a current layout was read on, then shows it.
    void nameWorkspace(QVariantMap layout);
    QVariantMap m_currentLayout;
    std::shared_ptr<ActivityModel> m_activities;
    std::shared_ptr<LauncherKeys> m_keys;
};
