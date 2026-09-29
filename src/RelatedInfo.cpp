#include "RelatedInfo.h"
#include <KApplicationTrader>
#include <KService>
#include <Solid/Device>
#include <Solid/StorageAccess>
#include <Solid/StorageDrive>
#include <Solid/StorageVolume>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QProcess>
#include <QProcessEnvironment>
#include <QStandardPaths>
#include <QTimer>

namespace {
QVariant row(const QString &label, const QString &status) {
    return QVariantMap{{QStringLiteral("label"), label}, {QStringLiteral("status"), status}};
}
}

RelatedInfo::RelatedInfo(QObject *parent) : QObject(parent) {
    connect(&m_bluetooth, &BluetoothContext::changed, this, &RelatedInfo::changed);
}

QString RelatedInfo::keyForSetting(const QString &id) {
    // Match stable module IDs, not translated titles or search text.
    const QHash<QString, QString> keys = {
        {QStringLiteral("kcm_bluetooth"), QStringLiteral("bluetooth")},
        {QStringLiteral("kcm_pulseaudio"), QStringLiteral("audio")},
        {QStringLiteral("kcm_networkmanagement"), QStringLiteral("network")},
        {QStringLiteral("kcm_kscreen"), QStringLiteral("display")},
        {QStringLiteral("kcm_powerdevilprofilesconfig"), QStringLiteral("power")},
        {QStringLiteral("kcm_mobile_power"), QStringLiteral("power")},
        {QStringLiteral("kcm_printer_manager"), QStringLiteral("printers")},
        {QStringLiteral("kcm_solid_actions"), QStringLiteral("storage")},
        {QStringLiteral("kcm_componentchooser"), QStringLiteral("defaults")},
        {QStringLiteral("kcm_nightlight"), QStringLiteral("nightlight")},
        {QStringLiteral("kcm_kdeconnect"), QStringLiteral("connect")}};
    for (auto it = keys.cbegin(); it != keys.cend(); ++it)
        if (id == it.key() || id.endsWith(QLatin1Char('_') + it.key())) return it.value();
    return {};
}

QVariantList RelatedInfo::items(const QString &key) {
    if (key == QStringLiteral("bluetooth")) {
        QVariantList rows;
        for (const auto &name : m_bluetooth.connectedDevices()) rows.append(row(name, tr("Connected")));
        return rows;
    }
    if (!key.isEmpty() && !m_requested.contains(key)) {
        m_requested.insert(key);
        // Do not emit changes or block inside a QML binding evaluation.
        QTimer::singleShot(0, this, [this, key]() { request(key); });
    }
    return m_rows.value(key);
}

void RelatedInfo::publish(const QString &key, QVariantList rows) {
    // Never let one context group monopolize the search surface.
    if (rows.size() > 4) {
        const auto extra = rows.size() - 3;
        rows = rows.mid(0, 3);
        rows.append(row(tr("%1 more in settings").arg(extra), {}));
    }
    m_rows[key] = rows;
    Q_EMIT changed();
}

void RelatedInfo::process(const QString &key, const QString &program,
                          const QStringList &args, Parse parse) {
    const auto executable = QStandardPaths::findExecutable(program);
    if (executable.isEmpty()) return;
    auto *job = new QProcess(this);
    auto environment = QProcessEnvironment::systemEnvironment();
    environment.insert(QStringLiteral("LC_ALL"), QStringLiteral("C"));
    job->setProcessEnvironment(environment);
    auto *timeout = new QTimer(job);
    timeout->setSingleShot(true);
    connect(timeout, &QTimer::timeout, job, [job]() { job->kill(); });
    connect(job, &QProcess::readyReadStandardOutput, job, [job]() {
        if (job->bytesAvailable() > 1024 * 1024) job->kill();
    });
    connect(job, &QProcess::finished, this, [this, key, job, parse, timeout](int code, QProcess::ExitStatus status) {
        timeout->stop();
        if (code == 0 && status == QProcess::NormalExit) publish(key, parse(job->readAllStandardOutput()));
        job->deleteLater();
    });
    connect(job, &QProcess::errorOccurred, job, [job](QProcess::ProcessError error) {
        if (error == QProcess::FailedToStart) job->deleteLater();
    });
    job->start(executable, args, QIODevice::ReadOnly);
    timeout->start(2000);
}

