#pragma once
#include <QObject>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QSet>
#include <QVariantList>
class TetteTransferProvider : public QObject {
    Q_OBJECT
public:
    explicit TetteTransferProvider(const QDBusConnection &bus, QObject *parent = nullptr);
    QVariantList activities() const { return m_rows; }
    void invoke(const QString &id, int generation, const QString &action);
Q_SIGNALS:
    void changed();
    // A copy or move in Files failed, as DesktopJobProvider::finished reports
    // a job's end, once.
    void finished(const QVariantMap &job);
private Q_SLOTS:
    void ownerChanged(const QString &name, const QString &oldOwner, const QString &newOwner);
    void snapshotChanged(const QString &json, const QDBusMessage &message);
private:
    void apply(const QString &json);
    QDBusConnection m_bus;
    QString m_owner;
    QVariantList m_rows;
    int m_generation = 0;
    qint64 m_revision = -1;
    QSet<QString> m_reported;
};
