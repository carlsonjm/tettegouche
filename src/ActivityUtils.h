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
inline QString fileIdentity(const QString &path) {
    struct stat s{};
    if (path.isEmpty() || ::lstat(QFile::encodeName(path).constData(), &s) || !S_ISREG(s.st_mode)) return {};
    return QString::number(s.st_dev) + QLatin1Char(':') + QString::number(s.st_ino);
}
}
