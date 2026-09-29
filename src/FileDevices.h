#pragma once

#include <Solid/Device>
#include <Solid/DeviceNotifier>
#include <Solid/OpticalDrive>
#include <Solid/Predicate>
#include <Solid/StorageAccess>
#include <Solid/StorageDrive>
#include <QCollator>
#include <QFile>
#include <QSet>
#include <QStandardPaths>
#include <QXmlStreamReader>
#include <algorithm>

// The drives Files lists beside its places: those KDE's file dialogs and Dolphin
// list, less any the person hid there, as they come and go. Nothing is asked of
// the system until the list is first wanted, so the launcher never waits on it
// to start. KDE's own places model is not used: it answers a failed lookup of its
// own with a widget message box, which aborts a process without widgets.
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
        bool busy() const { return opening || ejecting; }
        bool operator==(const Drive &) const = default;
    };
    using QObject::QObject;
    QList<Drive> drives() { start(); return m_drives; }
    // Opens a drive, mounting it first if it is not; answers with opened or failed.
    void open(const QString &id) {
        start();
        auto device = held(id);
        auto *access = device.as<Solid::StorageAccess>();
        if (!access || m_opening.contains(id) || m_removing.contains(id)) return;
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
Q_SIGNALS:
    void changed();
    void opened(const QString &id, const QString &path);
    void removed(const QString &id, const QString &label);
    void failed(const QString &id, const QString &message);
private:
    // The rule KDE's places model lists devices by, less phones, which Files
    // does not browse yet.
    static const Solid::Predicate &listed() {
        static const auto predicate = Solid::Predicate::fromString(QStringLiteral(
            "[[[[ StorageVolume.ignored == false AND [ StorageVolume.usage == 'FileSystem' OR StorageVolume.usage == 'Encrypted' ]]"
            " OR [ IS StorageAccess AND StorageDrive.driveType == 'Floppy' ]]"
            " OR OpticalDisc.availableContent & 'Audio' ] OR StorageAccess.ignored == false ]"));
        return predicate;
    }
    // The device, or the nearest one it sits on, that has the interface.
    static Solid::Device ancestor(const Solid::Device &device, Solid::DeviceInterface::Type type) {
        for (auto parent = device; parent.isValid(); parent = parent.parent())
            if (parent.isDeviceInterface(type)) return parent;
        return {};
    }
    // Solid drops a device's interfaces, and every connection to them, once
    // nothing holds the device, so each one Files listens to is held.
    Solid::Device held(const QString &udi) {
        if (const auto found = m_held.constFind(udi); found != m_held.constEnd()) return *found;
        const Solid::Device device(udi);
        watch(device);
        return device;
    }
    // What the person hid in Dolphin's places, by device and by group; read
    // afresh with every change, since Dolphin writes it at any time.
    struct Hidden { QSet<QString> devices; bool fixed = false, removable = false; };
    static Hidden hiddenInDolphin() {
        Hidden hidden;
        QFile file(QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation) + QStringLiteral("/user-places.xbel"));
        if (!file.open(QIODevice::ReadOnly)) return hidden;
        QXmlStreamReader xml(&file);
        QString udi;
        bool isHidden = false;
        while (!xml.atEnd()) {
            xml.readNext();
            const auto name = xml.name();
            if (xml.isStartElement()) {
                if (name == QLatin1String("bookmark") || name == QLatin1String("separator")) { udi.clear(); isHidden = false; }
                else if (name == QLatin1String("UDI")) udi = xml.readElementText();
                else if (name == QLatin1String("IsHidden")) isHidden = xml.readElementText() == QLatin1String("true");
                else if (name == QLatin1String("GroupState-Devices-IsHidden")) hidden.fixed = xml.readElementText() == QLatin1String("true");
                else if (name == QLatin1String("GroupState-RemovableDevices-IsHidden")) hidden.removable = xml.readElementText() == QLatin1String("true");
            } else if (xml.isEndElement() && (name == QLatin1String("bookmark") || name == QLatin1String("separator"))) {
                if (isHidden && !udi.isEmpty()) hidden.devices.insert(udi);
            }
        }
        return hidden;
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
            reload();
        });
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
        else if (error != Solid::UserCanceled) Q_EMIT failed(id, tr("“%1” could not be opened.%2").arg(device.description(), reason(data)));
        reload();
    }
    void finishRemoving(const QString &id, Solid::ErrorType error, const QVariant &data) {
        if (!m_removing.remove(id)) return;
        const auto label = m_labels.take(id);
        if (error == Solid::NoError) Q_EMIT removed(id, label);
        else if (error != Solid::UserCanceled) Q_EMIT failed(id, tr("“%1” could not be ejected.%2").arg(label, reason(data)));
        reload();
    }
    void reload() {
        const auto hidden = hiddenInDolphin();
        QList<Drive> drives;
        for (const auto &device : Solid::Device::listFromQuery(listed())) {
            auto *access = device.as<Solid::StorageAccess>();
            if (!access || hidden.devices.contains(device.udi())) continue;
            const auto driveDevice = ancestor(device, Solid::DeviceInterface::StorageDrive);
            const auto *drive = driveDevice.as<Solid::StorageDrive>();
            const bool removable = ancestor(device, Solid::DeviceInterface::OpticalDrive).isValid()
                || (drive && (drive->isRemovable() || drive->isHotpluggable()));
            if (removable ? hidden.removable : hidden.fixed) continue;
            watch(device);
            const bool mounted = access->isAccessible();
            drives.append(Drive{device.udi(), device.description(), device.icon(), mounted ? access->filePath() : QString(), mounted, removable,
                m_opening.contains(device.udi()), m_removing.contains(device.udi())});
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
    bool m_started = false;
    QList<Drive> m_drives;
    QHash<QString, Solid::Device> m_held;
    QSet<QString> m_opening, m_removing;
    QHash<QString, QString> m_labels;
};