void RelatedInfo::properties(const QString &key, const QString &service, const QString &path,
                            const QString &interface, bool system,
                            std::function<QVariantList(const QVariantMap &)> parse) {
    auto call = QDBusMessage::createMethodCall(service, path,
        QStringLiteral("org.freedesktop.DBus.Properties"), QStringLiteral("GetAll"));
    call.setAutoStartService(false);
    call.setArguments({interface});
    auto bus = system ? QDBusConnection::systemBus() : QDBusConnection::sessionBus();
    auto *watcher = new QDBusPendingCallWatcher(bus.asyncCall(call, 1500), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this, watcher, key, parse]() {
        QDBusPendingReply<QVariantMap> reply = *watcher;
        if (!reply.isError()) publish(key, parse(reply.value()));
        watcher->deleteLater();
    });
}

QVariantList RelatedInfo::audioRows(const QByteArray &json, const QString &kind) {
    QVariantList rows;
    for (const auto &value : QJsonDocument::fromJson(json).array()) {
        const auto object = value.toObject();
        if (object.value(QStringLiteral("name")).toString().endsWith(QStringLiteral(".monitor"))) continue;
        const auto name = object.value(QStringLiteral("description")).toString();
        if (name.isEmpty()) continue;
        QString status = kind;
        if (object.value(QStringLiteral("mute")).toBool()) status += tr(" · Muted");
        else if (object.value(QStringLiteral("state")).toString() == QStringLiteral("RUNNING")) status += tr(" · In use");
        rows.append(row(name, status));
    }
    return rows;
}

QVariantList RelatedInfo::displayRows(const QByteArray &json) {
    QVariantList rows;
    for (const auto &value : QJsonDocument::fromJson(json).object().value(QStringLiteral("outputs")).toArray()) {
        const auto output = value.toObject();
        if (!output.value(QStringLiteral("connected")).toBool()) continue;
        QString status = tr("Disabled");
        if (output.value(QStringLiteral("enabled")).toBool()) {
            status = tr("Enabled");
            for (const auto &modeValue : output.value(QStringLiteral("modes")).toArray()) {
                const auto mode = modeValue.toObject();
                if (mode.value(QStringLiteral("id")) != output.value(QStringLiteral("currentModeId"))) continue;
                status = mode.value(QStringLiteral("name")).toString();
                status += tr(" · %1% scale").arg(qRound(output.value(QStringLiteral("scale")).toDouble(1) * 100));
            }
        }
        rows.append(row(output.value(QStringLiteral("name")).toString(), status));
    }
    return rows;
}

QVariantList RelatedInfo::networkRows(const QByteArray &text) {
    QVariantList rows;
    for (const auto &line : QString::fromUtf8(text).split(QLatin1Char('\n'), Qt::SkipEmptyParts)) {
        auto parts = line.split(QLatin1Char(':'));
        if (parts.size() < 3) continue;
        parts.removeLast(); // Device interface; no addresses or secrets.
        const auto type = parts.takeLast();
        if (type == QStringLiteral("loopback") || type == QStringLiteral("bridge")) continue;
        rows.append(row(parts.join(QLatin1Char(':')), type == QStringLiteral("vpn")
            ? tr("VPN · Active") : tr("Connected")));
    }
    return rows;
}

