#pragma once
#include <QObject>
#include <QVariantList>
#include <QMap>
#include <QTimer>
#include <QSocketNotifier>

class IncomingFileProvider : public QObject {
    Q_OBJECT
public:
    explicit IncomingFileProvider(const QString &directory, QObject *parent = nullptr,
                                  int quietMs = 2000, int idleMs = 5000);
    ~IncomingFileProvider() override;
    QVariantList activities() const;
    bool valid() const { return m_watch >= 0; }
    void consume(const QString &id);
    bool matchesFile(const QVariantMap &row) const;
Q_SIGNALS:
    void changed();
private:
    struct Entry {
        QString id, name, identity;
        qint64 size = 0, deadline = 0;
        bool settling = false;
        QString stamp;
        int quietChecks = 0;
    };
    void drain();
    void arm();
    void touch(const QString &name, bool settling);
    void scheduleExpiry();
    void expire();
    QString m_directory;
    int m_fd = -1, m_watch = -1, m_parentWatch = -1;
    int m_quietMs, m_idleMs, m_serial = 0;
    QSocketNotifier *m_notifier = nullptr;
    QMap<QString, Entry> m_entries;
    QMap<quint32, Entry> m_moves;
    QTimer m_expiry;
};
