#pragma once

#include "DriveRules.h"
#include <KProtocolInfo>
#include <KLocalizedString>
#include <Solid/Device>
#include <Solid/DeviceNotifier>
#include <Solid/OpticalDrive>
#include <Solid/PortableMediaPlayer>
#include <Solid/Predicate>
#include <Solid/StorageAccess>
#include <Solid/StorageDrive>
#include <QCollator>
#include <QDBusArgument>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusPendingCallWatcher>
#include <QDBusServiceWatcher>
#include <QDBusVariant>
#include <QFile>
#include <QSet>
#include <QStandardPaths>
#include <QUrl>
#include <QXmlStreamReader>
#include <algorithm>
#include <memory>
#include <optional>

// The drives Files lists beside its places: those KDE's file dialogs and Dolphin
// list, less any the person hid there, as they come and go, and phones. Nothing
// is asked of the system until the list is first wanted, so the launcher never
// waits on it to start. KDE's own places model is not used: it answers a failed
// lookup of its own with a widget message box, which aborts a process without
// widgets.
//
// A phone by cable is browsed through kio-fuse, which shows KDE's MTP address
// as a folder; one through KDE Connect, at the folder KDE Connect mounts it on.
// Either way Files keeps browsing local paths.
class FileDevices : public QObject
{
    Q_OBJECT
public:
    struct Drive {
        QString id, label, icon, path;
        bool mounted = false;
        // Plugged in rather than built in: removable or hot-pluggable media,
        // which an unmount makes safe to pull out.
        bool removable = false;
        // Being opened, or made safe to pull out.
        bool opening = false, ejecting = false;
        // A phone, by cable or through KDE Connect. It has no eject: unplugging
        // it, or taking it out of reach, is how it leaves.
        bool phone = false;
        bool busy() const { return opening || ejecting; }
        bool operator==(const Drive &) const = default;
    };
    using QObject::QObject;
    QList<Drive> drives() { start(); return m_drives; }
    // Opens a drive, mounting it first if it is not; answers with opened or failed.
    void open(const QString &id) {
        start();
        if (m_opening.contains(id) || m_removing.contains(id)) return;
        if (id.startsWith(connectedPrefix())) { openConnected(id); return; }
        auto device = held(id);
        if (isCabledPhone(device)) { openCabled(device); return; }
        auto *access = device.as<Solid::StorageAccess>();
        if (!access) return;
        if (access->isAccessible()) { Q_EMIT opened(id, access->filePath()); return; }
        m_opening.insert(id); reload();
        if (!access->setup()) finishOpening(id, Solid::OperationFailed, {});
    }
    // Makes a drive safe to pull out: unmounted, and powered off where the system
    // can, or an optical disc ejected. Answers with removed or failed.
    void remove(const QString &id) {
        start();
        auto device = held(id);
        auto *access = device.as<Solid::StorageAccess>();
        if (!access || m_opening.contains(id) || m_removing.contains(id)) return;
        m_removing.insert(id); m_labels[id] = device.description(); reload();
        bool started = false;
        auto opticalDevice = ancestor(device, Solid::DeviceInterface::OpticalDrive);
        if (auto *optical = opticalDevice.as<Solid::OpticalDrive>()) {
            m_held.insert(opticalDevice.udi(), opticalDevice);
            connect(optical, &Solid::OpticalDrive::ejectDone, this, [this](Solid::ErrorType error, const QVariant &data, const QString &udi) {
                finishRemoving(udi, error, data);
            }, Qt::UniqueConnection);
            started = optical->eject();
        } else {
            started = access->teardown();
        }
        if (!started) finishRemoving(id, Solid::OperationFailed, {});
    }
    // The phone plugged in that a KDE address for it names, as Plasma's device
    // pop-up hands one over, or nothing for any other address.
    QString phoneForAddress(const QUrl &url) {
        const auto path = url.path();
        if (url.scheme() != QLatin1String("mtp") || !path.startsWith(QLatin1String("udi="))) return {};
        for (const auto &drive : drives()) {
            if (!drive.phone || drive.id.startsWith(connectedPrefix())) continue;
            const auto rest = path.mid(4);
            if (rest == drive.id || rest.startsWith(drive.id + QLatin1Char('/'))) return drive.id;
        }
        return {};
    }
Q_SIGNALS:
    void changed();
    void opened(const QString &id, const QString &path);
    void removed(const QString &id, const QString &label);
    void failed(const QString &id, const QString &message);
private Q_SLOTS:
    void connectedChanged() { loadConnected(); }
private:
    // The rule KDE's places model lists devices by, a phone by cable included
    // where KDE can browse one.
    static const Solid::Predicate &listed() {
        static const auto predicate = [] {
            QString rule = DriveRules::storageRule();
            if (KProtocolInfo::isKnownProtocol(QStringLiteral("mtp")))
                rule = QLatin1Char('[') + rule + QStringLiteral(" OR PortableMediaPlayer.supportedProtocols == 'mtp' ]");
            return Solid::Predicate::fromString(rule);
        }();
        return predicate;
    }
    static bool isCabledPhone(const Solid::Device &device) {
        const auto *player = device.as<Solid::PortableMediaPlayer>();
        return player && !device.is<Solid::StorageAccess>()
            && player->supportedProtocols().contains(QLatin1String("mtp"));
    }
    static Solid::Device ancestor(const Solid::Device &device, Solid::DeviceInterface::Type type) {
        return DriveRules::ancestor(device, type);
    }
    // Solid drops a device's interfaces, and every connection to them, once
    // nothing holds the device, so each one Files listens to is held.
    Solid::Device held(const QString &udi) {
        if (const auto found = m_held.constFind(udi); found != m_held.constEnd()) return *found;
        const Solid::Device device(udi);
        watch(device);
        return device;
    }
    void start() {
        if (m_started) return;
        m_started = true;
        auto *notifier = Solid::DeviceNotifier::instance();
        connect(notifier, &Solid::DeviceNotifier::deviceAdded, this, [this] { reload(); });
        connect(notifier, &Solid::DeviceNotifier::deviceRemoved, this, [this](const QString &udi) {
            // A drive powered off after its unmount leaves as it is made safe.
            if (m_removing.contains(udi)) finishRemoving(udi, Solid::NoError, {});
            m_opening.remove(udi);
            m_held.remove(udi);
            m_phonePaths.remove(udi);
            reload();
        });
        watchConnected();
        reload();
    }
    void watch(const Solid::Device &device) {
        auto *access = device.as<Solid::StorageAccess>();
        if (!access || m_held.contains(device.udi())) return;
        m_held.insert(device.udi(), device);
        const auto udi = device.udi();
        connect(access, &Solid::StorageAccess::accessibilityChanged, this, [this, udi](bool accessible) {
            if (accessible && m_opening.contains(udi)) finishOpening(udi, Solid::NoError, {});
            else if (!accessible && m_removing.contains(udi)) finishRemoving(udi, Solid::NoError, {});
            reload();
        });
        connect(access, &Solid::StorageAccess::setupDone, this, [this](Solid::ErrorType error, const QVariant &data, const QString &id) {
            finishOpening(id, error, data);
        });
        connect(access, &Solid::StorageAccess::teardownDone, this, [this](Solid::ErrorType error, const QVariant &data, const QString &id) {
            finishRemoving(id, error, data);
        });
    }
    static QString reason(const QVariant &data) {
        const auto text = data.toString().trimmed();
        return text.isEmpty() ? QString() : QStringLiteral(" ") + text;
    }
    void finishOpening(const QString &id, Solid::ErrorType error, const QVariant &data) {
        if (!m_opening.remove(id)) return;
        auto device = held(id);
        auto *access = device.as<Solid::StorageAccess>();
        if (error == Solid::NoError && access && access->isAccessible()) Q_EMIT opened(id, access->filePath());
        else if (error == Solid::NoError) m_opening.insert(id); // mounted, not yet reported
        else if (error != Solid::UserCanceled) Q_EMIT failed(id, i18n("“%1” could not be opened.%2", device.description(), reason(data)));
        reload();
    }
    void finishRemoving(const QString &id, Solid::ErrorType error, const QVariant &data) {
        if (!m_removing.remove(id)) return;
        const auto label = m_labels.take(id);
        if (error == Solid::NoError) Q_EMIT removed(id, label);
        else if (error != Solid::UserCanceled) Q_EMIT failed(id, i18n("“%1” could not be ejected.%2", label, reason(data)));
        reload();
    }

