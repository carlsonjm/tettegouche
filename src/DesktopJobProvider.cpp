#include "DesktopJobProvider.h"
#include "ActivityUtils.h"
#include <job.h>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusPendingCallWatcher>
#include <QDBusServiceWatcher>
#include <QDir>
#include <QTimer>
#include <QFileInfo>
#include <QUrl>

using N = NotificationManager::Notifications;
namespace {
const QString JobService = QStringLiteral("org.kde.JobViewServer");
// The one local file a job wrote, from what its producer reported and what is
// on disk. A destination that is a folder, as KDE Connect reports one, counts
// only with a description value naming a regular file directly inside it; the
// values' labels are translated and never read.
QString writtenFile(const NotificationManager::Job &job) {
    const auto url = job.destUrl();
    if (!url.isLocalFile()) return {};
    const QFileInfo destination(url.toLocalFile());
    if (destination.isFile()) return destination.absoluteFilePath();
    if (!destination.isDir() || job.totalFiles() > 1) return {};
    const auto folder = QDir::cleanPath(destination.absoluteFilePath());
    for (const auto &value : {job.descriptionValue2(), job.descriptionValue1()}) {
        const QFileInfo named(value.startsWith(QLatin1String("file:")) ? QUrl(value).toLocalFile() : value);
        if (QDir::isAbsolutePath(named.filePath()) && named.isFile() && QDir::cleanPath(named.absolutePath()) == folder)
            return named.absoluteFilePath();
    }
    return {};
}
}
DesktopJobProvider::DesktopJobProvider(QObject *parent) : QObject(parent),
    m_jobs(NotificationManager::JobsModel::createJobsModel()) {
    // Plasma's Notifications widget holds the job service where it runs, and
    // this provider shares its model. Where nothing holds it, as in a panel
    // without that widget, applications would report their transfers to
    // nobody, so Ambient holds it, and then also clears the jobs that end.
    const auto update = [this] {
        if (m_holding && !m_settlePending) {
            m_settlePending = true;
            QTimer::singleShot(0, this, &DesktopJobProvider::settleEnded);
        }
        Q_EMIT changed();
    };
    connect(m_jobs.get(), &QAbstractItemModel::rowsInserted, this, update);
    connect(m_jobs.get(), &QAbstractItemModel::rowsRemoved, this, &DesktopJobProvider::changed);
    connect(m_jobs.get(), &QAbstractItemModel::dataChanged, this, update);
    connect(m_jobs.get(), &QAbstractItemModel::modelReset, this, [this] { ++m_generation; Q_EMIT changed(); });
    connect(m_jobs.get(), &NotificationManager::JobsModel::serviceOwnershipLost, this, [this] {
        m_holding = false; ++m_generation; Q_EMIT changed();
    });
    m_owner = new QDBusServiceWatcher(JobService, QDBusConnection::sessionBus(),
                                      QDBusServiceWatcher::WatchForUnregistration, this);
    connect(m_owner, &QDBusServiceWatcher::serviceUnregistered, this, &DesktopJobProvider::holdIfFree);
    QTimer::singleShot(0, this, &DesktopJobProvider::holdIfFree);
    QTimer::singleShot(0, this, &DesktopJobProvider::changed);
}
void DesktopJobProvider::holdIfFree() {
    if (m_jobs->isValid()) return;
    auto call = QDBusMessage::createMethodCall(QStringLiteral("org.freedesktop.DBus"), QStringLiteral("/org/freedesktop/DBus"),
                                               QStringLiteral("org.freedesktop.DBus"), QStringLiteral("NameHasOwner"));
    call.setArguments({JobService});
    auto *watcher = new QDBusPendingCallWatcher(QDBusConnection::sessionBus().asyncCall(call), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this, watcher] {
        watcher->deleteLater();
        const auto reply = watcher->reply();
        if (reply.type() != QDBusMessage::ReplyMessage || reply.arguments().value(0).toBool() || m_jobs->isValid()) return;
        m_holding = m_jobs->init();
        if (m_holding) { ++m_generation; Q_EMIT changed(); }
    });
}
// Each job that ended is reported once, then closed: nothing else is there to
// close it, and a closed job leaves the model.
void DesktopJobProvider::settleEnded() {
    m_settlePending = false;
    if (!m_holding || !m_jobs->isValid()) return;
    for (int i = m_jobs->rowCount() - 1; i >= 0; --i) {
        const auto index = m_jobs->index(i, 0);
        const auto *job = m_jobs->data(index, N::JobDetailsRole).value<NotificationManager::Job *>();
        if (!job || job->state() != N::JobStateStopped || m_ended.contains(job->id())) continue;
        m_ended.insert(job->id());
        const auto written = writtenFile(*job);
        QVariantMap ended{{QStringLiteral("id"), QStringLiteral("job:%1").arg(job->id())}, {QStringLiteral("generation"), m_generation},
            {QStringLiteral("application"), job->applicationName()},
            {QStringLiteral("icon"), job->applicationIconName()}, {QStringLiteral("desktopEntry"), job->desktopEntry()},
            {QStringLiteral("summary"), job->summary()}, {QStringLiteral("error"), job->error()},
            {QStringLiteral("errorText"), job->errorText()}};
        if (!written.isEmpty()) ended[QStringLiteral("destinationUrl")] = QUrl::fromLocalFile(written).toString();
        Q_EMIT finished(ended);
        m_jobs->close(index);
    }
    m_ended.removeIf([this](uint id) {
        for (int i = 0; i < m_jobs->rowCount(); ++i) {
            const auto *job = m_jobs->data(m_jobs->index(i, 0), N::JobDetailsRole).value<NotificationManager::Job *>();
            if (job && job->id() == id) return false;
        }
        return true;
    });
}
QVariantList DesktopJobProvider::activities() const {
    QVariantList rows;
    if (!m_jobs->isValid()) return rows;
    for (int i = 0; i < m_jobs->rowCount(); ++i) {
        const auto index = m_jobs->index(i, 0);
        const auto *job = m_jobs->data(index, N::JobDetailsRole).value<NotificationManager::Job *>();
        if (!job || job->state() == N::JobStateStopped) continue;
        QVariantMap row{{QStringLiteral("id"), QStringLiteral("job:%1").arg(job->id())}, {QStringLiteral("generation"), m_generation},
            {QStringLiteral("kind"), QStringLiteral("transfer")}, {QStringLiteral("evidence"), QStringLiteral("job")},
            {QStringLiteral("source"), job->applicationName()}, {QStringLiteral("icon"), job->applicationIconName()},
            {QStringLiteral("title"), job->summary()},
            {QStringLiteral("state"), job->state() == N::JobStateSuspended ? QStringLiteral("suspended") : QStringLiteral("running")},
            {QStringLiteral("capabilities"), QVariantMap{{QStringLiteral("cancel"), job->killable()},
                {QStringLiteral("suspend"), job->suspendable() && job->state() == N::JobStateRunning},
                {QStringLiteral("resume"), job->suspendable() && job->state() == N::JobStateSuspended}}}};
        // Default zero percent is not evidence that a producer knows its total.
        if (job->totalBytes() > 0 || job->totalItems() > 0 || job->percentage() > 0)
            row[QStringLiteral("progress")] = qBound(0.0, job->percentage() / 100.0, 1.0);
        if (job->totalBytes() > 0) {
            row[QStringLiteral("processedBytes")] = job->processedBytes(); row[QStringLiteral("totalBytes")] = job->totalBytes();
        } else if (job->processedBytes() > 0) row[QStringLiteral("processedBytes")] = job->processedBytes();
        if (job->speed() > 0) row[QStringLiteral("bytesPerSecond")] = job->speed();
        row[QStringLiteral("description")] = job->text();
        // effectiveDestUrl/descriptionUrl may infer a path from translated
        // description text, so merging and actions use writtenFile alone.
        if (const auto written = writtenFile(*job); !written.isEmpty()) {
            row[QStringLiteral("destinationUrl")] = QUrl::fromLocalFile(written).toString();
            row[QStringLiteral("fileIdentity")] = Ambient::fileIdentity(written);
            row[QStringLiteral("title")] = QFileInfo(written).fileName();
        }
        rows.append(row);
    }
    return rows;
}
void DesktopJobProvider::invoke(const QString &id, int generation, const QString &action) {
    if (generation != m_generation || !m_jobs->isValid()) return;
    for (int i = 0; i < m_jobs->rowCount(); ++i) {
        const auto index = m_jobs->index(i, 0);
        const auto *job = m_jobs->data(index, N::JobDetailsRole).value<NotificationManager::Job *>();
        if (!job || id != QStringLiteral("job:%1").arg(job->id()) || job->state() == N::JobStateStopped) continue;
        if (action == QLatin1String("cancel") && job->killable()) m_jobs->kill(index);
        else if (action == QLatin1String("suspend") && job->suspendable() && job->state() == N::JobStateRunning) m_jobs->suspend(index);
        else if (action == QLatin1String("resume") && job->suspendable() && job->state() == N::JobStateSuspended) m_jobs->resume(index);
        return;
    }
}
