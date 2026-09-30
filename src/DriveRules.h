#pragma once

#include <Solid/Device>
#include <Solid/Predicate>
#include <Solid/StorageDrive>
#include <QFile>
#include <QSet>
#include <QStandardPaths>
#include <QXmlStreamReader>

// Which storage KDE lists as drives, shared by Files and Ambient.
namespace DriveRules {

// The rule KDE's places model lists storage by.
inline QString storageRule() {
    return QStringLiteral(
        "[[[[ StorageVolume.ignored == false AND [ StorageVolume.usage == 'FileSystem' OR StorageVolume.usage == 'Encrypted' ]]"
        " OR [ IS StorageAccess AND StorageDrive.driveType == 'Floppy' ]]"
        " OR OpticalDisc.availableContent & 'Audio' ] OR StorageAccess.ignored == false ]");
}
inline const Solid::Predicate &storage() {
    static const auto predicate = Solid::Predicate::fromString(storageRule());
    return predicate;
}

// The device, or the nearest one it sits on, that has the interface.
inline Solid::Device ancestor(const Solid::Device &device, Solid::DeviceInterface::Type type) {
    for (auto parent = device; parent.isValid(); parent = parent.parent())
        if (parent.isDeviceInterface(type)) return parent;
    return {};
}

// Plugged in rather than built in: an optical disc, or a volume on removable
// or hot-pluggable media, such as a USB stick or a memory card.
inline bool removable(const Solid::Device &device) {
    if (ancestor(device, Solid::DeviceInterface::OpticalDrive).isValid()) return true;
    const auto driveDevice = ancestor(device, Solid::DeviceInterface::StorageDrive);
    const auto *drive = driveDevice.as<Solid::StorageDrive>();
    return drive && (drive->isRemovable() || drive->isHotpluggable());
}

// What the person hid in Dolphin's places, by device and by group; read
// afresh each time, since Dolphin writes it at any time.
struct Hidden { QSet<QString> devices; bool fixed = false, removable = false; };
inline Hidden hiddenInDolphin() {
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

}
