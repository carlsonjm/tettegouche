#include "FinishNotices.h"
#include "ActivityUtils.h"
#include <KLocalizedString>
#include <QDBusMessage>
#include <QDBusPendingCallWatcher>
#include <QDir>
#include <QFileInfo>
#include <QUrl>

namespace {
const QString Service = QStringLiteral("org.freedesktop.Notifications");
const QString Path = QStringLiteral("/org/freedesktop/Notifications");
// KIO's code for a job the person cancelled, which is no failure.
constexpr int Cancelled = 1;
qint64 nowMs() { return Ambient::nowUs() / 1000; }
}

FinishNotices::FinishNotices(const QDBusConnection &bus, const QString &downloads, QObject *parent, int lingerMs)
    : QObject(parent), m_bus(bus), m_downloads(QDir::cleanPath(downloads)), m_lingerMs(lingerMs) {
    m_expiry.setSingleShot(true);
    connect(&m_expiry, &QTimer::timeout, this, &FinishNotices::expire);
    m_bus.connect(Service, Path, Service, QStringLiteral("ActionInvoked"), this, SLOT(actionInvoked(uint,QString)));
    m_bus.connect(Service, Path, Service, QStringLiteral("NotificationClosed"), this, SLOT(notificationClosed(uint)));
}

void FinishNotices::report(const QVariantMap &job) {
    const int error = job.value(QStringLiteral("error")).toInt();
    const auto path = QUrl(job.value(QStringLiteral("destinationUrl")).toString()).toLocalFile();
    End end{job.value(QStringLiteral("id")).toString(), job.value(QStringLiteral("application")).toString(),
            job.value(QStringLiteral("icon")).toString(), job.value(QStringLiteral("desktopEntry")).toString(),
            {}, {}, {}, job.value(QStringLiteral("generation")).toInt()};
    if (error != 0 && error != Cancelled) {
        end.failed = true;
        end.title = i18n("Transfer failed");
        end.body = job.value(QStringLiteral("errorText")).toString();
        if (end.body.isEmpty()) end.body = job.value(QStringLiteral("summary")).toString();
    } else if (error == 0 && !path.isEmpty() && QFileInfo(path).absolutePath() == m_downloads) {
        end.path = path;
        end.title = QFileInfo(path).fileName();
        end.body = i18n("Arrived in Downloads");
    } else {
        return;
    }
    end.deadline = nowMs() + m_lingerMs;
    m_lingering.append(end);
    if (!m_expiry.isActive()) m_expiry.start(m_lingerMs);
    Q_EMIT changed();
}

QVariantList FinishNotices::activities() const {
    QVariantList rows;
    for (const auto &end : m_lingering) {
        QVariantMap row{{QStringLiteral("id"), end.id}, {QStringLiteral("generation"), end.generation},
            {QStringLiteral("kind"), QStringLiteral("transfer")}, {QStringLiteral("evidence"), QStringLiteral("job")},
            {QStringLiteral("state"), end.failed ? QStringLiteral("failed") : QStringLiteral("finished")},
            {QStringLiteral("source"), end.application}, {QStringLiteral("icon"), end.icon},
            {QStringLiteral("title"), end.title}, {QStringLiteral("description"), end.body},
            {QStringLiteral("capabilities"), QVariantMap{{QStringLiteral("showInFiles"), !end.path.isEmpty()}}}};
        if (!end.path.isEmpty()) {
            row[QStringLiteral("progress")] = 1.0;
            row[QStringLiteral("destinationUrl")] = QUrl::fromLocalFile(end.path).toString();
            row[QStringLiteral("fileIdentity")] = Ambient::fileIdentity(end.path);
        }
        rows.append(row);
    }
    return rows;
}

void FinishNotices::used(const QString &id) {
    for (auto it = m_lingering.begin(); it != m_lingering.end(); ++it) {
        if (it->id != id) continue;
        notify(*it);
        m_lingering.erase(it);
        Q_EMIT changed();
        return;
    }
}

void FinishNotices::expire() {
    const auto now = nowMs();
    qint64 next = 0;
    for (auto it = m_lingering.begin(); it != m_lingering.end();) {
        if (it->deadline > now) {
            next = next ? qMin(next, it->deadline) : it->deadline;
            ++it;
            continue;
        }
        notify(*it);
        it = m_lingering.erase(it);
    }
    if (next) m_expiry.start(int(qMax<qint64>(1, next - now)));
    Q_EMIT changed();
}

void FinishNotices::notify(const End &end) {
    const QStringList actions = end.path.isEmpty() ? QStringList()
        : QStringList{QStringLiteral("default"), QString(), QStringLiteral("show"), i18n("Show in Files")};
    // The freedesktop categories for a transfer's end.
    QVariantMap hints{{QStringLiteral("category"), end.failed ? QStringLiteral("transfer.error") : QStringLiteral("transfer.complete")}};
    if (!end.desktopEntry.isEmpty()) hints.insert(QStringLiteral("desktop-entry"), end.desktopEntry);
    if (!end.path.isEmpty()) hints.insert(QStringLiteral("x-kde-urls"), QStringList{QUrl::fromLocalFile(end.path).toString()});
    auto call = QDBusMessage::createMethodCall(Service, Path, Service, QStringLiteral("Notify"));
    call.setArguments({end.application, uint(0), end.icon, end.title, end.body, actions, hints, -1});
    auto *watcher = new QDBusPendingCallWatcher(m_bus.asyncCall(call), this);
    const auto path = end.path;
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this, watcher, path] {
        watcher->deleteLater();
        const auto reply = watcher->reply();
        if (!path.isEmpty() && reply.type() == QDBusMessage::ReplyMessage) m_open.insert(reply.arguments().value(0).toUInt(), path);
    });
}

void FinishNotices::actionInvoked(uint id, const QString &action) {
    const auto found = m_open.constFind(id);
    if (found == m_open.cend()) return;
    if (action == QLatin1String("show") || action == QLatin1String("default")) Q_EMIT revealRequested(*found);
}

void FinishNotices::notificationClosed(uint id) {
    m_open.remove(id);
}
