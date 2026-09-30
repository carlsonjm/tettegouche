#pragma once
#include <QDBusConnection>
#include <QHash>
#include <QObject>
#include <QTimer>
#include <QVariantList>

// The end of a transfer that earns a line: a file that arrived in Downloads
// brings the person something new, and a failure needs them. Such an end stays
// in Ambient for a minute, in the transfer's own place and with its action,
// then is filed as a notification of the transfer category, which the history
// keeps and the ticker does not play: that minute was its showing. One the
// person used in Ambient is filed at once. Any other end is quiet, since the
// person started it and saw it run.
class FinishNotices : public QObject {
    Q_OBJECT
public:
    FinishNotices(const QDBusConnection &bus, const QString &downloads, QObject *parent = nullptr, int lingerMs = 60000);
    // A job's end, as DesktopJobProvider::finished reports it.
    void report(const QVariantMap &job);
    // Ends still in Ambient, each in the place of the job it ended.
    QVariantList activities() const;
    // The person used this end in Ambient; it leaves and is filed at once.
    void used(const QString &id);
Q_SIGNALS:
    void changed();
    // Show in Files was chosen on an arrival's notice.
    void revealRequested(const QString &path);
private Q_SLOTS:
    void actionInvoked(uint id, const QString &action);
    void notificationClosed(uint id);
private:
    struct End { QString id, application, icon, desktopEntry, title, body, path; int generation = 0; bool failed = false; qint64 deadline = 0; };
    void expire();
    void notify(const End &end);
    QDBusConnection m_bus;
    QString m_downloads;
    int m_lingerMs;
    QList<End> m_lingering;
    QTimer m_expiry;
    // Each arrival's notice still open, and the file it shows.
    QHash<uint, QString> m_open;
};
