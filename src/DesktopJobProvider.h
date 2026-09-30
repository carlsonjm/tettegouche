#pragma once
#include <QObject>
#include <QSet>
#include <QVariantList>
#include <jobsmodel.h>

class QDBusServiceWatcher;

class DesktopJobProvider : public QObject {
    Q_OBJECT
public:
    explicit DesktopJobProvider(QObject *parent = nullptr);
    QVariantList activities() const;
    void invoke(const QString &id, int generation, const QString &action);
    // Whether Ambient holds the job service itself, as it does where no
    // Notifications widget runs to hold it.
    bool holding() const { return m_holding; }
Q_SIGNALS:
    void changed();
    // A job that ended while Ambient held the service: its id and generation
    // as its row had them, application, icon, summary, local destination file
    // and error. Where Plasma's widget holds
    // the service, it reports the ends of jobs itself.
    void finished(const QVariantMap &job);
private:
    void holdIfFree();
    void settleEnded();
    NotificationManager::JobsModel::Ptr m_jobs;
    QDBusServiceWatcher *m_owner = nullptr;
    QSet<uint> m_ended;
    bool m_holding = false, m_settlePending = false;
    int m_generation = 1;
};
