/* SPDX-License-Identifier: GPL-2.0-or-later */

#pragma once

#include <Plasma/Applet>
#include <QList>
#include <QPointer>
#include <QVariantList>
#include <memory>
class ActivityModel;
class LauncherKeys;

class QProcess;
class QQuickItem;
class QWindow;

class TettegoucheApplet final : public Plasma::Applet
{
    Q_OBJECT
    Q_PROPERTY(bool launcherActive READ launcherActive NOTIFY launcherActiveChanged)
    Q_PROPERTY(QVariantList ambientActivities READ ambientActivities WRITE setAmbientActivities
               NOTIFY ambientActivitiesChanged)

public:
    TettegoucheApplet(QObject *parent, const KPluginMetaData &data,
                      const QVariantList &args);

    bool launcherActive() const;
    QVariantList ambientActivities() const;
    void setAmbientActivities(const QVariantList &activities);
    Q_INVOKABLE void launch(bool useKadunce);
    // "apps" or "files": opens the launcher on that drawer, as Meta+G and Meta+E do.
    Q_INVOKABLE void openDrawer(const QString &drawer);
    Q_INVOKABLE int availablePanelWidth(QQuickItem *visualParent, int minimumWidth, int gap) const;
    Q_INVOKABLE void watchPanelGeometry(QQuickItem *visualParent);
    Q_INVOKABLE void invokeActivity(const QString &id, int generation, const QString &action,
                                    const QVariant &value = {});
    Q_INVOKABLE qint64 monotonicNowUs() const;
    Q_INVOKABLE QRectF screenRect(QQuickItem *item) const;
    Q_INVOKABLE bool prepareIslandSurface(QWindow *window, QQuickItem *panelItem) const;

Q_SIGNALS:
    void invocationRequested();
    void launcherActiveChanged();
    void ambientActivitiesChanged();
    void panelGeometryChanged();
    void activityActionInvoked(const QString &id, int generation, const QString &action);

private:
    void watchGeometryItem(QQuickItem *item);
    void startLauncher(bool useKadunce, const QString &showFile = {}, const QString &drawer = {});

    QProcess *m_process = nullptr;
    QVariantList m_ambientActivities;
    QList<QPointer<QQuickItem>> m_watchedGeometryItems;
    bool m_watchingContainment = false;
    std::shared_ptr<ActivityModel> m_activities;
    std::shared_ptr<LauncherKeys> m_keys;
};
