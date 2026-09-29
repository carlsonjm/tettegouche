#include "IncomingFileProvider.h"
#include "ActivityUtils.h"
#include <QFileInfo>
#include <QDir>
#include <sys/inotify.h>
#include <unistd.h>
#include <cerrno>
#include <limits>

namespace {
QString stamp(const struct stat &s) {
    return QStringLiteral("%1:%2:%3:%4:%5").arg(s.st_size).arg(s.st_mtim.tv_sec)
        .arg(s.st_mtim.tv_nsec).arg(s.st_ctim.tv_sec).arg(s.st_ctim.tv_nsec);
}
}

IncomingFileProvider::IncomingFileProvider(const QString &directory, QObject *parent, int quietMs, int idleMs)
    : QObject(parent), m_directory(QDir::cleanPath(directory)), m_quietMs(quietMs), m_idleMs(idleMs) {
    if (directory.isEmpty() || !QDir::isAbsolutePath(directory)) return;
    m_expiry.setSingleShot(true);
    connect(&m_expiry, &QTimer::timeout, this, &IncomingFileProvider::expire);
    m_fd = inotify_init1(IN_NONBLOCK | IN_CLOEXEC);
    if (m_fd < 0) return;
    m_parentWatch = inotify_add_watch(m_fd, QFile::encodeName(QFileInfo(m_directory).absolutePath()).constData(),
                                    IN_CREATE | IN_MOVED_TO | IN_DELETE | IN_MOVED_FROM);
    arm();
    m_notifier = new QSocketNotifier(m_fd, QSocketNotifier::Read, this);
    connect(m_notifier, &QSocketNotifier::activated, this, &IncomingFileProvider::drain);
    // No baseline admission: only subsequent create/move/write events create rows.
}
IncomingFileProvider::~IncomingFileProvider() {
    if (m_notifier) m_notifier->setEnabled(false);
    if (m_fd >= 0) ::close(m_fd);
}
void IncomingFileProvider::arm() {
    if (m_watch >= 0) inotify_rm_watch(m_fd, m_watch);
    m_watch = inotify_add_watch(m_fd, QFile::encodeName(m_directory).constData(),
        IN_CREATE | IN_MODIFY | IN_ATTRIB | IN_CLOSE_WRITE | IN_MOVED_FROM | IN_MOVED_TO
        | IN_DELETE | IN_DELETE_SELF | IN_MOVE_SELF | IN_ONLYDIR | IN_DONT_FOLLOW);
    m_entries.clear(); m_moves.clear(); m_expiry.stop();
}
void IncomingFileProvider::touch(const QString &name, bool settling) {
    const auto path = QDir(m_directory).filePath(name);
    struct stat s{};
    if (::lstat(QFile::encodeName(path).constData(), &s) || !S_ISREG(s.st_mode)) { m_entries.remove(name); return; }
    const QString identity = Ambient::fileIdentity(path);
    auto &entry = m_entries[name];
    if (entry.identity != identity) entry = {QStringLiteral("incoming:%1").arg(++m_serial), name, identity};
    entry.name = name; entry.size = s.st_size; entry.settling = settling;
    entry.stamp = stamp(s); entry.quietChecks = 0;
    entry.deadline = Ambient::nowUs() / 1000 + (settling ? m_quietMs : m_idleMs);
}
void IncomingFileProvider::drain() {
    alignas(inotify_event) char buffer[16384];
    bool changed = false;
    for (;;) {
        const auto count = ::read(m_fd, buffer, sizeof(buffer));
        if (count < 0 && errno == EINTR) continue;
        if (count <= 0) break;
        for (qsizetype offset = 0; offset < count;) {
            const auto *event = reinterpret_cast<const inotify_event *>(buffer + offset);
            offset += sizeof(inotify_event) + event->len;
            const QString name = event->len ? QFile::decodeName(event->name) : QString();
            if (event->mask & IN_Q_OVERFLOW) { arm(); changed = true; continue; }
            if (event->wd == m_parentWatch) {
                if (name == QFileInfo(m_directory).fileName()) { arm(); changed = true; }
                continue;
            }
            if (event->wd != m_watch) continue;
            if (event->mask & (IN_DELETE_SELF | IN_MOVE_SELF | IN_UNMOUNT | IN_IGNORED)) {
                m_watch = -1; m_entries.clear(); m_moves.clear(); changed = true; continue;
            }
            if (name.isEmpty() || (event->mask & IN_ISDIR)) continue;
            if ((event->mask & (IN_ATTRIB | IN_CLOSE_WRITE)) && !m_entries.contains(name)) continue;
            if (event->mask & IN_MOVED_FROM) {
                if (m_entries.contains(name)) {
                    auto old = m_entries.take(name);
                    old.deadline = Ambient::nowUs() / 1000 + 100;
                    m_moves.insert(event->cookie, old);
                }
            } else if (event->mask & IN_DELETE) m_entries.remove(name);
            else {
                if ((event->mask & IN_MOVED_TO) && m_moves.contains(event->cookie)) {
                    auto entry = m_moves.take(event->cookie);
                    if (entry.identity == Ambient::fileIdentity(QDir(m_directory).filePath(name)))
                        m_entries.insert(name, entry);
                }
                touch(name, event->mask & (IN_CLOSE_WRITE | IN_MOVED_TO));
            }
            changed = true;
        }
    }
    scheduleExpiry();
    if (changed) Q_EMIT this->changed();
}
void IncomingFileProvider::scheduleExpiry() {
    qint64 next = std::numeric_limits<qint64>::max();
    for (const auto &e : m_entries) next = qMin(next, e.deadline);
    for (const auto &e : m_moves) next = qMin(next, e.deadline);
    if (next == std::numeric_limits<qint64>::max()) m_expiry.stop();
    else m_expiry.start(int(qBound(qint64(1), next - Ambient::nowUs()/1000, qint64(60000))));
}
void IncomingFileProvider::expire() {
    // Quiet retirement is not completion. No success, percentage, Open or history.
    const auto now = Ambient::nowUs()/1000;
    for (auto it = m_entries.begin(); it != m_entries.end();) {
        auto &entry = it.value();
        if (entry.deadline > now) { ++it; continue; }
        const auto path = QDir(m_directory).filePath(entry.name);
        struct stat s{};
        const bool sameFile = !::lstat(QFile::encodeName(path).constData(), &s)
            && entry.identity == Ambient::fileIdentity(path);
        if (sameFile && stamp(s) != entry.stamp && entry.quietChecks++ == 0) {
            // One bounded recheck for metadata changed without a delivered write event.
            entry.stamp = stamp(s); entry.size = s.st_size;
            entry.deadline = now + m_quietMs; ++it;
        } else it = m_entries.erase(it);
    }
    m_moves.removeIf([now](const auto &e) { return e.value().deadline <= now; });
    scheduleExpiry(); Q_EMIT changed();
}
QVariantList IncomingFileProvider::activities() const {
    QVariantList rows;
    for (const auto &e : m_entries) {
        rows.append(QVariantMap{{QStringLiteral("id"), e.id}, {QStringLiteral("generation"), 1}, {QStringLiteral("kind"), QStringLiteral("transfer")},
            {QStringLiteral("state"), QStringLiteral("running")}, {QStringLiteral("source"), tr("Incoming file")}, {QStringLiteral("icon"), QStringLiteral("folder-download-symbolic")},
            {QStringLiteral("title"), e.name}, {QStringLiteral("observedSizeBytes"), e.size}, {QStringLiteral("evidence"), QStringLiteral("filesystem")},
            {QStringLiteral("arrivalState"), e.settling ? QStringLiteral("settling") : QStringLiteral("changing")},
            {QStringLiteral("destinationUrl"), QUrl::fromLocalFile(QDir(m_directory).filePath(e.name)).toString()},
            {QStringLiteral("fileIdentity"), e.identity}, {QStringLiteral("capabilities"), QVariantMap{{QStringLiteral("showInFiles"), true}}}});
    }
    return rows;
}
bool IncomingFileProvider::matchesFile(const QVariantMap &row) const {
    return !row.value(QStringLiteral("fileIdentity")).toString().isEmpty()
        && row.value(QStringLiteral("fileIdentity")).toString() == Ambient::fileIdentity(Ambient::localPath(row.value(QStringLiteral("destinationUrl"))));
}
void IncomingFileProvider::consume(const QString &id) {
    m_entries.removeIf([&id](const auto &e) { return e.value().id == id; });
    scheduleExpiry();
}