    // Asks over the session bus without waiting, and answers on the reply.
    template<typename Answer>
    void ask(const QString &service, const QString &path, const QString &interface, const QString &method,
             const QVariantList &arguments, int timeout, Answer answer) {
        auto call = QDBusMessage::createMethodCall(service, path, interface, method);
        call.setArguments(arguments);
        auto *watcher = new QDBusPendingCallWatcher(QDBusConnection::sessionBus().asyncCall(call, timeout), this);
        connect(watcher, &QDBusPendingCallWatcher::finished, this, [watcher, answer]() {
            watcher->deleteLater();
            answer(watcher->reply());
        });
    }
    static bool answered(const QDBusMessage &reply) { return reply.type() == QDBusMessage::ReplyMessage; }

    // A phone by cable: kio-fuse mounts KDE's address for it and answers with a
    // local folder, kept while the phone stays plugged in.
    void openCabled(const Solid::Device &device) {
        const auto udi = device.udi(), name = device.description();
        if (const auto path = m_phonePaths.value(udi); !path.isEmpty()) { Q_EMIT opened(udi, path); return; }
        m_opening.insert(udi); reload();
        ask(QStringLiteral("org.kde.KIOFuse"), QStringLiteral("/org/kde/KIOFuse"), QStringLiteral("org.kde.KIOFuse.VFS"),
            QStringLiteral("mountUrl"), {QStringLiteral("mtp:udi=%1").arg(udi)}, PhoneTimeout, [this, udi, name](const QDBusMessage &reply) {
            if (!m_opening.remove(udi)) return; // unplugged meanwhile
            const auto path = answered(reply) ? reply.arguments().value(0).toString() : QString();
            if (!path.isEmpty()) m_phonePaths.insert(udi, path);
            reload();
            if (!path.isEmpty()) Q_EMIT opened(udi, path);
            else if (reply.errorName() == QLatin1String("org.freedesktop.DBus.Error.ServiceUnknown"))
                Q_EMIT failed(udi, i18n("Files needs kio-fuse to open “%1” by cable.", name));
            else Q_EMIT failed(udi, i18n("“%1” could not be opened. Unlock it, and let this computer reach its files.", name));
        });
    }

