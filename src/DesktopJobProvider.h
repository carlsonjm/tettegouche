#pragma once
#include <QObject>
#include <QVariantList>
#include <jobsmodel.h>

class DesktopJobProvider : public QObject {
    Q_OBJECT
public:
    explicit DesktopJobProvider(QObject *parent = nullptr);
    QVariantList activities() const;
    void invoke(const QString &id, int generation, const QString &action);
Q_SIGNALS:
    void changed();
private:
    NotificationManager::JobsModel::Ptr m_jobs;
    int m_generation = 1;
};
