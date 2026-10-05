#pragma once
#include <QJsonArray>
#include <QObject>
#include <QTimer>
class FileBrowser;
class TransferActivityBridge : public QObject {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "io.github.carlsonjm.Tettegouche.Activities1")
public:
    explicit TransferActivityBridge(FileBrowser *files, QObject *parent = nullptr);
public Q_SLOTS:
    QString snapshot() const;
    void cancel(const QString &id);
    void suspend(const QString &id);
    void resume(const QString &id);
Q_SIGNALS:
    void changed(const QString &snapshot);
private:
    QJsonArray rows() const;
    void publish();
    FileBrowser *m_files;
    QTimer m_pending;
    QJsonArray m_lastRows;
    bool m_published = false;
    quint64 m_revision = 0;
};