    // KDE Connect's paired phones in reach that share their files. Its daemon is
    // only asked while it runs; Files never starts it.
    // A phone's files are mounted whole, but it lets only the storage it shares
    // be read: `storage` is where it opens, once mounted.
    struct Connected { QString id, name, mountPoint, storage; bool mounted = false; };
    static QString connectedPrefix() { return QStringLiteral("kdeconnect:"); }
    static QString connectService() { return QStringLiteral("org.kde.kdeconnect"); }
    static QString daemonPath() { return QStringLiteral("/modules/kdeconnect"); }
    static QString sftpInterface() { return QStringLiteral("org.kde.kdeconnect.device.sftp"); }
    static QString devicePath(const QString &id) { return daemonPath() + QStringLiteral("/devices/") + id; }
    static QString sftpPath(const QString &id) { return devicePath(id) + QStringLiteral("/sftp"); }
    void watchConnected() {
        auto bus = QDBusConnection::sessionBus();
        auto *owner = new QDBusServiceWatcher(connectService(), bus, QDBusServiceWatcher::WatchForOwnerChange, this);
        connect(owner, &QDBusServiceWatcher::serviceOwnerChanged, this, [this] { loadConnected(); });
        for (const auto *signal : {"deviceAdded", "deviceRemoved", "deviceVisibilityChanged", "deviceListChanged"})
            bus.connect(connectService(), daemonPath(), QStringLiteral("org.kde.kdeconnect.daemon"), QString::fromLatin1(signal), this, SLOT(connectedChanged()));
        // Any phone's files mounted or unmounted, whichever asked.
        for (const auto *signal : {"mounted", "unmounted"})
            bus.connect(connectService(), QString(), sftpInterface(), QString::fromLatin1(signal), this, SLOT(connectedChanged()));
        loadConnected();
    }
    void loadConnected() {
        const auto generation = ++m_connectedGeneration;
        const auto settle = [this, generation](const QList<Connected> &found) {
            if (generation != m_connectedGeneration) return;
            m_connected = found;
            reload();
        };
        ask(QStringLiteral("org.freedesktop.DBus"), QStringLiteral("/org/freedesktop/DBus"), QStringLiteral("org.freedesktop.DBus"),
            QStringLiteral("NameHasOwner"), {connectService()}, -1, [this, settle](const QDBusMessage &running) {
            if (!answered(running) || !running.arguments().value(0).toBool()) { settle({}); return; }
            ask(connectService(), daemonPath(), QStringLiteral("org.kde.kdeconnect.daemon"), QStringLiteral("devices"), {true, true}, -1,
                [this, settle](const QDBusMessage &listed) {
                const auto ids = answered(listed) ? listed.arguments().value(0).toStringList() : QStringList();
                if (ids.isEmpty()) { settle({}); return; }
                struct Gathering { qsizetype waiting; QList<Connected> found; };
                auto gathering = std::make_shared<Gathering>(Gathering{ids.size(), {}});
                const auto done = [gathering, settle](std::optional<Connected> phone) {
                    if (phone) gathering->found.append(*phone);
                    if (--gathering->waiting == 0) settle(gathering->found);
                };
                for (const auto &id : ids) gatherConnected(id, done);
            });
        });
    }
    // One phone's name and where its files are mounted; a phone that does not
    // share its files has no sftp object and is left out.
    template<typename Done>
    void gatherConnected(const QString &id, Done done) {
        ask(connectService(), devicePath(id), QStringLiteral("org.freedesktop.DBus.Properties"), QStringLiteral("Get"),
            {QStringLiteral("org.kde.kdeconnect.device"), QStringLiteral("name")}, -1, [this, id, done](const QDBusMessage &named) {
            const auto name = named.arguments().value(0).value<QDBusVariant>().variant().toString();
            if (!answered(named) || name.isEmpty()) { done(std::nullopt); return; }
            ask(connectService(), sftpPath(id), sftpInterface(), QStringLiteral("mountPoint"), {}, -1, [this, id, name, done](const QDBusMessage &where) {
                const auto mountPoint = where.arguments().value(0).toString();
                if (!answered(where) || mountPoint.isEmpty()) { done(std::nullopt); return; }
                ask(connectService(), sftpPath(id), sftpInterface(), QStringLiteral("isMounted"), {}, -1, [this, id, name, mountPoint, done](const QDBusMessage &mounted) {
                    if (!answered(mounted) || !mounted.arguments().value(0).toBool()) { done(Connected{id, name, mountPoint, {}, false}); return; }
                    askStorage(id, [id, name, mountPoint, done](const QString &storage) { done(Connected{id, name, mountPoint, storage, true}); });
                });
            });
        });
    }
    // The storage a mounted phone shares, the outermost first, as a
    // phone's own storage holds its camera folder.
    template<typename Answer>
    void askStorage(const QString &id, Answer answer) {
        ask(connectService(), sftpPath(id), sftpInterface(), QStringLiteral("getDirectories"), {}, -1, [answer](const QDBusMessage &reply) {
            auto folders = answered(reply) ? qdbus_cast<QVariantMap>(reply.arguments().value(0)).keys() : QStringList();
            std::sort(folders.begin(), folders.end(), [](const QString &a, const QString &b) {
                return a.size() != b.size() ? a.size() < b.size() : a < b;
            });
            answer(folders.value(0));
        });
    }
    // Whether a folder is one a phone through KDE Connect is mounted on, which
    // Solid also lists as a network share.
    bool withinConnected(const QString &path) const {
        for (const auto &phone : m_connected)
            if (path == phone.mountPoint || path.startsWith(phone.mountPoint + QLatin1Char('/'))) return true;
        return false;
    }
    static QString opensAt(const Connected &phone) { return phone.storage.isEmpty() ? phone.mountPoint : phone.storage; }
    Connected findConnected(const QString &id) const {
        for (const auto &phone : m_connected) if (connectedPrefix() + phone.id == id) return phone;
        return {};
    }
    void openConnected(const QString &id) {
        const auto phone = findConnected(id);
        if (phone.id.isEmpty()) return;
        if (phone.mounted) { Q_EMIT opened(id, opensAt(phone)); return; }
        // KDE Connect mounts a phone's files with sshfs, which it leaves optional.
        if (QStandardPaths::findExecutable(QStringLiteral("sshfs")).isEmpty()) {
            Q_EMIT failed(id, i18n("Files needs sshfs to open “%1” over Wi-Fi.", phone.name));
            return;
        }
        m_opening.insert(id); reload();
        ask(connectService(), sftpPath(phone.id), sftpInterface(), QStringLiteral("mountAndWait"), {}, PhoneTimeout,
            [this, id, phone](const QDBusMessage &reply) {
            if (answered(reply) && reply.arguments().value(0).toBool()) {
                askStorage(phone.id, [this, id, phone](const QString &storage) {
                    if (!m_opening.remove(id)) return;
                    auto opened = phone;
                    opened.mounted = true; opened.storage = storage;
                    for (auto &known : m_connected) if (known.id == phone.id) known = opened;
                    reload();
                    Q_EMIT this->opened(id, opensAt(opened));
                });
                return;
            }
            ask(connectService(), sftpPath(phone.id), sftpInterface(), QStringLiteral("getMountError"), {}, -1,
                [this, id, phone](const QDBusMessage &error) {
                if (!m_opening.remove(id)) return;
                reload();
                const auto text = error.arguments().value(0).toString();
                // The phone refuses until KDE Connect there may reach its files.
                if (text.contains(QLatin1String("ermission")))
                    Q_EMIT failed(id, i18n("Allow KDE Connect on “%1” to reach its files, then open it again.", phone.name));
                else Q_EMIT failed(id, i18n("“%1” could not be opened.%2", phone.name, reason(text)));
            });
        });
    }

