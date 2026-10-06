#pragma once
#include <QVariantMap>
#include <QDBusArgument>
#include <QDBusVariant>
#include <QDir>
#include <QFile>
#include <QUrl>
#include <chrono>
#include <sys/stat.h>

namespace Ambient {
inline qint64 nowUs() {
    return std::chrono::duration_cast<std::chrono::microseconds>(
        std::chrono::steady_clock::now().time_since_epoch()).count();
}
inline QVariantMap map(const QVariant &v) {
    if (v.metaType() == QMetaType::fromType<QDBusArgument>()) return qdbus_cast<QVariantMap>(v);
    if (v.metaType() == QMetaType::fromType<QDBusVariant>()) return map(v.value<QDBusVariant>().variant());
    return v.toMap();
}
inline QString localPath(const QVariant &v) {
    const QUrl url(v.toString());
    return url.isLocalFile() ? QDir::cleanPath(url.toLocalFile()) : QString();
}
// Whether a path lies on a network or user-space mount, read from the mount
// table alone. Such a mount can hang while its server is away, and a stat
// there would hold the panel with it, so Ambient never looks at those files.
inline bool onRemoteMount(const QString &path, const QByteArray &mounts) {
    static const QList<QByteArray> remote{"nfs", "nfs4", "cifs", "smb3", "smbfs", "9p", "ceph", "afs",
        "davfs", "glusterfs", "ncpfs", "sshfs"};
    const auto target = QFile::encodeName(QDir::cleanPath(path));
    qsizetype longest = -1;
    bool far = false;
    for (const auto &line : mounts.split('\n')) {
        const auto fields = line.split(' ');
        if (fields.size() < 3) continue;
        // The table writes spaces and the like in a mount point as octal escapes.
        QByteArray point;
        for (qsizetype i = 0; i < fields[1].size(); ++i) {
            if (fields[1][i] == '\\' && i + 3 < fields[1].size()) {
                point += char(fields[1].mid(i + 1, 3).toInt(nullptr, 8)); i += 3;
            } else point += fields[1][i];
        }
        const bool under = target == point || point == "/"
            || (target.startsWith(point) && target.at(point.size()) == '/');
        if (!under || point.size() < longest) continue;
        longest = point.size();
        far = remote.contains(fields[2]) || fields[2].startsWith("fuse.");
    }
    return far;
}
inline bool onRemoteMount(const QString &path) {
    QFile table(QStringLiteral("/proc/self/mounts"));
    return table.open(QIODevice::ReadOnly) && onRemoteMount(path, table.readAll());
}
inline QString fileIdentity(const QString &path) {
    struct stat s{};
    if (path.isEmpty() || onRemoteMount(path) || ::lstat(QFile::encodeName(path).constData(), &s) || !S_ISREG(s.st_mode)) return {};
    return QString::number(s.st_dev) + QLatin1Char(':') + QString::number(s.st_ino);
}
}
