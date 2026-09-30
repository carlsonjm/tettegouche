#pragma once
#include <QDBusConnection>
#include <QHash>
#include <QObject>
#include <QTimer>
#include <QVariantList>
#include <Solid/Device>

// A drive plugged in that nothing has mounted. It waits in Ambient for a
// minute, where one tap asks Files to open it, mounting it first. Ignored, or
// set aside, it is filed as a notification of the freedesktop device.added
// category with Open in Files, which the history keeps and the ticker does
// not play: that minute was its showing. A drive already there when Ambient
// starts, one the system or the person mounts, one Files does not list, and a
// phone never wait here. Unplugged, a drive leaves, and its filed notice with
// it.
class DriveActivityProvider : public QObject {
    Q_OBJECT
public:
    struct Drive { QString udi, label, icon; qint64 sizeBytes = -1; };
    DriveActivityProvider(const QDBusConnection &bus, QObject *parent = nullptr, int lingerMs = 60000,
                          bool watchDevices = true);
    QVariantList activities() const;
    // Tapped in Ambient: it leaves, and Files is asked to open it.
    void open(const QString &id);
    // Set aside in Ambient: filed now.
    void setAside(const QString &id);
    // A drive of Files' own list, plugged in and not mounted.
    void plugged(const Drive &drive);
    // Unplugged: it leaves, and so does its notice.
    void unplugged(const QString &udi);
    // Mounted by the system or the person: it leaves quietly.
    void mounted(const QString &udi);
Q_SIGNALS:
    void changed();
    // Files should open this drive.
    void openRequested(const QString &udi);
private Q_SLOTS:
    void actionInvoked(uint id, const QString &action);
    void notificationClosed(uint id, uint reason);
private:
    struct Waiting { Drive drive; int generation = 0; qint64 deadline = 0; };
    void deviceAdded(const QString &udi);
    void expire();
    void file(const Drive &drive);
    bool take(const QString &udi, Waiting *taken = nullptr);
    QDBusConnection m_bus;
    int m_lingerMs;
    QList<Waiting> m_waiting;
    QTimer m_expiry;
    int m_generation = 0;
    // Solid drops a device's interfaces, and every connection to them, once
    // nothing holds the device.
    QHash<QString, Solid::Device> m_held;
    // Each filed notice still open, and its drive.
    QHash<uint, QString> m_filed;
};
