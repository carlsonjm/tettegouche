#pragma once
#include <QDBusConnection>
#include <QDBusMessage>
#include <QHash>
#include <QObject>
#include <QVariantList>

// The screen being shared or recorded, from the status notifier item Plasma's
// portal, xdg-desktop-portal-kde, shows while a screen cast runs. Its icon is
// the receiving application's, its tooltip already says who receives the
// screen in the person's language, and its menu's one action, End, closes the
// portal session: Stop sends that action. The item is followed through the
// StatusNotifierWatcher as it comes, changes and goes; nothing is asked on a
// timer.
//
// Each share also says whether notifications are quiet, from the notification
// server's Inhibited property: Plasma keeps them quiet while the screen is
// shared when its setting for that is on, and the person's Do Not Disturb
// does too.
class ScreenShareProvider : public QObject {
    Q_OBJECT
public:
    explicit ScreenShareProvider(const QDBusConnection &bus, QObject *parent = nullptr);
    QVariantList activities() const;
    void invoke(const QString &id, int generation, const QString &action);
Q_SIGNALS:
    void changed();
private Q_SLOTS:
    void registered(const QString &item);
    void unregistered(const QString &item);
    void itemChanged(const QDBusMessage &message);
    void notificationsChanged(const QString &interface, const QVariantMap &properties, const QStringList &invalidated);
private:
    void readQuiet();
    struct Share { QString item, service, path, menu, icon, who; int generation = 0; };
    void load();
    void read(const QString &item);
    static QPair<QString, QString> address(const QString &item);
    QDBusConnection m_bus;
    QHash<QString, Share> m_shares;
    int m_generation = 0;
    bool m_quiet = false;
};