    void reload() {
        const auto hidden = DriveRules::hiddenInDolphin();
        QList<Drive> drives;
        for (const auto &device : Solid::Device::listFromQuery(listed())) {
            if (hidden.devices.contains(device.udi())) continue;
            if (isCabledPhone(device)) {
                if (hidden.removable) continue;
                const auto path = m_phonePaths.value(device.udi());
                drives.append(Drive{device.udi(), device.description(), QStringLiteral("smartphone"), path, !path.isEmpty(), true,
                    m_opening.contains(device.udi()), false, true});
                continue;
            }
            auto *access = device.as<Solid::StorageAccess>();
            if (!access || (access->isAccessible() && withinConnected(access->filePath()))) continue;
            const bool removable = DriveRules::removable(device);
            if (removable ? hidden.removable : hidden.fixed) continue;
            watch(device);
            const bool mounted = access->isAccessible();
            drives.append(Drive{device.udi(), device.description(), device.icon(), mounted ? access->filePath() : QString(), mounted, removable,
                m_opening.contains(device.udi()), m_removing.contains(device.udi())});
        }
        for (const auto &phone : std::as_const(m_connected)) {
            const auto id = connectedPrefix() + phone.id;
            drives.append(Drive{id, phone.name, QStringLiteral("smartphone"), phone.mounted ? opensAt(phone) : QString(), phone.mounted, true,
                m_opening.contains(id), false, true});
        }
        // Built-in drives first, as KDE lists them, then each group by name.
        QCollator collator; collator.setNumericMode(true); collator.setCaseSensitivity(Qt::CaseInsensitive);
        std::stable_sort(drives.begin(), drives.end(), [&collator](const Drive &a, const Drive &b) {
            return a.removable != b.removable ? !a.removable : collator.compare(a.label, b.label) < 0;
        });
        if (drives == m_drives) return;
        m_drives = drives;
        Q_EMIT changed();
    }
    // A phone may ask its owner first, on its own screen.
    static constexpr int PhoneTimeout = 60000;
    bool m_started = false;
    QList<Drive> m_drives;
    QHash<QString, Solid::Device> m_held;
    QSet<QString> m_opening, m_removing;
    QHash<QString, QString> m_labels;
    // Each cabled phone opened, by device, and the folder kio-fuse gave it.
    QHash<QString, QString> m_phonePaths;
    QList<Connected> m_connected;
    quint64 m_connectedGeneration = 0;
};
