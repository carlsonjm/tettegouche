#include "DesktopJobProvider.h"
#include "ActivityUtils.h"
#include <job.h>
#include <QTimer>
#include <QFileInfo>

using N = NotificationManager::Notifications;
DesktopJobProvider::DesktopJobProvider(QObject *parent) : QObject(parent),
    m_jobs(NotificationManager::JobsModel::createJobsModel()) {
    // Share Plasma's existing owner. Never call init() or compete for JobViewServer.
    connect(m_jobs.get(), &QAbstractItemModel::rowsInserted, this, &DesktopJobProvider::changed);
    connect(m_jobs.get(), &QAbstractItemModel::rowsRemoved, this, &DesktopJobProvider::changed);
    connect(m_jobs.get(), &QAbstractItemModel::dataChanged, this, &DesktopJobProvider::changed);
    connect(m_jobs.get(), &QAbstractItemModel::modelReset, this, [this] { ++m_generation; Q_EMIT changed(); });
    connect(m_jobs.get(), &NotificationManager::JobsModel::serviceOwnershipLost, this,
            [this] { ++m_generation; Q_EMIT changed(); });
    QTimer::singleShot(0, this, &DesktopJobProvider::changed);
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
        // destUrl is producer data. effectiveDestUrl/descriptionUrl may infer a path
        // from translated description text, so never use those for merging/actions.
        const auto url = job->destUrl();
        if (url.isLocalFile() && QFileInfo(url.toLocalFile()).isFile()) {
            row[QStringLiteral("destinationUrl")] = url.toString();
            row[QStringLiteral("fileIdentity")] = Ambient::fileIdentity(url.toLocalFile());
            row[QStringLiteral("title")] = QFileInfo(url.toLocalFile()).fileName();
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
