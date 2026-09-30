#include "DriveActivityProvider.h"
#include "ActivityUtils.h"
#include "DriveRules.h"
#include <QDBusMessage>
#include <QDBusPendingCallWatcher>
#include <QLocale>
#include <Solid/DeviceNotifier>
#include <Solid/PortableMediaPlayer>
#include <Solid/StorageAccess>
#include <Solid/StorageVolume>

namespace {
const QString Service = QStringLiteral("org.freedesktop.Notifications");
const QString Path = QStringLiteral("/org/freedesktop/Notifications");
const QString Prefix = QStringLiteral("drive:");
// The freedesktop reasons a notice closes for good: dismissed, or closed by
// its sender. One that merely expired stays in the history, actions and all.
constexpr uint Dismissed = 2, Closed = 3;
qint64 nowMs() { return Ambient::nowUs() / 1000; }
QString sizeText(qint64 bytes) {
    return bytes > 0 ? QLocale().formattedDataSize(bytes, 1, QLocale::DataSizeSIFormat) : QString();
}
}

DriveActivityProvider::DriveActivityProvider(const QDBusConnection &bus, QObject *parent, int lingerMs, bool watchDevices)
    : QObject(parent), m_bus(bus), m_lingerMs(lingerMs) {
    m_expiry.setSingleShot(true);
    connect(&m_expiry, &QTimer::timeout, this, &DriveActivityProvider::expire);
    m_bus.connect(Service, Path, Service, QStringLiteral("ActionInvoked"), this, SLOT(actionInvoked(uint,QString)));
    m_bus.connect(Service, Path, Service, QStringLiteral("NotificationClosed"), this, SLOT(notificationClosed(uint,uint)));
    if (!watchDevices) return;
    auto *notifier = Solid::DeviceNotifier::instance();
    connect(notifier, &Solid::DeviceNotifier::deviceAdded, this, &DriveActivityProvider::deviceAdded);
    connect(notifier, &Solid::DeviceNotifier::deviceRemoved, this, &DriveActivityProvider::unplugged);
}

void DriveActivityProvider::deviceAdded(const QString &udi) {
    Solid::Device device(udi);
    auto *access = device.as<Solid::StorageAccess>();
    if (!access || access->isAccessible() || device.is<Solid::PortableMediaPlayer>()
            || !DriveRules::storage().matches(device) || !DriveRules::removable(device)) return;
    const auto hidden = DriveRules::hiddenInDolphin();
    if (hidden.removable || hidden.devices.contains(udi)) return;
    m_held.insert(udi, device);
    connect(access, &Solid::StorageAccess::accessibilityChanged, this, [this, udi](bool accessible) {
        if (accessible) mounted(udi);
    });
    const auto *volume = device.as<Solid::StorageVolume>();
    plugged({udi, device.description(), device.icon(), volume ? qint64(volume->size()) : -1});
}

void DriveActivityProvider::plugged(const Drive &drive) {
    take(drive.udi);
    m_waiting.append({drive, ++m_generation, nowMs() + m_lingerMs});
    if (!m_expiry.isActive()) m_expiry.start(m_lingerMs);
    Q_EMIT changed();
}

bool DriveActivityProvider::take(const QString &udi, Waiting *taken) {
    for (auto it = m_waiting.begin(); it != m_waiting.end(); ++it) {
        if (it->drive.udi != udi) continue;
        if (taken) *taken = *it;
        m_waiting.erase(it);
        return true;
    }
    return false;
}

void DriveActivityProvider::unplugged(const QString &udi) {
    m_held.remove(udi);
    for (auto it = m_filed.begin(); it != m_filed.end();) {
        if (it.value() != udi) { ++it; continue; }
        auto call = QDBusMessage::createMethodCall(Service, Path, Service, QStringLiteral("CloseNotification"));
        call.setArguments({it.key()});
        m_bus.asyncCall(call);
        it = m_filed.erase(it);
    }
    if (take(udi)) Q_EMIT changed();
}

void DriveActivityProvider::mounted(const QString &udi) {
    if (take(udi)) Q_EMIT changed();
}

QVariantList DriveActivityProvider::activities() const {
    QVariantList rows;
    for (const auto &waiting : m_waiting) {
        QVariantMap row{{QStringLiteral("id"), QString(Prefix + waiting.drive.udi)}, {QStringLiteral("generation"), waiting.generation},
            {QStringLiteral("kind"), QStringLiteral("drive")}, {QStringLiteral("state"), QStringLiteral("waiting")},
            {QStringLiteral("title"), waiting.drive.label}, {QStringLiteral("icon"), waiting.drive.icon},
            {QStringLiteral("capabilities"), QVariantMap{{QStringLiteral("open"), true}}}};
        if (waiting.drive.sizeBytes > 0) row[QStringLiteral("sizeBytes")] = waiting.drive.sizeBytes;
        rows.append(row);
    }
    return rows;
}

void DriveActivityProvider::open(const QString &id) {
    const auto udi = id.mid(Prefix.size());
    if (!id.startsWith(Prefix) || !take(udi)) return;
    Q_EMIT changed();
    Q_EMIT openRequested(udi);
}

void DriveActivityProvider::setAside(const QString &id) {
    Waiting waiting;
    if (!id.startsWith(Prefix) || !take(id.mid(Prefix.size()), &waiting)) return;
    file(waiting.drive);
    Q_EMIT changed();
}

void DriveActivityProvider::expire() {
    const auto now = nowMs();
    qint64 next = 0;
    bool filed = false;
    for (auto it = m_waiting.begin(); it != m_waiting.end();) {
        if (it->deadline > now) {
            next = next ? qMin(next, it->deadline) : it->deadline;
            ++it;
            continue;
        }
        file(it->drive);
        it = m_waiting.erase(it);
        filed = true;
    }
    if (next) m_expiry.start(int(qMax<qint64>(1, next - now)));
    if (filed) Q_EMIT changed();
}

void DriveActivityProvider::file(const Drive &drive) {
    const auto size = sizeText(drive.sizeBytes);
    const auto body = size.isEmpty() ? tr("Plugged in") : tr("%1, plugged in").arg(size);
    const QStringList actions{QStringLiteral("default"), QString(), QStringLiteral("open"), tr("Open in Files")};
    // The freedesktop category for a device plugged in.
    const QVariantMap hints{{QStringLiteral("category"), QStringLiteral("device.added")},
        {QStringLiteral("desktop-entry"), QStringLiteral("io.github.carlsonjm.Tettegouche.Files")}};
    auto call = QDBusMessage::createMethodCall(Service, Path, Service, QStringLiteral("Notify"));
    call.setArguments({tr("Files"), uint(0), drive.icon, drive.label, body, actions, hints, -1});
    auto *watcher = new QDBusPendingCallWatcher(m_bus.asyncCall(call), this);
    const auto udi = drive.udi;
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this, watcher, udi] {
        watcher->deleteLater();
        const auto reply = watcher->reply();
        if (reply.type() == QDBusMessage::ReplyMessage) m_filed.insert(reply.arguments().value(0).toUInt(), udi);
    });
}

void DriveActivityProvider::actionInvoked(uint id, const QString &action) {
    const auto found = m_filed.constFind(id);
    if (found == m_filed.cend()) return;
    if (action == QLatin1String("open") || action == QLatin1String("default")) Q_EMIT openRequested(*found);
}

void DriveActivityProvider::notificationClosed(uint id, uint reason) {
    if (reason == Dismissed || reason == Closed) m_filed.remove(id);
}