void RelatedInfo::request(const QString &key) {
    if (key == QStringLiteral("network")) {
        process(key, QStringLiteral("nmcli"), {QStringLiteral("-t"), QStringLiteral("--escape"), QStringLiteral("no"),
            QStringLiteral("-f"), QStringLiteral("NAME,TYPE,DEVICE"), QStringLiteral("connection"), QStringLiteral("show"), QStringLiteral("--active")}, networkRows);
    } else if (key == QStringLiteral("display")) {
        process(key, QStringLiteral("kscreen-doctor"), {QStringLiteral("-j")}, displayRows);
    } else if (key == QStringLiteral("audio")) {
        for (const auto &kind : {QStringLiteral("sinks"), QStringLiteral("sources")}) {
            process(key + kind, QStringLiteral("pactl"), {QStringLiteral("--format=json"), QStringLiteral("list"), kind},
                [this, key, kind](const QByteArray &data) {
                    const auto rows = audioRows(data, kind == QStringLiteral("sinks") ? tr("Output") : tr("Microphone"));
                    m_rows[key + kind] = rows;
                    publish(key, m_rows.value(key + QStringLiteral("sinks")) + m_rows.value(key + QStringLiteral("sources")));
                    return rows;
                });
        }
    } else if (key == QStringLiteral("power")) {
        properties(key + QStringLiteral("battery"), QStringLiteral("org.freedesktop.UPower"), QStringLiteral("/org/freedesktop/UPower/devices/DisplayDevice"),
            QStringLiteral("org.freedesktop.UPower.Device"), true, [this, key](const QVariantMap &p) {
                QVariantList rows;
                if (p.value(QStringLiteral("IsPresent")).toBool()) rows.append(row(tr("Battery"),
                    tr("%1% · %2").arg(qRound(p.value(QStringLiteral("Percentage")).toDouble()))
                    .arg(p.value(QStringLiteral("State")).toInt() == 1 ? tr("Charging") : tr("Not charging"))));
                m_rows[key + QStringLiteral("battery")] = rows;
                publish(key, rows + m_rows.value(key + QStringLiteral("profile")));
                return rows;
            });
        process(key + QStringLiteral("profile"), QStringLiteral("powerprofilesctl"), {QStringLiteral("get")},
            [this, key](const QByteArray &data) {
                QVariantList rows;
                const auto profile = QString::fromUtf8(data).trimmed();
                if (!profile.isEmpty()) rows.append(row(tr("System power profile"), profile));
                m_rows[key + QStringLiteral("profile")] = rows;
                publish(key, m_rows.value(key + QStringLiteral("battery")) + rows);
                return rows;
            });
    } else if (key == QStringLiteral("nightlight")) {
        properties(key, QStringLiteral("org.kde.KWin"), QStringLiteral("/org/kde/KWin/NightLight"),
            QStringLiteral("org.kde.KWin.NightLight"), false, [](const QVariantMap &p) {
                if (!p.value(QStringLiteral("available")).toBool()) return QVariantList{};
                return QVariantList{row(tr("Night Light"), !p.value(QStringLiteral("enabled")).toBool() ? tr("Disabled")
                    : p.value(QStringLiteral("running")).toBool() ? tr("Active · %1 K").arg(p.value(QStringLiteral("currentTemperature")).toUInt()) : tr("Enabled · Not active"))};
            });
    } else if (key == QStringLiteral("connect")) {
        process(key, QStringLiteral("kdeconnect-cli"), {QStringLiteral("--list-available"), QStringLiteral("--name-only")}, [](const QByteArray &data) {
            QVariantList rows;
            for (const auto &name : QString::fromUtf8(data).split(QLatin1Char('\n'), Qt::SkipEmptyParts)) rows.append(row(name, tr("Reachable")));
            return rows;
        });
    } else if (key == QStringLiteral("printers")) {
        process(key, QStringLiteral("lpstat"), {QStringLiteral("-p")}, [](const QByteArray &data) {
            QVariantList rows;
            for (const auto &line : QString::fromUtf8(data).split(QLatin1Char('\n'))) {
                if (!line.startsWith(QStringLiteral("printer "))) continue;
                const auto name = line.section(QLatin1Char(' '), 1, 1);
                rows.append(row(name, line.contains(QStringLiteral("disabled")) ? tr("Disabled")
                    : line.contains(QStringLiteral("now printing")) ? tr("Printing") : tr("Idle")));
            }
            return rows;
        });
    } else if (key == QStringLiteral("defaults")) {
        QVariantList rows;
        for (const auto &mime : {QStringLiteral("x-scheme-handler/https"), QStringLiteral("x-scheme-handler/mailto"), QStringLiteral("inode/directory")}) {
            const auto service = KApplicationTrader::preferredService(mime);
            if (service) rows.append(row(service->name(), mime.endsWith(QStringLiteral("https")) ? tr("Browser")
                : mime.endsWith(QStringLiteral("mailto")) ? tr("Mail") : tr("File manager")));
        }
        publish(key, rows);
    } else if (key == QStringLiteral("storage")) {
        QVariantList rows;
        for (const auto &device : Solid::Device::listFromType(Solid::DeviceInterface::StorageVolume)) {
            auto parent = device.parent();
            while (parent.isValid() && !parent.is<Solid::StorageDrive>()) parent = parent.parent();
            const auto *drive = parent.as<Solid::StorageDrive>();
            const auto *volume = device.as<Solid::StorageVolume>();
            const auto *access = device.as<Solid::StorageAccess>();
            if (!drive || !volume || (!drive->isRemovable() && !drive->isHotpluggable())) continue;
            rows.append(row(volume->label().isEmpty() ? device.description() : volume->label(),
                access && access->isAccessible() ? tr("Mounted") : tr("Not mounted")));
        }
        publish(key, rows);
    }
}
